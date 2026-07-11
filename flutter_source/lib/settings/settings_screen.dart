import 'dart:convert';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'rbac_mapper_screen.dart';
import 'camera_management_screen.dart';
import 'analytics_screen.dart';
import 'manage_staff_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.6),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
              color: Colors.black.withValues(alpha: 0.05), height: 1.0),
        ),
      ),
      body: GlassBackground(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade50,
                        child: Icon(Icons.manage_accounts_rounded,
                            color: Colors.teal.shade700),
                      ),
                      title: const Text(
                        'Manage Staff',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A)),
                      ),
                      subtitle: const Text(
                          'Add, remove, or update staff photos for AI recognition'),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ManageStaffScreen()));
                      },
                    ),
                    const Divider(
                        height: 1, thickness: 1, indent: 20, endIndent: 20),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade50,
                        child: Icon(Icons.videocam_rounded,
                            color: Colors.teal.shade700),
                      ),
                      title: const Text(
                        'Manage Cameras',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A)),
                      ),
                      subtitle: const Text(
                          'Add or remove registered RTSP camera sources'),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const CameraManagementScreen()));
                      },
                    ),
                    const Divider(
                        height: 1, thickness: 1, indent: 20, endIndent: 20),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade50,
                        child: Icon(Icons.schema_rounded,
                            color: Colors.teal.shade700),
                      ),
                      title: const Text(
                        'Access Node Mapper',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A)),
                      ),
                      subtitle: const Text(
                          'Visually map users and groups to permissions (RBAC)'),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RBACMapperScreen()));
                      },
                    ),
                    const Divider(
                        height: 1, thickness: 1, indent: 20, endIndent: 20),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade50,
                        child: Icon(Icons.analytics_rounded,
                            color: Colors.teal.shade700),
                      ),
                      title: const Text(
                        'Analytics Dashboard',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A)),
                      ),
                      subtitle: const Text(
                          'View daily attendance, total hours, and system events'),
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AnalyticsScreen()));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
