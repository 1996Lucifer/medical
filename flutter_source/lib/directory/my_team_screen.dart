import 'dart:convert';

import 'package:flutter/material.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';

/// Everyone currently resolving (services/staff/hierarchy.py) to the
/// logged-in account as their effective head - reachable only from the
/// People Directory's "My team" action, which is itself only shown to
/// accounts AuthProvider.isHead reports true for (see
/// people_directory_screen.dart). A non-head account can still open this
/// route directly by URL/back-nav; the backend's GET /api/staff/my-team
/// already answers "not a head" with an empty list rather than an error,
/// so _EmptyOrErrorState's copy below is written to read correctly either
/// way ("nobody reports to you yet") instead of assuming the visitor is
/// definitely a head with zero reports.
class MyTeamScreen extends StatefulWidget {
  const MyTeamScreen({super.key});

  @override
  State<MyTeamScreen> createState() => _MyTeamScreenState();
}

enum _LoadState { loading, loaded, error }

class _MyTeamScreenState extends State<MyTeamScreen> {
  List<Map<String, dynamic>> _team = [];
  _LoadState _state = _LoadState.loading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final response = await NetworkManager.instance.get(ApiRoutes.myTeam);
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _state = _LoadState.error);
        return;
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      setState(() {
        _team = rows.cast<Map<String, dynamic>>()
          ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        _state = _LoadState.loaded;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _reassign(Map<String, dynamic> member) async {
    final departmentController =
        TextEditingController(text: member['department'] as String? ?? '');
    // A head reassigns within their own team, or hands someone off to a
    // named individual outside it (e.g. a nurse head assigning a nurse to
    // report directly to a specific doctor) - so the picker isn't limited
    // to the current team, it's every OTHER person on this team plus a
    // free-text "someone else" fallback kept deliberately simple: full
    // staff search is the manage_staff-gated admin dialog's job
    // (settings/manage_staff_screen.dart), not this narrower head view.
    int? reportsToId = member['reports_to_id'] as int?;
    final currentHeadName = member['reports_to_name'] as String?;

    Map<String, dynamic>? result;
    try {
      result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text('Reassign ${member['name']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: departmentController,
                  decoration: const InputDecoration(
                    labelText: 'Department / ward',
                    hintText: 'e.g. ICU',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: reportsToId,
                  decoration: const InputDecoration(labelText: 'Reports to'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Back to me (default)'),
                    ),
                    for (final other in _team)
                      if (other['id'] != member['id'])
                        DropdownMenuItem<int?>(
                          value: other['id'] as int,
                          child: Text(other['name'] as String,
                              overflow: TextOverflow.ellipsis),
                        ),
                  ],
                  onChanged: (val) => setD(() => reportsToId = val),
                ),
                if (currentHeadName != null) ...[
                  const SizedBox(height: 8),
                  Text('Currently under: $currentHeadName',
                      style: Theme.of(ctx).textTheme.bodySmall),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, {
                  'department': departmentController.text.trim().isEmpty
                      ? null
                      : departmentController.text.trim(),
                  'reports_to_id': reportsToId,
                }),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      departmentController.dispose();
    }

    if (result == null || !mounted) return;

    final response = await NetworkManager.instance.put(
      ApiRoutes.staffAssignment(member['id'] as int),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(result),
    );
    if (!mounted) return;

    if (response.statusCode == 200) {
      _load();
    } else {
      String detail = 'Could not update this assignment.';
      try {
        detail = (jsonDecode(response.body) as Map)['detail'] as String? ?? detail;
      } catch (_) {
        // Non-JSON error body (e.g. a raw 500 page) - keep the generic copy
        // above rather than surfacing transport internals to the user.
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My team')),
      body: switch (_state) {
        _LoadState.loading => const Center(child: CircularProgressIndicator()),
        _LoadState.error => _MessageState(
            icon: Icons.wifi_off,
            title: 'Couldn\'t load your team',
            subtitle: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        _LoadState.loaded when _team.isEmpty => const _MessageState(
            icon: Icons.groups_outlined,
            title: 'Nobody reports to you yet',
            subtitle: 'Staff assigned to your category or department, or '
                'anyone reassigned directly to you, will show up here.',
          ),
        _LoadState.loaded => RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _team.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final member = _team[i];
                final department = member['department'] as String?;
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: scheme.secondaryContainer,
                      child: Text(
                        (member['name'] as String).isNotEmpty
                            ? (member['name'] as String)[0].toUpperCase()
                            : '?',
                        style: TextStyle(color: scheme.onSecondaryContainer),
                      ),
                    ),
                    title: Text(member['name'] as String),
                    subtitle: Text(
                      [member['category'], if (department != null) department]
                          .whereType<String>()
                          .join(' · '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      tooltip: 'Reassign',
                      onPressed: () => _reassign(member),
                    ),
                  ),
                );
              },
            ),
          ),
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
