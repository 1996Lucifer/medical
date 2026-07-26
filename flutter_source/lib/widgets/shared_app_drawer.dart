import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class SharedAppDrawer extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final bool popOnNavigate;

  const SharedAppDrawer({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    this.popOnNavigate = false,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final List<NavigationDestination> destinations = [];

    if (auth.hasPermission('view_admin')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.grid_view),
        label: 'Command Center',
      ));
    }
    if (auth.hasPermission('view_patients')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.people_alt_outlined),
        label: 'Patients',
      ));
    }
    if (auth.hasPermission('view_consultation')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.medical_services_outlined),
        label: 'Consultation',
      ));
    }
    if (auth.hasPermission('view_camera')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.videocam_outlined),
        label: 'AI Camera',
      ));
    }
    if (auth.hasPermission('view_analytics')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.analytics_outlined),
        label: 'AI Analytics',
      ));
    }
    if (auth.hasPermission('view_security')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.lock_outline),
        label: 'Security Vault',
      ));
    }
    if (auth.hasPermission('view_agent')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        label: 'Agent',
      ));
    }
    if (auth.hasPermission('view_settings')) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.settings_system_daydream_outlined),
        label: 'System Health',
      ));
    }

    if (destinations.isEmpty) {
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.error),
        label: 'No Access',
      ));
    }

    const Color tealAccent = Color(0xFF64ffda);
    const Color surfaceBright = Color(0xFF2c3951);
    const Color textVariant = Color(0xFFbacac3);

    return Container(
      width: 260,
      color: const Color(0xFF071A33),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Row(
              children: [
                Icon(Icons.shield, color: tealAccent, size: 28),
                SizedBox(width: 12),
                Text(
                  'Aegis Hospital AI',
                  style: TextStyle(color: tealAccent, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceBright.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tealAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Core AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('PROTOCOL ACTIVE', style: TextStyle(color: tealAccent, fontSize: 10, letterSpacing: 0.5)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                final dest = destinations[index];
                final isActive = currentIndex == index;

                return InkWell(
                  onTap: () {
                    onIndexChanged(index);
                    if (popOnNavigate) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive ? tealAccent.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isActive ? const Border(left: BorderSide(color: tealAccent, width: 3)) : null,
                    ),
                    child: Row(
                      children: [
                        Icon((dest.icon as Icon).icon, color: isActive ? tealAccent : textVariant, size: 20),
                        const SizedBox(width: 16),
                        Text(
                          dest.label,
                          style: TextStyle(
                            color: isActive ? tealAccent : textVariant,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: InkWell(
              onTap: () {
                auth.logout();
                if (popOnNavigate) {
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              },
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.red[300], size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Sign Out',
                    style: TextStyle(color: Colors.red[300], fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
