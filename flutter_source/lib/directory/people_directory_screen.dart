import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../call/call_models.dart';
import '../call/call_service.dart';
import '../main.dart' show GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../providers/auth_provider.dart';

enum _DirectoryCategory { patients, doctors, staff }

extension on _DirectoryCategory {
  String get label {
    switch (this) {
      case _DirectoryCategory.patients:
        return 'Patients';
      case _DirectoryCategory.doctors:
        return 'Doctors';
      case _DirectoryCategory.staff:
        return 'Staff';
    }
  }
}

/// One directory for everyone a staff member might need to look up or
/// call: patients, doctors, and general staff, switched with choice chips
/// instead of being scattered across separate screens. What each viewer
/// sees is scoped by role:
///   - Admin/superadmin: all patients (view-only - only a patient's own
///     doctor can call them, see services/calls/authorization.py), all
///     doctors, all staff - can call any doctor/staff freely.
///   - A doctor: the SAME screen, but "Patients" shows only their own
///     patients (from Consultation history) with working call buttons,
///     since that's who they're allowed to call.
///   - Any other staff role: Doctors + Staff only (no patient browsing).
class PeopleDirectoryScreen extends StatefulWidget {
  const PeopleDirectoryScreen({super.key});

  @override
  State<PeopleDirectoryScreen> createState() => _PeopleDirectoryScreenState();
}

class _PeopleDirectoryScreenState extends State<PeopleDirectoryScreen> {
  _DirectoryCategory _category = _DirectoryCategory.staff;
  List<dynamic> _items = [];
  bool _isLoading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';
  bool _initialized = false;

  List<_DirectoryCategory> _availableCategories(AuthProvider auth) {
    final isAdmin = auth.role == 'admin' || auth.role == 'superadmin';
    final canSeePatients = isAdmin || auth.isDoctor;
    return [
      if (canSeePatients) _DirectoryCategory.patients,
      _DirectoryCategory.doctors,
      _DirectoryCategory.staff,
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final auth = context.read<AuthProvider>();
      final categories = _availableCategories(auth);
      _category = categories.contains(_DirectoryCategory.staff)
          ? _DirectoryCategory.staff
          : categories.first;
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      String url;
      switch (_category) {
        case _DirectoryCategory.patients:
          final isAdmin = auth.role == 'admin' || auth.role == 'superadmin';
          url = isAdmin
              ? ApiRoutes.patients()
              : ApiRoutes.staffPatients(auth.staffId ?? 0);
          break;
        case _DirectoryCategory.doctors:
          url = ApiRoutes.doctorsDirectory;
          break;
        case _DirectoryCategory.staff:
          url = ApiRoutes.staff;
          break;
      }
      final response = await NetworkManager.instance.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _items = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load directory.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filteredItems {
    if (_query.trim().isEmpty) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      return name.contains(q);
    }).toList();
  }

  bool get _canCallInCurrentCategory {
    // Admin can view all patients but per backend authorization can never
    // call one directly (only that patient's own doctor can) - the button
    // would just be a dead-end tap, so hide it entirely for that case.
    if (_category == _DirectoryCategory.patients) {
      final auth = context.read<AuthProvider>();
      return auth.isDoctor;
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

  String _subtitle(Map<String, dynamic> item) {
    switch (_category) {
      case _DirectoryCategory.patients:
        return item['mrn'] != null ? 'MRN: ${item['mrn']}' : 'No MRN on file';
      case _DirectoryCategory.doctors:
      case _DirectoryCategory.staff:
        return item['role'] ?? item['category'] ?? '';
    }
  }

  IconData get _categoryIcon {
    switch (_category) {
      case _DirectoryCategory.patients:
        return Icons.person_outline;
      case _DirectoryCategory.doctors:
        return Icons.medical_services_outlined;
      case _DirectoryCategory.staff:
        return Icons.badge_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;
    final categories = _availableCategories(auth);
    final canCall = _canCallInCurrentCategory;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('People Directory',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: scheme.onSurface)),
        // No `leading` override: this is a normal top-level nav tab now
        // (see app_router.dart's kNavEntries), not a sub-page reached via
        // push - it gets the same "no back arrow, drawer hamburger on
        // mobile" treatment every other main tab gets.
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: GlassBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final cat in categories)
                    ChoiceChip(
                      label: Text(cat.label),
                      selected: _category == cat,
                      selectedColor: scheme.secondary.withValues(alpha: 0.2),
                      onSelected: (_) {
                        setState(() => _category = cat);
                        _fetchData();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _filteredItems.isEmpty
                          ? const Center(child: Text('Nobody found.'))
                          : LayoutBuilder(
                              builder: (context, constraints) =>
                                  GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 320,
                                  mainAxisExtent: 150,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                                itemCount: _filteredItems.length,
                                itemBuilder: (context, index) {
                                  final item = _filteredItems[index]
                                      as Map<String, dynamic>;
                                  final itemCanCall =
                                      canCall && item['can_call'] == true;
                                  return Card(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      // Patient cards open the full chart
                                      // (reports + consultations); doctor/
                                      // staff cards don't have an
                                      // equivalent detail view, so they're
                                      // not tappable - calling is their
                                      // only action.
                                      onTap: _category ==
                                              _DirectoryCategory.patients
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
                                                CircleAvatar(
                                                  backgroundColor: scheme
                                                      .secondary
                                                      .withValues(alpha: 0.15),
                                                  child: Icon(_categoryIcon,
                                                      color: scheme.secondary),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item['name'] ?? '',
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        _subtitle(item),
                                                        style: TextStyle(
                                                            color: scheme
                                                                .onSurfaceVariant,
                                                            fontSize: 12),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
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
                                                  IconButton(
                                                    icon: Icon(Icons.call,
                                                        color: scheme.secondary,
                                                        size: 20),
                                                    tooltip: 'Audio call',
                                                    onPressed: () => _call(
                                                        item, CallMode.audio),
                                                  ),
                                                  IconButton(
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
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  _category ==
                                                              _DirectoryCategory
                                                                  .patients &&
                                                          !canCall
                                                      ? 'View only'
                                                      : 'No portal access',
                                                  style: TextStyle(
                                                      color: scheme
                                                          .onSurfaceVariant,
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
                            ),
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
