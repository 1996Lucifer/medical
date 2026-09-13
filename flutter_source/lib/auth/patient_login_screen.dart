import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/auth_provider.dart';
import '../providers/site_config_provider.dart';

/// A dedicated login screen for patient-portal accounts - visually
/// identical shell to LoginScreen (same GlassCard/GlassBackground, same
/// branding) so it reads as part of the same product, but labeled and
/// framed for patients rather than hospital staff. Posts to the exact same
/// /api/auth/login - a patient account is just a User row with
/// role="patient" (see routers/patients.py's create-login endpoint), so
/// there's nothing patient-specific about the auth call itself, only the
/// framing and the post-login destination (app_router.dart routes
/// role=="patient" to /my-portal).
class PatientLoginScreen extends StatefulWidget {
  const PatientLoginScreen({super.key});

  @override
  State<PatientLoginScreen> createState() => _PatientLoginScreenState();
}

class _PatientLoginScreenState extends State<PatientLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _accent => Theme.of(context).colorScheme.secondary;
  Color get _error => Theme.of(context).colorScheme.error;

  void _showRequestAccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Need Portal Access?'),
        content: const Text(
          'Patient portal accounts are set up by hospital staff after your '
          'visit. Ask your doctor or the front desk to enable portal access '
          'for you, and they\'ll give you a username and temporary password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.error ?? 'Login failed',
              style: TextStyle(color: _error)),
          backgroundColor: const Color(0xFF93000a),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;

    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassCard(
                padding: const EdgeInsets.all(40.0),
                borderRadius: 24.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Consumer<SiteConfigProvider>(
                      builder: (context, siteConfig, _) {
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: _accent.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: _accent.withValues(alpha: 0.3),
                                      width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _accent.withValues(alpha: 0.2),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    )
                                  ]),
                              child: siteConfig.fullLogoUrl != null
                                  ? ClipOval(
                                      child: Image.network(
                                        siteConfig.fullLogoUrl!,
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.favorite_outline,
                                            size: 120,
                                            color: _accent),
                                      ),
                                    )
                                  : Icon(Icons.favorite_outline,
                                      size: 120, color: _accent),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              siteConfig.hospitalName,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: _primary,
                                letterSpacing: -0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'PATIENT PORTAL ACCESS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accent,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Username',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: const Color(0xFF00382d),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: isLoading ? null : _login,
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Color(0xFF00382d), strokeWidth: 2))
                            : const Text(
                                'ACCESS MY PORTAL',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: _showRequestAccessDialog,
                      child: Text("Don't have an account?",
                          style: TextStyle(
                              color: _onSurfaceVariant, fontSize: 14)),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: Icon(Icons.badge_outlined,
                          color: _onSurfaceVariant, size: 18),
                      label: Text("Hospital Staff? Sign in here",
                          style: TextStyle(
                              color: _onSurfaceVariant, fontSize: 13)),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    VoidCallback? onToggleObscure,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(color: _primary),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _onSurfaceVariant),
        prefixIcon: Icon(icon, color: _accent.withValues(alpha: 0.7)),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _onSurfaceVariant,
                ),
                onPressed: onToggleObscure,
              )
            : null,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.2),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _accent),
        ),
      ),
    );
  }
}
