import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_router.dart';
import '../providers/auth_provider.dart';
import '../providers/site_config_provider.dart';

/// The persistent side nav, reused both as the main shell's permanent
/// sidebar (desktop) / drawer (mobile), and standalone by settings
/// sub-pages that want the same "jump to another section" affordance
/// (see manage_staff_screen.dart). Active destination and navigation are
/// both derived from the current GoRouter location — there is no local
/// index to keep in sync with the URL, so it can't drift from what's
/// actually on screen the way the old int-based version could.
class SharedAppDrawer extends StatelessWidget {
  const SharedAppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final visibleEntries =
        kNavEntries.where((e) => auth.hasPermission(e.permission)).toList();

    final currentPath = GoRouterState.of(context).uri.path;

    final scheme = Theme.of(context).colorScheme;
    final Color tealAccent = scheme.secondary;
    final Color surfaceBright = scheme.surfaceBright;
    final Color textVariant = scheme.onSurfaceVariant;
    final Color textColor = scheme.onSurface;

    return Container(
      width: 260,
      // Slightly distinct from the main content background so the sidebar
      // reads as its own panel, same relationship the old hardcoded
      // 0xFF071A33-vs-0xFF041329 pairing had, but theme-aware now.
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Consumer<SiteConfigProvider>(
              builder: (context, siteConfig, _) {
                return Row(
                  children: [
                    if (siteConfig.fullLogoUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          siteConfig.fullLogoUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.shield, color: tealAccent, size: 64),
                        ),
                      )
                    else
                      Icon(Icons.shield, color: tealAccent, size: 64),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        siteConfig.hospitalName,
                        style: TextStyle(
                            color: tealAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceBright.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: textVariant.withValues(alpha: 0.15)),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Core AI',
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      Text('PROTOCOL ACTIVE',
                          style: TextStyle(
                              color: tealAccent,
                              fontSize: 10,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: visibleEntries.length,
              itemBuilder: (context, index) {
                final entry = visibleEntries[index];
                final isActive = currentPath == entry.path ||
                    currentPath.startsWith('${entry.path}/');

                return InkWell(
                  onTap: () {
                    Scaffold.maybeOf(context)?.closeDrawer();
                    context.go(entry.path);
                  },
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? tealAccent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isActive
                          ? Border(
                              left: BorderSide(color: tealAccent, width: 3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(entry.icon,
                            color: isActive ? tealAccent : textVariant,
                            size: 24),
                        const SizedBox(width: 16),
                        Text(
                          entry.label,
                          style: TextStyle(
                            color: isActive ? tealAccent : textVariant,
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.normal,
                            fontSize: 15,
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
                Scaffold.maybeOf(context)?.closeDrawer();
                auth.logout();
              },
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.red[300], size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Sign Out',
                    style: TextStyle(
                        color: Colors.red[300], fontWeight: FontWeight.bold),
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
