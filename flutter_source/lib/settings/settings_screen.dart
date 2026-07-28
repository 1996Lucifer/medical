import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../providers/auth_provider.dart';
import '../providers/site_config_provider.dart';
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
  static const Color _onPrimaryContainer = Color(0xFF00201a);

  void _showBrandingSettings(BuildContext context) {
    final siteConfig = Provider.of<SiteConfigProvider>(context, listen: false);
    final hospitalCtrl = TextEditingController(text: siteConfig.hospitalName);
    final agentCtrl = TextEditingController(text: siteConfig.agentName);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: GlassCard(
                borderRadius: 24.0,
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.palette_outlined, color: _primaryFixedDim, size: 24),
                            SizedBox(width: 12),
                            Text('Branding Settings',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _primary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Configure your hospital identity and AI agent name.',
                          style: TextStyle(fontSize: 14, color: _onSurfaceVariant)),
                        const SizedBox(height: 32),

                        // Hospital Logo Section
                        const Text('HOSPITAL LOGO',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1.5)),
                        const SizedBox(height: 12),
                        Consumer<SiteConfigProvider>(
                          builder: (context, config, _) {
                            return Row(
                              children: [
                                Container(
                                  width: 72, height: 72,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _primaryFixedDim.withValues(alpha: 0.3)),
                                  ),
                                  child: config.fullLogoUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          config.fullLogoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.broken_image, color: _onSurfaceVariant, size: 32),
                                        ),
                                      )
                                    : const Icon(Icons.add_photo_alternate_outlined, color: _onSurfaceVariant, size: 32),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.upload, size: 16),
                                      label: const Text('Upload Logo', style: TextStyle(fontSize: 13)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryFixedDim,
                                        foregroundColor: _onPrimaryContainer,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      ),
                                      onPressed: config.isLoading ? null : () async {
                                        final result = await FilePicker.platform.pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: ['png', 'jpg', 'jpeg', 'svg', 'webp'],
                                          withData: true,
                                        );
                                        if (result != null && result.files.first.bytes != null) {
                                          final file = result.files.first;
                                          final success = await config.uploadLogo(
                                            file.bytes!,
                                            file.name,
                                          );
                                          if (success && ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              const SnackBar(content: Text('Logo uploaded!')),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    if (config.fullLogoUrl != null) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        icon: Icon(Icons.delete_outline, size: 14, color: Colors.red[300]),
                                        label: Text('Remove', style: TextStyle(fontSize: 12, color: Colors.red[300])),
                                        onPressed: config.isLoading ? null : () async {
                                          final success = await config.deleteLogo();
                                          if (success && ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              const SnackBar(content: Text('Logo removed')),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 28),

                        // Hospital Name
                        const Text('HOSPITAL NAME',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: hospitalCtrl,
                          style: const TextStyle(color: _primary),
                          decoration: InputDecoration(
                            hintText: 'e.g. City General Hospital',
                            hintStyle: TextStyle(color: _onSurfaceVariant.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.2),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _primaryFixedDim),
                            ),
                            prefixIcon: Icon(Icons.local_hospital_outlined, color: _primaryFixedDim.withValues(alpha: 0.7)),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Agent Name
                        const Text('AI AGENT NAME',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: agentCtrl,
                          style: const TextStyle(color: _primary),
                          decoration: InputDecoration(
                            hintText: 'e.g. MedBot, Athena',
                            hintStyle: TextStyle(color: _onSurfaceVariant.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.2),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _primaryFixedDim),
                            ),
                            prefixIcon: Icon(Icons.smart_toy_outlined, color: _primaryFixedDim.withValues(alpha: 0.7)),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: const Text('Cancel', style: TextStyle(color: _onSurfaceVariant)),
                            ),
                            const SizedBox(width: 12),
                            Consumer<SiteConfigProvider>(
                              builder: (context, config, _) {
                                return ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryFixedDim,
                                    foregroundColor: _onPrimaryContainer,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                  ),
                                  onPressed: config.isLoading ? null : () async {
                                    final success = await config.updateConfig(
                                      hospitalName: hospitalCtrl.text.trim(),
                                      agentName: agentCtrl.text.trim(),
                                    );
                                    if (success && dialogCtx.mounted) {
                                      Navigator.of(dialogCtx).pop();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Branding updated successfully!'),
                                            backgroundColor: Color(0xFF27354c),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: config.isLoading
                                    ? const SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00382d)))
                                    : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _primary)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: _onSurfaceVariant)),
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
          'Settings',
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
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : 340,
                        child: _buildNavCard(
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
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 340,
                        child: _buildNavCard(
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
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 340,
                        child: _buildNavCard(
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
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 340,
                        child: _buildNavCard(
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
                      ),
                      Consumer<AuthProvider>(
                        builder: (context, auth, _) {
                          if (auth.role == 'superadmin') {
                            return SizedBox(
                              width: isMobile ? double.infinity : 340,
                              child: _buildNavCard(
                                title: 'Branding Settings',
                                subtitle: 'Configure hospital identity, logo, and AI agent naming.',
                                icon: Icons.palette_outlined,
                                onTap: () => _showBrandingSettings(context),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
