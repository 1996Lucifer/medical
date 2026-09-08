import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../app_router.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../widgets/shared_app_drawer.dart';

/// /uploads is authenticated now (staff photos included) — attach the same
/// bearer token used for API calls so NetworkImage can still load them.
Map<String, String> _authHeaders() {
  final token = NetworkManager.instance.token;
  return token != null ? {'Authorization': 'Bearer $token'} : {};
}

class ManageStaffScreen extends StatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  // Theme-derived colors
  Color get _bgBase => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceContainer => Theme.of(context).colorScheme.surfaceContainer;
  Color get _surfaceContainerLow =>
      Theme.of(context).colorScheme.surfaceContainerLow;
  Color get _surfaceContainerHigh =>
      Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _surfaceContainerHighest =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _tealAccent => Theme.of(context).colorScheme.secondary;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _textVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _critical => Theme.of(context).colorScheme.error;

  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _activityList = [];
  String _searchQuery = '';
  String? _selectedDepartment;
  bool _isLoading = true;

  List<String> get _departmentOptions {
    final categories = _staffList
        .map((s) => (s['category'] as String?)?.trim())
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  List<Map<String, dynamic>> get _filteredStaffList {
    final query = _searchQuery.toLowerCase();
    return _staffList.where((staff) {
      final name = (staff['name'] as String).toLowerCase();
      final role = (staff['role'] as String? ?? 'Medical Staff');
      final category = (staff['category'] as String? ?? 'Medical Staff');
      final matchesQuery = query.isEmpty ||
          name.contains(query) ||
          role.toLowerCase().contains(query) ||
          category.toLowerCase().contains(query);
      final matchesDepartment =
          _selectedDepartment == null || category == _selectedDepartment;
      return matchesQuery && matchesDepartment;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchStaff();
  }

  Future<void> _fetchStaff() async {
    setState(() => _isLoading = true);
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.staff)
          .timeout(const Duration(seconds: 5));
      final activityResp = await NetworkManager.instance
          .get(ApiRoutes.staffActivity)
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _staffList = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
          if (activityResp.statusCode == 200) {
            _activityList = (jsonDecode(activityResp.body) as List<dynamic>)
                .cast<Map<String, dynamic>>();
          }
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
  }

  Widget _buildSideNav() {
    return const SharedAppDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: _bgBase,
      body: GlassBackground(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: isDesktop ? 260 : 0,
              right: 0,
              bottom: 0,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildHeader(isDesktop)),
                          const SizedBox(width: 24),
                          SizedBox(
                              width: 400, child: _buildFilterBar(isDesktop)),
                        ],
                      )
                    else ...[
                      _buildHeader(isDesktop),
                      const SizedBox(height: 24),
                      _buildFilterBar(isDesktop),
                    ],
                    const SizedBox(height: 32),
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildStaffGrid(isDesktop: true),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: _buildSidebarStats(),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          _buildStaffGrid(isDesktop: false),
                          const SizedBox(height: 32),
                          _buildSidebarStats(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (isDesktop)
              Positioned(
                top: 0,
                left: 0,
                bottom: 0,
                width: 260,
                child: _buildSideNav(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Staff Recognition Management',
            style: TextStyle(
                color: _textColor,
                fontSize: isDesktop ? 32 : 24,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
            'Manage biometric profiles for AI facial recognition and tracking across secure sectors.',
            style:
                TextStyle(color: _textVariant, fontSize: isDesktop ? 18 : 16)),
      ],
    );
  }

  static const double _filterControlHeight = 44;

  Widget _buildFilterBar(bool isDesktop) {
    final searchField = SizedBox(
      height: _filterControlHeight,
      child: TextField(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintText: 'Search by name, ID, or role...',
          hintStyle: TextStyle(color: _textVariant),
          prefixIcon: Icon(Icons.search, color: _textVariant, size: 20),
          filled: true,
          fillColor: _surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _textVariant.withValues(alpha: 0.4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _textVariant.withValues(alpha: 0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _tealAccent),
          ),
        ),
        style: TextStyle(color: _textColor),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );

    final departmentDropdown = _buildDropdown(
      hint: 'Departments',
      value: _selectedDepartment,
      items: _departmentOptions,
      onChanged: (value) => setState(() => _selectedDepartment = value),
    );

    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          searchField,
          const SizedBox(width: 16),
          departmentDropdown,
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: _filterControlHeight,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textVariant.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          isDense: true,
          value: value,
          hint: Text(hint,
              style: TextStyle(color: _textColor, fontSize: 13),
              overflow: TextOverflow.ellipsis),
          icon: Icon(Icons.expand_more, color: _textVariant, size: 20),
          dropdownColor: _surfaceContainerLow,
          items: [
            DropdownMenuItem<String?>(
                value: null,
                child: Text(hint,
                    style: TextStyle(color: _textColor, fontSize: 13))),
            ...items.map((item) => DropdownMenuItem<String?>(
                value: item,
                child: Text(item,
                    style: TextStyle(color: _textColor, fontSize: 13)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSidebarStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart, color: _tealAccent, size: 24),
                  const SizedBox(width: 8),
                  Text('Recognition Health',
                      style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Accuracy Rate',
                      style: TextStyle(color: _textVariant, fontSize: 14)),
                  Text('99.4%',
                      style: TextStyle(
                          color: _tealAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: _textVariant.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.994,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _tealAccent,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: _tealAccent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: _surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _textVariant.withValues(alpha: 0.05))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ACTIVE NODES',
                              style: TextStyle(
                                  color: _textVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('412',
                              style: TextStyle(
                                  color: _textColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: _surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _textVariant.withValues(alpha: 0.05))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TOTAL STAFF',
                              style: TextStyle(
                                  color: _textVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                              '${_staffList.isNotEmpty ? _staffList.length : 2840}',
                              style: TextStyle(
                                  color: _textColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _tealAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: _tealAccent.withValues(alpha: 0.2))),
                child: Row(
                  children: [
                    Icon(Icons.circle, color: _tealAccent, size: 12),
                    const SizedBox(width: 12),
                    Text('All biometric clusters synced.',
                        style: TextStyle(color: _tealAccent, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.priority_high, color: _critical, size: 24),
                  const SizedBox(width: 8),
                  Text('Recent Activity',
                      style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
              const SizedBox(height: 16),
              if (_activityList.isEmpty)
                Text('No recent activity.',
                    style: TextStyle(color: _textVariant)),
              ..._activityList.take(3).map((a) {
                final colorStr = a['color'] as String;
                Color color = _tealAccent;
                if (colorStr == 'green') color = Colors.green;
                if (colorStr == 'red') color = Colors.red;
                if (colorStr == 'orange') color = Colors.orange;

                return _buildActivityItem(
                  a['title'] as String,
                  a['subtitle'] as String,
                  color,
                );
              }),
              if (_activityList.isNotEmpty) const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _showAllActivityLogs,
                  child: Text('VIEW ALL SYSTEM LOGS',
                      style: TextStyle(
                          color: _textVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  void _showAllActivityLogs() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('All System Logs',
                      style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _activityList.isEmpty
                        ? Center(
                            child: Text('No activity recorded.',
                                style: TextStyle(color: _textVariant)))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _activityList.length,
                            itemBuilder: (ctx, i) {
                              final a = _activityList[i];
                              final colorStr = a['color'] as String? ?? '';
                              Color color = _tealAccent;
                              if (colorStr == 'green') color = Colors.green;
                              if (colorStr == 'red') color = Colors.red;
                              if (colorStr == 'orange') color = Colors.orange;
                              return _buildActivityItem(
                                a['title'] as String? ?? '',
                                a['subtitle'] as String? ?? '',
                                color,
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActivityItem(String title, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 2, height: 36, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: _textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: _textVariant, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffGrid({required bool isDesktop}) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _tealAccent));
    }

    final displayList = _filteredStaffList;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemCount = displayList.length + 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 400,
            mainAxisExtent: 210,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildAddNewStaffCard();
            }
            return _buildStaffCard(displayList[index - 1]);
          },
        );
      },
    );
  }

  Widget _buildAddNewStaffCard() {
    return InkWell(
      onTap: _showRegisterNewStaffDialog,
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: DashedRectPainter(
          color: _textVariant.withValues(alpha: 0.12),
          strokeWidth: 2,
          gap: 6,
          dash: 6,
          radius: 16,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _surfaceContainer,
                ),
                child: Icon(Icons.add, size: 32, color: _textVariant),
              ),
              const SizedBox(height: 16),
              Text('Onboard New Personnel',
                  style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                  'Initialize biometric capture for new hospital staff members.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textVariant, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> staff) {
    final photoUrl = staff['photo_url'] != null
        ? '${ApiRoutes.baseUrl}${staff['photo_url']}'
        : null;
    final photoCount = staff['photo_count'] ?? 1;
    final bool needsRescan = photoCount < 2;
    final String accountStatus = staff['status'] as String? ?? 'active';
    final bool isRevoked = accountStatus == 'inactive';

    return GlassCard(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _textVariant.withValues(alpha: 0.12)),
                      image: photoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(photoUrl,
                                  headers: _authHeaders()),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: photoUrl == null
                        ? Center(
                            child: Text(getInitials(staff['name'] as String),
                                style: TextStyle(
                                    color: _textColor,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)))
                        : null,
                  ),
                  Positioned(
                    bottom: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: _surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: needsRescan
                                  ? _critical.withValues(alpha: 0.5)
                                  : _tealAccent.withValues(alpha: 0.5))),
                      child: Text(needsRescan ? 'NEEDS RESCAN' : '99.8% MATCH',
                          style: TextStyle(
                              color: needsRescan ? _critical : _tealAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(staff['name'] as String,
                                style: TextStyle(
                                    color: _textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: needsRescan
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.1)
                                  : _tealAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: needsRescan
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.2)
                                      : _tealAccent.withValues(alpha: 0.2))),
                          child: Text(needsRescan ? 'PENDING' : 'VERIFIED',
                              style: TextStyle(
                                  color: needsRescan
                                      ? Theme.of(context).colorScheme.primary
                                      : _tealAccent,
                                  fontSize: 10,
                                  letterSpacing: -0.5,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        [
                          staff['category'] as String? ?? 'Medical Staff',
                          staff['role'] as String? ?? 'Medical Staff',
                        ].toSet().join(' · '),
                        style: TextStyle(color: _textVariant, fontSize: 14)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: _tealAccent.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_open,
                                  color: _tealAccent, size: 14),
                              const SizedBox(width: 4),
                              Text('Level Access',
                                  style: TextStyle(
                                      color: _tealAccent, fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildAccountStatusBadge(accountStatus),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                    needsRescan ? Icons.camera_enhance : Icons.camera_alt,
                    needsRescan ? 'SCAN PROFILE' : 'UPDATE PHOTO', () {
                  _showStaffDetailsSheet(staff);
                }, isPrimary: needsRescan),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(Icons.edit, 'EDIT PROFILE', () {
                  _editProfile(
                      staff['id'] as int,
                      staff['name'] as String,
                      staff['role'] as String? ?? 'Medical Staff',
                      staff['category'] as String? ?? 'Medical Staff');
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: isRevoked
                    ? _buildActionBtn(Icons.block, 'REVOKED', null,
                        isDestructive: true)
                    : _buildActionBtn(Icons.person_remove, 'REVOKE', () {
                        _deleteStaff(
                            staff['id'] as int, staff['name'] as String);
                      }, isDestructive: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountStatusBadge(String status) {
    late final Color color;
    late final String label;
    switch (status) {
      case 'active':
        color = _tealAccent;
        label = 'ACTIVE';
        break;
      case 'change_password':
        color = Colors.orangeAccent;
        label = 'CHANGE PASSWORD';
        break;
      case 'inactive':
        color = _critical;
        label = 'INACTIVE';
        break;
      case 'pending':
        color = _textVariant;
        label = 'PENDING';
        break;
      default:
        color = _textVariant;
        label = status.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, VoidCallback? onTap,
      {bool isDestructive = false, bool isPrimary = false}) {
    final color =
        isDestructive ? _textVariant : (isPrimary ? _bgBase : _textVariant);
    final bgColor = isPrimary ? _tealAccent : _surfaceContainer;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: isDestructive ? _textVariant : color, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: isDestructive ? _textVariant : color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _showGeneratedCredentialsDialog(
      String username, String tempPassword) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.vpn_key, color: _tealAccent),
              const SizedBox(width: 8),
              Text('Login Credentials Created',
                  style: TextStyle(
                      color: _textColor, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Share these with the new staff member. This temporary '
                  'password is shown only once and will be required to '
                  'change on first login.',
                  style: TextStyle(color: _textVariant, fontSize: 13)),
              const SizedBox(height: 20),
              _buildCredentialRow('Username', username),
              const SizedBox(height: 12),
              _buildCredentialRow('Temporary Password', tempPassword),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _tealAccent, foregroundColor: _bgBase),
              child: const Text("I've noted this down"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _textVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        color: _textVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        color: _textColor,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy, color: _textVariant, size: 18),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)));
            },
          ),
        ],
      ),
    );
  }

  static const List<String> _staffCategoryOptions = [
    'Medical Staff',
    'Doctor',
    'Nurse',
    'Security',
    'Morgue',
    'Administrative',
    'Support Staff',
  ];

  Future<void> _showRegisterNewStaffDialog() async {
    final nameController = TextEditingController();
    String selectedRole = 'Medical Staff';
    String selectedCategory = 'Medical Staff';
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: Text('Onboard New Personnel',
                style:
                    TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Provide a full name to begin Live Face Setup.',
                    style: TextStyle(color: _textVariant, fontSize: 14)),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  onChanged: (val) => setD(() {}),
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _staffCategoryOptions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setD(() => selectedCategory = val);
                  },
                  dropdownColor: _surfaceContainerHighest,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    'Medical Staff',
                    'Head of Radiology',
                    'Oncology Lead',
                    'Security Specialist',
                    'Admin'
                  ]
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setD(() => selectedRole = val);
                  },
                  dropdownColor: _surfaceContainerHighest,
                ),
                if (isUploading)
                  Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: CircularProgressIndicator(color: _tealAccent)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: _textVariant))),
              ElevatedButton(
                onPressed: (nameController.text.isEmpty || isUploading)
                    ? null
                    : () async {
                        setD(() => isUploading = true);
                        try {
                          final resp = await NetworkManager.instance.post(
                              ApiRoutes.registerStaff(nameController.text,
                                  selectedRole, selectedCategory));
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            if (resp.statusCode == 200) {
                              final staffData = jsonDecode(resp.body);
                              final newStaffId = staffData['id'];
                              final newUsername =
                                  staffData['username'] as String?;
                              final tempPassword =
                                  staffData['temp_password'] as String?;

                              if (newUsername != null &&
                                  tempPassword != null &&
                                  context.mounted) {
                                await _showGeneratedCredentialsDialog(
                                    newUsername, tempPassword);
                              }

                              // go() (not push()) so the URL reflects the
                              // live-setup screen; it navigates back here
                              // via context.go on its own completion/cancel,
                              // which remounts this screen fresh (refetching
                              // the just-onboarded staff member).
                              context.go(
                                  '$settingsStaffPath/$newStaffId/live-setup');
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      'Error registering staff (Code: ${resp.statusCode})'),
                                  backgroundColor: Colors.red));
                            }
                          }
                        } finally {
                          if (ctx.mounted) setD(() => isUploading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: _tealAccent, foregroundColor: _bgBase),
                child: const Text('Start Live Setup',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }),
      ),
    );
  }

  void _showStaffDetailsSheet(Map<String, dynamic> staff) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: _StaffDetailsView(
              staffId: staff['id'] as int,
              staffName: staff['name'] as String,
              onUpdate: () {
                _fetchStaff();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _editProfile(int staffId, String staffName, String staffRole,
      String staffCategory) async {
    final nameController = TextEditingController(text: staffName);
    String selectedRole = staffRole.isNotEmpty ? staffRole : 'Medical Staff';
    String selectedCategory =
        staffCategory.isNotEmpty ? staffCategory : 'Medical Staff';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: Text('Edit Profile', style: TextStyle(color: _textColor)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Full Name')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _staffCategoryOptions.contains(selectedCategory)
                      ? selectedCategory
                      : 'Medical Staff',
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _staffCategoryOptions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setD(() => selectedCategory = val);
                  },
                  dropdownColor: _surfaceContainerHighest,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    'Medical Staff',
                    'Head of Radiology',
                    'Oncology Lead',
                    'Security Specialist',
                    'Admin'
                  ]
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setD(() => selectedRole = val);
                  },
                  dropdownColor: _surfaceContainerHighest,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel', style: TextStyle(color: _textVariant))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, {
                        'name': nameController.text,
                        'role': selectedRole,
                        'category': selectedCategory,
                      }),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _tealAccent, foregroundColor: _bgBase),
                  child: const Text('Save')),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      final newName = result['name']!;
      final newRole = result['role']!;
      final newCategory = result['category']!;
      if (newName.isNotEmpty) {
        await NetworkManager.instance.put(
          ApiRoutes.staffMember(staffId),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(
              {'name': newName, 'role': newRole, 'category': newCategory}),
        );
        _fetchStaff();
      }
    }
  }

  Future<void> _deleteStaff(int staffId, String staffName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: AlertDialog(
          title: Text('Revoke Access', style: TextStyle(color: _critical)),
          content: Text(
              'This disables $staffName\'s login — they will no longer be '
              'able to sign in. Their profile and history are kept and can '
              'be reviewed here.',
              style: TextStyle(color: _textVariant)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: _textVariant))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _critical, foregroundColor: _bgBase),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Revoke',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        final resp = await NetworkManager.instance
            .delete(ApiRoutes.staffMember(staffId));
        if (resp.statusCode == 200) {
          _fetchStaff();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✓ Access revoked'),
                backgroundColor: Colors.green));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Failed to revoke access: ${resp.statusCode}'),
                backgroundColor: Colors.red));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }
}

class DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  DashedRectPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.gap = 5.0,
    this.dash = 5.0,
    this.radius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    var path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(radius)));

    Path dashPath = Path();
    for (PathMetric pathMetric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < pathMetric.length) {
        dashPath.addPath(
          pathMetric.extractPath(distance, distance + dash),
          Offset.zero,
        );
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _StaffDetailsView extends StatefulWidget {
  final int staffId;
  final String staffName;
  final VoidCallback onUpdate;

  const _StaffDetailsView({
    required this.staffId,
    required this.staffName,
    required this.onUpdate,
  });

  @override
  State<_StaffDetailsView> createState() => _StaffDetailsViewState();
}

class _StaffDetailsViewState extends State<_StaffDetailsView> {
  // Theme-derived colors
  Color get _bgBase => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceContainerLow =>
      Theme.of(context).colorScheme.surfaceContainerLow;
  Color get _surfaceContainerHigh =>
      Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _tealAccent => Theme.of(context).colorScheme.secondary;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _textVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _critical => Theme.of(context).colorScheme.error;

  List<Map<String, dynamic>> _photos = [];
  bool _isLoadingPhotos = true;

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
  }

  Future<void> _fetchPhotos() async {
    setState(() => _isLoadingPhotos = true);
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.staffPhotos(widget.staffId));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _photos = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _isLoadingPhotos = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingPhotos = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPhotos = false);
    }
  }

  Future<void> _deletePhoto(int photoId) async {
    final resp = await NetworkManager.instance
        .delete(ApiRoutes.staffPhotoDelete(widget.staffId, photoId));
    if (resp.statusCode == 200) {
      _fetchPhotos();
      widget.onUpdate();
    }
  }

  Future<void> _uploadAnglePhoto(String angleLabel) async {
    FilePickerResult? pickedFile = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (pickedFile == null) return;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Uploading $angleLabel photo...'),
        backgroundColor: _tealAccent));

    try {
      final request = NetworkManager.instance.multipartRequest(
          'POST', ApiRoutes.staffPhotoUpload(widget.staffId, angleLabel));
      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
            'file', pickedFile.files.single.bytes!,
            filename: pickedFile.files.single.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
            'file', pickedFile.files.single.path!));
      }
      final resp = await request.send();
      if (mounted) {
        if (resp.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✓ Photo uploaded successfully!'),
              backgroundColor: Colors.green));
          _fetchPhotos();
          widget.onUpdate();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Upload failed with status ${resp.statusCode}'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error uploading photo'),
            backgroundColor: Colors.red));
      }
    }
  }

  void _startLiveSetup() {
    // go() (not push()) so the URL reflects the live-setup screen; it
    // navigates back to /settings/staff on its own completion/cancel,
    // which remounts the staff list fresh.
    context.go('$settingsStaffPath/${widget.staffId}/live-setup');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${widget.staffName} Photos',
                  style: TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              IconButton(
                  icon: Icon(Icons.close, color: _textColor),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              'Upload photos from various angles to improve AI recognition accuracy.',
              style: TextStyle(color: _textVariant, fontSize: 14)),
          const SizedBox(height: 24),
          if (_isLoadingPhotos)
            SizedBox(
                height: 100,
                child: Center(
                    child: CircularProgressIndicator(color: _tealAccent)))
          else if (_photos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                  color: _surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: _textVariant.withValues(alpha: 0.12))),
              child: Column(
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 48, color: _textVariant.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  Text('No additional photos uploaded yet.',
                      style: TextStyle(color: _textVariant)),
                ],
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _photos.map((photo) {
                final photoUrl = photo['photo_url'] != null
                    ? '${ApiRoutes.baseUrl}${photo['photo_url']}'
                    : null;
                return Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: _surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _textVariant.withValues(alpha: 0.12)),
                        image: photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(photoUrl,
                                    headers: _authHeaders()),
                                fit: BoxFit.cover)
                            : null,
                      ),
                      child: photoUrl == null
                          ? Center(
                              child: Icon(Icons.image,
                                  color: _textVariant.withValues(alpha: 0.6)))
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: _bgBase.withValues(alpha: 0.8),
                          borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12)),
                        ),
                        child: Text(
                          (photo['label'] as String?)
                                  ?.replaceAll('_', ' ')
                                  .toUpperCase() ??
                              'PHOTO',
                          style: TextStyle(
                              color: _textColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _deletePhoto(photo['id'] as int),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: _critical, shape: BoxShape.circle),
                          child: Icon(Icons.close, size: 12, color: _bgBase),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          const SizedBox(height: 32),
          Text('Guided 3D Registration (Recommended)',
              style: TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 8),
          Text(
              'Record a short 5-second video slowly rolling your head around. The AI will automatically extract all necessary angles.',
              style: TextStyle(color: _textVariant, fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _startLiveSetup,
              icon: const Icon(Icons.camera_front),
              label: const Text('Start Live Interactive Setup',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _tealAccent.withValues(alpha: 0.1),
                foregroundColor: _tealAccent,
                elevation: 0,
                side: BorderSide(color: _tealAccent.withValues(alpha: 0.3)),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Divider(
              height: 1,
              thickness: 1,
              color: _textVariant.withValues(alpha: 0.12)),
          const SizedBox(height: 24),
          Text('Manual Fallback Registration',
              style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildUploadButton('front', Icons.face),
              _buildUploadButton('side_left', Icons.turn_left),
              _buildUploadButton('side_right', Icons.turn_right),
              _buildUploadButton('angled_down', Icons.arrow_downward),
              _buildUploadButton('other', Icons.more_horiz),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButton(String label, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: _textColor),
      label:
          Text(label.replaceAll('_', ' '), style: TextStyle(color: _textColor)),
      onPressed: () => _uploadAnglePhoto(label),
      backgroundColor: _surfaceContainerHigh,
      side: BorderSide(color: _textVariant.withValues(alpha: 0.12)),
    );
  }
}
