import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../call/call_models.dart';
import '../call/call_service.dart';
import '../call/chat_screen.dart';
import '../main.dart' show GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../providers/auth_provider.dart';
import 'my_team_screen.dart';

/// The chip value meaning "no staff-category filter applied". Also doubles
/// as the sentinel for "show patients instead of staff" via [_kPatients] -
/// both live in the exact same single chip row now, so there's only ever
/// one filter to reason about, not a category row stacked under a
/// separate patients/staff switcher.
const _kAllCategoriesFilter = 'All';
const _kPatients = 'Patients';

/// One directory for everyone a staff member might need to look up or
/// call: patients and staff (doctors included - a "Doctor" is just one
/// Staff.category value among others). A single row of filter chips -
/// Patients (if visible to this role) / All / Doctor / Nurse / ... derived
/// from whatever category values actually appear - replaces what used to
/// be two stacked filter rows (a Patients/Staff switcher on top of a
/// separate category row), which was one filter too many for what this
/// screen actually needs. What's visible is scoped by role:
///   - Admin/superadmin: all patients (view-only - only a patient's own
///     doctor can call them, see services/calls/authorization.py), all
///     staff/doctors - can call any of them freely.
///   - A doctor: the same screen, but "Patients" shows only their own
///     patients (from Consultation history) with working call buttons,
///     since that's who they're allowed to call.
///   - Any other staff role: no "Patients" chip at all (no patient
///     browsing) - just the staff category filters.
class PeopleDirectoryScreen extends StatefulWidget {
  const PeopleDirectoryScreen({super.key});

  @override
  State<PeopleDirectoryScreen> createState() => _PeopleDirectoryScreenState();
}

class _PeopleDirectoryScreenState extends State<PeopleDirectoryScreen> {
  List<dynamic> _staffItems = [];
  List<dynamic> _patientItems = [];
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';
  bool _initialized = false;

  // The single selected chip: _kPatients, _kAllCategoriesFilter, or a real
  // RBAC group name. Loaded up front along with staff/patients (see
  // _fetchData), so switching chips is instant client-side filtering, not
  // a fresh network round-trip each time.
  String _selectedFilter = _kAllCategoriesFilter;

  // The real, configured RBAC groups (routers/rbac.py's GET /groups) - the
  // filter chips must be exactly this list, not whatever category strings
  // happen to already exist on staff records. Found live: a stale/default
  // value like "Medical Staff" (never a real RBAC role - just leftover
  // placeholder text from staff registration) was showing up as its own
  // filter chip, and a real configured role with zero staff currently
  // assigned wouldn't show up as a chip at all.
  List<String> _rbacGroupNames = [];

  bool _canSeePatients(AuthProvider auth) {
    final isAdmin = auth.role == 'admin' || auth.role == 'superadmin';
    return isAdmin || auth.isDoctor;
  }

  List<String> get _availableFilters {
    final auth = context.read<AuthProvider>();
    final rest = <String>{
      if (_canSeePatients(auth)) _kPatients,
      ..._rbacGroupNames,
    }.toList()
      ..sort();
    // "All" always leads; everything else (Patients included) is
    // alphabetical after it, not grouped by kind.
    return [_kAllCategoriesFilter, ...rest];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _fetchData();
      context.read<CallService>().loadConversations();
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      final requests = <Future<_FetchResult>>[
        NetworkManager.instance
            .get(ApiRoutes.staff)
            .then((r) => _FetchResult('staff', r)),
        NetworkManager.instance
            .get(ApiRoutes.rbacGroups)
            .then((r) => _FetchResult('rbac_groups', r)),
        if (_canSeePatients(auth))
          NetworkManager.instance
              .get((auth.role == 'admin' || auth.role == 'superadmin')
                  ? ApiRoutes.patients()
                  : ApiRoutes.staffPatients(auth.staffId ?? 0))
              .then((r) => _FetchResult('patients', r)),
      ];
      final results = await Future.wait(requests);

      String? failure;
      List<dynamic> staff = _staffItems;
      List<dynamic> patients = _patientItems;
      List<String> rbacGroupNames = _rbacGroupNames;
      for (final result in results) {
        if (result.response.statusCode != 200) {
          // A failed RBAC-groups fetch shouldn't block the whole directory
          // from loading - it only degrades the category filter chips to
          // just "All"/"Patients", still usable.
          if (result.kind != 'rbac_groups') {
            failure = 'Failed to load directory.';
          }
          continue;
        }
        // GET /api/staff and GET /api/patients now return
        // {items, total, page, limit} instead of a bare list (see
        // routers/staff.py, routers/patients.py) - unwrap items. The
        // "patients" kind can also come from GET /api/staff/{id}/patients
        // (staffPatients), which is unpaginated and still a bare list, so
        // only unwrap when the body actually decoded to that paginated
        // shape.
        final decoded = jsonDecode(result.response.body);
        final data = decoded is Map<String, dynamic>
            ? decoded['items'] as List<dynamic>
            : decoded as List<dynamic>;
        if (result.kind == 'staff') {
          staff = data;
        } else if (result.kind == 'rbac_groups') {
          rbacGroupNames = data
              .cast<Map<String, dynamic>>()
              .map((g) => g['name'] as String)
              .toList();
        } else {
          patients = data;
        }
      }

      if (!mounted) return;
      setState(() {
        _staffItems = staff;
        _patientItems = patients;
        _rbacGroupNames = rbacGroupNames;
        _error = failure;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  bool get _showingPatients => _selectedFilter == _kPatients;

  List<dynamic> get _filteredItems {
    Iterable<dynamic> result;
    if (_showingPatients) {
      result = _patientItems;
    } else {
      // The logged-in user showing up in their own People Directory
      // (calling or messaging yourself makes no sense) - exclude whichever
      // entry's user_id matches the current account.
      final myUserId = context.read<AuthProvider>().userId;
      result = myUserId == null
          ? _staffItems
          : _staffItems.where((item) => item['user_id'] != myUserId);

      if (_selectedFilter != _kAllCategoriesFilter) {
        result = result.where((item) => item['category'] == _selectedFilter);
      }
    }

    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      result = result.where(
          (item) => (item['name'] as String? ?? '').toLowerCase().contains(q));
    }

    final sorted = result.toList()
      ..sort((a, b) => (a['name'] as String? ?? '')
          .toLowerCase()
          .compareTo((b['name'] as String? ?? '').toLowerCase()));
    return sorted;
  }

  bool get _canCallInCurrentFilter {
    // Admin can view all patients but per backend authorization can never
    // call one directly (only that patient's own doctor can) - the button
    // would just be a dead-end tap, so hide it entirely for that case.
    if (_showingPatients) {
      return context.read<AuthProvider>().isDoctor;
    }
    return true;
  }

  void _call(Map<String, dynamic> item, CallMode mode) {
    final userId = item['user_id'];
    if (userId == null) return;
    context.read<CallService>().startCall(
          CallPeer(userId: userId, name: item['name'] ?? ''),
          mode,
        );
  }

  void _message(Map<String, dynamic> item) {
    final userId = item['user_id'];
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(peerId: userId, peerName: item['name'] ?? ''),
      ),
    );
  }

  String _subtitle(Map<String, dynamic> item) {
    if (_showingPatients) {
      return item['mrn'] != null ? 'MRN: ${item['mrn']}' : 'No MRN on file';
    }
    return item['role'] ?? item['category'] ?? '';
  }

  IconData get _categoryIcon =>
      _showingPatients ? Icons.person_outline : Icons.badge_outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canCall = _canCallInCurrentFilter;
    final isHead = context.watch<AuthProvider>().isHead;
    // MainShell's own top bar + bottom nav tab label already convey
    // "what app / what section" on mobile, so this screen's own title
    // bar is redundant chrome there - drop it. Desktop keeps it as-is.
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isMobile
          ? null
          : AppBar(
              title: Text('People Directory',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: scheme.onSurface)),
              // No `leading` override: this is a normal top-level nav tab now
              // (see app_router.dart's kNavEntries), not a sub-page reached via
              // push - it gets the same "no back arrow, drawer hamburger on
              // mobile" treatment every other main tab gets.
              elevation: 0,
              backgroundColor: Colors.transparent,
              actions: [
                if (isHead)
                  IconButton(
                    icon: const Icon(Icons.groups_outlined),
                    tooltip: 'My team',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyTeamScreen()),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
      body: GlassBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search by name...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  // Mobile hides this screen's own AppBar (see isMobile
                  // above), so "My team" needs a second entry point here,
                  // next to the search field, rather than only living in
                  // the desktop AppBar's actions.
                  if (isMobile && isHead) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.groups_outlined),
                      tooltip: 'My team',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyTeamScreen()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final filter in _availableFilters)
                    ChoiceChip(
                      label: Text(filter),
                      selected: _selectedFilter == filter,
                      selectedColor: scheme.secondary.withValues(alpha: 0.2),
                      onSelected: (_) =>
                          setState(() => _selectedFilter = filter),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _fetchData,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : Builder(builder: (context) {
                          // Computed once per build, not once per grid
                          // item - _filteredItems re-runs the full
                          // filter+sort pass on every access, so calling
                          // it from itemCount AND itemBuilder (as before)
                          // was O(N) filter passes for N visible items
                          // instead of one.
                          final items = _filteredItems;
                          if (items.isEmpty) {
                            return const Center(child: Text('Nobody found.'));
                          }
                          return LayoutBuilder(
                            builder: (context, constraints) => GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 320,
                                mainAxisExtent: 150,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item =
                                    items[index] as Map<String, dynamic>;
                                final itemCanCall =
                                    canCall && item['can_call'] == true;
                                return Card(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    // Patient cards open the full chart
                                    // (reports + consultations); doctor/
                                    // staff cards don't have an
                                    // equivalent detail view, so they're
                                    // not tappable - calling is their
                                    // only action.
                                    onTap: _showingPatients
                                        ? () => context
                                            .go('/patients/${item['id']}')
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              _PersonAvatar(
                                                photoUrl: item['photo_url']
                                                    as String?,
                                                fallbackIcon: _categoryIcon,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item['name'] ?? '',
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      _subtitle(item),
                                                      style: TextStyle(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                          fontSize: 12),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          if (itemCanCall)
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                _MessageIconButton(
                                                  unreadCount: item['user_id']
                                                          is int
                                                      ? context
                                                          .watch<CallService>()
                                                          .unreadCountFor(
                                                              item['user_id']
                                                                  as int)
                                                      : 0,
                                                  onPressed: () =>
                                                      _message(item),
                                                ),
                                                const SizedBox(width: 12),
                                                IconButton(
                                                  padding: EdgeInsets.zero,
                                                  // Was BoxConstraints()
                                                  // (zeroed) - well under
                                                  // the ~44-48dp minimum
                                                  // touch target, easy to
                                                  // mis-tap the adjacent
                                                  // button on a dense card.
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 40,
                                                          minHeight: 40),
                                                  icon: Icon(Icons.call,
                                                      color: scheme.secondary,
                                                      size: 20),
                                                  tooltip: 'Audio call',
                                                  onPressed: () => _call(
                                                      item, CallMode.audio),
                                                ),
                                                const SizedBox(width: 12),
                                                IconButton(
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 40,
                                                          minHeight: 40),
                                                  icon: Icon(Icons.videocam,
                                                      color: scheme.secondary,
                                                      size: 20),
                                                  tooltip: 'Video call',
                                                  onPressed: () => _call(
                                                      item, CallMode.video),
                                                ),
                                              ],
                                            )
                                          else
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Text(
                                                _showingPatients && !canCall
                                                    ? 'View only'
                                                    : 'No portal access',
                                                style: TextStyle(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                    fontSize: 11),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

/// A directory card's avatar - the staff member's own enrolled photo when
/// they have one (StaffResponse.photo_url, same field manage_staff_screen
/// already renders), falling back to the plain category icon otherwise.
/// Patients never have a photo_url (no such field on PatientResponse), so
/// this always falls back to the icon for them.
class _PersonAvatar extends StatelessWidget {
  final String? photoUrl;
  final IconData fallbackIcon;

  const _PersonAvatar({required this.photoUrl, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullUrl = photoUrl != null ? '${ApiRoutes.baseUrl}$photoUrl' : null;
    return CircleAvatar(
      backgroundColor: scheme.secondary.withValues(alpha: 0.15),
      backgroundImage: fullUrl != null
          ? NetworkImage(fullUrl,
              headers: NetworkManager.instance.authHeaders())
          : null,
      child:
          fullUrl == null ? Icon(fallbackIcon, color: scheme.secondary) : null,
    );
  }
}

/// Tiny pairing so Future.wait's results can be told apart by which
/// endpoint they came from, without relying on list position.
class _FetchResult {
  final String kind;
  final http.Response response;
  _FetchResult(this.kind, this.response);
}

/// The directory's message icon with a small unread-count dot, fed by
/// CallService.loadConversations()/unreadCountFor - a plain
/// Icons.chat_bubble_outline gave zero indication a staff member had an
/// unread message waiting without opening every conversation to check.
class _MessageIconButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const _MessageIconButton(
      {required this.unreadCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Was a 20x20 SizedBox - that outer size wins over the IconButton's
    // own `constraints` (a tighter parent constraint always overrides a
    // child's preferred one), so the actual tap target was 20x20 - well
    // under the ~44-48dp minimum. 40x40 with the icon centered inside.
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.chat_bubble_outline,
                color: scheme.secondary, size: 20),
            // The unread dot below is otherwise color-only information -
            // folding the count into the tooltip/semantic label means a
            // screen reader (or a colorblind user hovering for the
            // tooltip) still gets it.
            tooltip:
                unreadCount > 0 ? 'Message ($unreadCount unread)' : 'Message',
            onPressed: onPressed,
          ),
          if (unreadCount > 0)
            Positioned(
              // The icon itself sits centered in this now-larger box (10px
              // margin on each side) - offset from that, not from the
              // box's own corner, so the dot stays anchored to the icon.
              right: 8,
              top: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
