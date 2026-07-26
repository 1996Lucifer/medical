import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart' show GlassCard, GlassBackground;
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
  // Aetheris colors
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _surfaceContainerLowest = Color(0xFF010e24);

  Widget _buildNavCard(
      {required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap,
      bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GlassCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isPrimary
                    ? _primaryFixedDim.withValues(alpha: 0.1)
                    : _surfaceContainerLowest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isPrimary
                        ? _primaryFixedDim.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.05)),
              ),
              child: Icon(icon, color: isPrimary ? _primaryFixedDim : Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _primary)),
                const SizedBox(height: 8),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 14, color: _onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(isPrimary ? 'Configure' : 'Access',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isPrimary ? _primaryFixedDim : _onSurfaceVariant)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward,
                    size: 16,
                    color: isPrimary ? _primaryFixedDim : _onSurfaceVariant)
              ],
            )
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Security Infrastructure',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.white.withValues(alpha: 0.05), height: 1.0),
        ),
      ),
      body: GlassBackground(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 24.0 : 40.0,
              vertical: isMobile ? 100.0 : 120.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('System Settings',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: _primary)),
              const SizedBox(height: 8),
              const Text(
                  'Configure AI recognition parameters, camera node clusters, and biometric staff access.',
                  style: TextStyle(fontSize: 16, color: _onSurfaceVariant)),
              const SizedBox(height: 40),
              Expanded(
                child: GridView.count(
                  crossAxisCount: isMobile ? 1 : 2,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                  childAspectRatio: isMobile ? 1.5 : 2.0,
                  children: [
                    _buildNavCard(
                        title: 'Manage Staff Recognition',
                        subtitle:
                            'Add, remove, or update staff photos for AI facial recognition and tracking.',
                        icon: Icons.badge,
                        isPrimary: true,
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ManageStaffScreen()));
                        }),
                    _buildNavCard(
                        title: 'Node Cluster: Camera Streams',
                        subtitle:
                            'Add or remove registered RTSP camera sources and monitor connection statuses.',
                        icon: Icons.videocam,
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const CameraManagementScreen()));
                        }),
                    _buildNavCard(
                        title: 'Access Node Mapper',
                        subtitle:
                            'Visually map users and groups to permissions across different clinical zones.',
                        icon: Icons.hub,
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RBACMapperScreen()));
                        }),
                    _buildNavCard(
                        title: 'Analytics Engine',
                        subtitle:
                            'View real-time efficiency metrics and AI detection logs for the entire facility.',
                        icon: Icons.analytics,
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AnalyticsScreen()));
                        }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
