import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'app_router.dart';
import 'network/environment.dart';
import 'providers/agent_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/camera_provider.dart';
import 'providers/consultation_provider.dart';
import 'providers/security_provider.dart';
import 'providers/site_config_provider.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvironmentConfig.init();

  final authProvider = AuthProvider();
  final siteConfigProvider = SiteConfigProvider();
  final themeProvider = ThemeProvider();
  // Kick off session restoration from persisted JWT before first frame
  authProvider.tryAutoLogin();
  // Load hospital branding config
  siteConfigProvider.fetchConfig();
  // Restore a previously-chosen light/dark preference, if any
  themeProvider.loadSavedTheme();

  final router = buildAppRouter(authProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: siteConfigProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => AgentProvider()),
        ChangeNotifierProvider(create: (_) => ConsultationProvider()),
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => SecurityProvider()),
      ],
      child: MyApp(router: router),
    ),
  );
}

class MyApp extends StatelessWidget {
  final GoRouter router;
  const MyApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp.router(
          title: 'Healthcare Operations Copilot',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode,
          darkTheme: ThemeProvider.darkTheme,
          theme: ThemeProvider.lightTheme,
          routerConfig: router,
          // Session restoration is a brief, route-independent gate: show
          // the splash over whatever the router is about to resolve to,
          // rather than making it a redirect target (which would flash
          // the real route in the URL bar before restoration finishes).
          builder: (context, child) {
            final auth = context.watch<AuthProvider>();
            if (!auth.isRestoringSession) return child ?? const SizedBox();
            return Consumer<SiteConfigProvider>(
              builder: (context, siteConfig, _) {
                return Scaffold(
                  backgroundColor: const Color(0xFF041329),
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (siteConfig.fullLogoUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              siteConfig.fullLogoUrl!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.shield,
                                  size: 56,
                                  color: Color(0xFF38debb)),
                            ),
                          )
                        else
                          const Icon(Icons.shield,
                              size: 56, color: Color(0xFF38debb)),
                        const SizedBox(height: 24),
                        Text(
                          siteConfig.hospitalName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Color(0xFF38debb),
                            strokeWidth: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ── Glassmorphic UI helpers ──────────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).cardColor;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2);
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(
                  alpha: isDark ? 0.6 : 0.9), // surface-container
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor,
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          color: Theme.of(context).scaffoldBackgroundColor, // Theme-aware base
        ),
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 600,
            height: 600,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  scheme.primary.withValues(alpha: 0.05), // Primary accent leak
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 120.0, sigmaY: 120.0),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          left: 40,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.secondary
                  .withValues(alpha: 0.05), // Secondary accent leak
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        SafeArea(child: child),
      ],
    );
  }
}
