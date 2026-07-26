import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:frontend/settings/live_face_setup_screen.dart';
import 'package:http/http.dart' as http;

import '../network/network_manager.dart';
import '../network/api_routes.dart';
import '../main.dart' show GlassBackground, mainLayoutKey;
import '../widgets/shared_app_drawer.dart';

const Color _bgBase = Color(0xFF041329);
const Color _surfaceContainer = Color(0xFF112036);
const Color _surfaceContainerLow = Color(0xFF0d1c32);
const Color _surfaceContainerHigh = Color(0xFF1c2a41);
const Color _surfaceContainerHighest = Color(0xFF27354c);
const Color _tealAccent = Color(0xFF38debb);
const Color _textColor = Color(0xFFd6e3ff);
const Color _textVariant = Color(0xFFbacac3);
const Color _critical = Color(0xFFffb4ab);

class ManageStaffScreen extends StatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _activityList = [];
  String _searchQuery = '';
  bool _isLoading = true;

  List<Map<String, dynamic>> get _filteredStaffList {
    if (_searchQuery.isEmpty) return _staffList;
    final query = _searchQuery.toLowerCase();
    return _staffList.where((staff) {
      final name = (staff['name'] as String).toLowerCase();
      final role = (staff['role'] as String? ?? 'Medical Staff').toLowerCase();
      return name.contains(query) || role.contains(query);
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

  Widget _buildBackgroundBlobs(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -160,
          right: -160,
          child: Container(
            width: 384,
            height: 384,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: const Color(0xFF5ffbd6).withValues(alpha: 0.1), blurRadius: 120, spreadRadius: 40)
              ],
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).size.height / 2 - 160,
          left: -160,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: const Color(0xFF14d1ff).withValues(alpha: 0.05), blurRadius: 100, spreadRadius: 40)
              ],
            ),
          ),
        ),
      ],
    );
  }

  String getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }

  Widget _buildTopNav(bool isDesktop) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: _bgBase.withValues(alpha: 0.6),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isDesktop)
                Row(
                  children: [
                    Container(
                      width: 256,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF3c4a45).withValues(alpha: 0.3)),
                      ),
                      child: const TextField(
                        decoration: InputDecoration(
                          hintText: 'Global node search...',
                          hintStyle: TextStyle(color: _textVariant, fontSize: 14),
                          prefixIcon: Icon(Icons.search, color: _textVariant, size: 20),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 24),
                    const Icon(Icons.notifications_none, color: _textVariant),
                    const SizedBox(width: 24),
                    const Icon(Icons.settings_outlined, color: _textVariant),
                    const SizedBox(width: 24),
                    const Icon(Icons.security, color: _tealAccent),
                    const SizedBox(width: 24),
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _tealAccent, width: 2),
                        image: const DecorationImage(
                          image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuApGw8uvNeou2uMd2IGiiRGNvuWzdxR1KQHOIK5fTADCVEABVD4UbOKZ8LwK3Tm0oyUM7egXONirBrWOSPZOb2iz2pZXPYSKv3rkZ54igStb95QKeBi_yPgCH33BsgTv2aeH1MTw3lcYzZqk7o40mD6sggcuwsMVa4qKV9fcVBju6iIJ2E1jRPCNNyvgiYk8nqVah3Sbz_2Ypj9X8UxzSq11AXDSmh2FmGQlvUhY-EUIfYAw1f1s2D_D8yDog-KlVKfc-Dg3jUGkfU'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideNav() {
    return SharedAppDrawer(
      currentIndex: mainLayoutKey.currentState?.currentIndex ?? 0,
      popOnNavigate: true,
      onIndexChanged: (index) {
        mainLayoutKey.currentState?.changeTab(index);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: _bgBase,
      body: Stack(
        children: [
          _buildBackgroundBlobs(context),
          Positioned(
            top: 72,
            left: isDesktop ? 260 : 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 40.0 : 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isDesktop),
                  const SizedBox(height: 32),
                  _buildFilterBar(isDesktop),
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
              top: 0, left: 0, bottom: 0, width: 260,
              child: _buildSideNav(),
            ),
          Positioned(
            top: 0, left: isDesktop ? 260 : 0, right: 0, height: 72,
            child: _buildTopNav(isDesktop),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    if (!isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Staff Recognition Management',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Manage biometric profiles for AI facial recognition and tracking across secure sectors.',
              style: TextStyle(color: _textVariant, fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showRegisterNewStaffDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5ffbd6),
              foregroundColor: const Color(0xFF002019),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.person_add),
            label: const Text('Add New Staff', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Staff Recognition Management',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                  'Manage biometric profiles for AI facial recognition and tracking across secure sectors.',
                  style: TextStyle(color: _textVariant, fontSize: 18)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _showRegisterNewStaffDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5ffbd6),
            foregroundColor: const Color(0xFF002019),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 8,
            shadowColor: const Color(0xFF5ffbd6).withValues(alpha: 0.2),
          ),
          icon: const Icon(Icons.person_add),
          label: const Text('Add New Staff', style: TextStyle(fontWeight: FontWeight.bold)),
        )
      ],
    );
  }

  Widget _buildFilterBar(bool isDesktop) {
    final searchField = TextField(
      decoration: InputDecoration(
        hintText: 'Search by name, ID, or role...',
        hintStyle: const TextStyle(color: _textVariant),
        prefixIcon: const Icon(Icons.search, color: _textVariant),
        filled: true,
        fillColor: _surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _tealAccent),
        ),
      ),
      style: const TextStyle(color: Colors.white),
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
    );

    final dropdowns = Row(
      children: [
        Expanded(child: _buildDropdown('All Departments')),
        const SizedBox(width: 16),
        Expanded(child: _buildDropdown('Access Level')),
      ],
    );

    return StaffGlassCard(
      padding: const EdgeInsets.all(24),
      child: isDesktop
          ? Row(
              children: [
                Expanded(flex: 2, child: searchField),
                const SizedBox(width: 24),
                Expanded(flex: 1, child: dropdowns),
              ],
            )
          : Column(
              children: [
                searchField,
                const SizedBox(height: 16),
                dropdowns,
              ],
            ),
    );
  }

  Widget _buildDropdown(String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(color: Colors.white)),
          icon: const Icon(Icons.expand_more, color: _textVariant),
          dropdownColor: _surfaceContainerLow,
          items: const [],
          onChanged: (value) {},
        ),
      ),
    );
  }

  Widget _buildSidebarStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StaffGlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.monitor_heart, color: _tealAccent, size: 24),
                  SizedBox(width: 8),
                  Text('Recognition Health',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
              const SizedBox(height: 24),
              const Row(
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
                  color: Colors.white.withValues(alpha: 0.05),
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
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ACTIVE NODES',
                              style: TextStyle(
                                  color: _textVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('412',
                              style: TextStyle(
                                  color: Colors.white,
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
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TOTAL STAFF',
                              style: TextStyle(
                                  color: _textVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('${_staffList.isNotEmpty ? _staffList.length : 2840}',
                              style: const TextStyle(
                                  color: Colors.white,
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
                    border: Border.all(color: _tealAccent.withValues(alpha: 0.2))),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: _tealAccent, size: 12),
                    SizedBox(width: 12),
                    Text('All biometric clusters synced.',
                        style: TextStyle(color: _tealAccent, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        StaffGlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.priority_high, color: _critical, size: 24),
                  SizedBox(width: 8),
                  Text('Recent Activity',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
              const SizedBox(height: 16),
              if (_activityList.isEmpty)
                const Text('No recent activity.', style: TextStyle(color: _textVariant)),
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
              if (_activityList.isNotEmpty)
                const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text('VIEW ALL SYSTEM LOGS',
                      style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              )
            ],
          ),
        ),
      ],
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
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: _textVariant, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffGrid({required bool isDesktop}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _tealAccent));
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
          color: Colors.white.withValues(alpha: 0.1),
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
                 decoration: const BoxDecoration(
                   shape: BoxShape.circle,
                   color: _surfaceContainer,
                 ),
                 child: const Icon(Icons.add, size: 32, color: _textVariant),
               ),
               const SizedBox(height: 16),
               const Text('Onboard New Personnel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
               const SizedBox(height: 8),
               const Text('Initialize biometric capture for new hospital staff members.', textAlign: TextAlign.center, style: TextStyle(color: _textVariant, fontSize: 12)),
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

    return StaffGlassCard(
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
                      color: const Color(0xFF27354c),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      image: photoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(photoUrl),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: photoUrl == null
                        ? Center(
                            child: Text(
                                getInitials(staff['name'] as String),
                                style: const TextStyle(
                                    color: Colors.white,
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
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: needsRescan
                                  ? const Color(0xFF14d1ff).withValues(alpha: 0.1)
                                  : _tealAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: needsRescan
                                      ? const Color(0xFF14d1ff).withValues(alpha: 0.2)
                                      : _tealAccent.withValues(alpha: 0.2))),
                          child: Text(needsRescan ? 'PENDING' : 'VERIFIED',
                              style: TextStyle(
                                  color: needsRescan
                                      ? const Color(0xFF14d1ff)
                                      : _tealAccent,
                                  fontSize: 10,
                                  letterSpacing: -0.5,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Medical Staff',
                        style:
                            TextStyle(color: _textVariant, fontSize: 14)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: _tealAccent.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_open,
                              color: _tealAccent, size: 14),
                          SizedBox(width: 4),
                          Text('Level Access',
                              style: TextStyle(
                                  color: _tealAccent, fontSize: 11)),
                        ],
                      ),
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
                    needsRescan ? 'SCAN PROFILE' : 'UPDATE PHOTO',
                    () { _showStaffDetailsSheet(staff); },
                    isPrimary: needsRescan),
              ),
              const SizedBox(width: 8),
                Expanded(
                  child: _buildActionBtn(Icons.edit, 'EDIT PROFILE', () {
                    _editProfile(staff['id'] as int, staff['name'] as String, staff['role'] as String? ?? 'Medical Staff');
                  }),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(Icons.person_remove, 'REVOKE', () {
                  _deleteStaff(staff['id'] as int, staff['name'] as String);
                }, isDestructive: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, VoidCallback onTap,
      {bool isDestructive = false, bool isPrimary = false}) {
    final color = isDestructive ? _textVariant : (isPrimary ? _bgBase : _textVariant);
    final bgColor = isPrimary
        ? _tealAccent
        : _surfaceContainer;

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
                    color: isDestructive ? _textVariant : color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _showRegisterNewStaffDialog() async {
    final nameController = TextEditingController();
    String selectedRole = 'Medical Staff';
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Theme(
        data:
            ThemeData.dark().copyWith(dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Onboard New Personnel',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Provide a full name to begin Live Face Setup.',
                    style: TextStyle(color: _textVariant, fontSize: 14)),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  onChanged: (val) => setD(() {}),
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: ['Medical Staff', 'Head of Radiology', 'Oncology Lead', 'Security Specialist', 'Admin']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setD(() => selectedRole = val);
                  },
                  dropdownColor: _surfaceContainerHighest,
                ),
                if (isUploading)
                  const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: CircularProgressIndicator(color: _tealAccent)),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel',
                      style: TextStyle(color: _textVariant))),
              ElevatedButton(
                onPressed: (nameController.text.isEmpty || isUploading)
                    ? null
                    : () async {
                        setD(() => isUploading = true);
                        try {
                          final resp = await NetworkManager.instance
                              .post(ApiRoutes.staffSearch(nameController.text));
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            if (resp.statusCode == 200) {
                              final staffData = jsonDecode(resp.body);
                              final newStaffId = staffData['id'];

                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => LiveFaceSetupScreen(
                                        staffId: newStaffId)),
                              );

                              if (result == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            '✓ 3D Face Profile successfully registered!'),
                                        backgroundColor: Colors.green));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                        '✓ ${nameController.text} registered, but face setup was skipped.'),
                                    backgroundColor: Colors.orange));
                              }
                              _fetchStaff();
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
                    style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _editProfile(int staffId, String staffName, String staffRole) async {
    final nameController = TextEditingController(text: staffName);
    String selectedRole = staffRole.isNotEmpty ? staffRole : 'Medical Staff';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData.dark().copyWith(dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Full Name')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: ['Medical Staff', 'Head of Radiology', 'Oncology Lead', 'Security Specialist', 'Admin']
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
                  child: const Text('Cancel', style: TextStyle(color: _textVariant))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, {'name': nameController.text, 'role': selectedRole}),
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
      if (newName.isNotEmpty) {
        await NetworkManager.instance.put(
          ApiRoutes.staffMember(staffId),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': newName, 'role': newRole}),
        );
        _fetchStaff();
      }
    }
  }

  Future<void> _deleteStaff(int staffId, String staffName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data:
            ThemeData.dark().copyWith(dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: AlertDialog(
          title:
              const Text('Revoke Access', style: TextStyle(color: _critical)),
          content: Text(
              'Are you sure you want to completely remove $staffName? This action cannot be undone.',
              style: const TextStyle(color: _textVariant)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: _textVariant))),
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
                content: Text('✓ Staff member revoked'),
                backgroundColor: Colors.green));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Failed to delete: ${resp.statusCode}'),
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

class StaffGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const StaffGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24.0),
    this.borderRadius = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF112240).withValues(alpha: 0.6),
            border: const Border(
              top: BorderSide(color: Colors.white24),
              left: BorderSide(color: Colors.white24),
              bottom: BorderSide(color: Colors.black26),
              right: BorderSide(color: Colors.black26),
            ),
          ),
          child: child,
        ),
      ),
    );
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
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(radius)));

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

  Future<void> _startLiveSetup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveFaceSetupScreen(staffId: widget.staffId),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ 3D Face Profile successfully registered!'),
          backgroundColor: Colors.green));
      _fetchPhotos();
      widget.onUpdate();
    }
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
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
              'Upload photos from various angles to improve AI recognition accuracy.',
              style: TextStyle(color: _textVariant, fontSize: 14)),
          const SizedBox(height: 24),
          if (_isLoadingPhotos)
            const SizedBox(
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
                  border: Border.all(color: Colors.white10)),
              child: const Column(
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 48, color: Colors.white24),
                  SizedBox(height: 8),
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
                        border: Border.all(color: Colors.white10),
                        image: photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(photoUrl),
                                fit: BoxFit.cover)
                            : null,
                      ),
                      child: photoUrl == null
                          ? const Center(
                              child: Icon(Icons.image, color: Colors.white24))
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
                          style: const TextStyle(
                              color: Colors.white,
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
                          decoration: const BoxDecoration(
                              color: _critical, shape: BoxShape.circle),
                          child:
                              const Icon(Icons.close, size: 12, color: _bgBase),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          const SizedBox(height: 32),
          const Text('Guided 3D Registration (Recommended)',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
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
          const Divider(height: 1, thickness: 1, color: Colors.white10),
          const SizedBox(height: 24),
          const Text('Manual Fallback Registration',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      label: Text(label.replaceAll('_', ' '),
          style: const TextStyle(color: _textColor)),
      onPressed: () => _uploadAnglePhoto(label),
      backgroundColor: _surfaceContainerHigh,
      side: const BorderSide(color: Colors.white10),
    );
  }
}
