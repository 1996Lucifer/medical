import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../providers/auth_provider.dart';
import '../providers/site_config_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Aetheris Colors
  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _error => Theme.of(context).colorScheme.error;

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  /// A fresh deployment (no admin account created yet) gets redirected to
  /// the setup wizard instead of showing the login form — see
  /// routers/setup.py for why this replaced the old auto-created
  /// "admin"/"admin" behavior.
  Future<void> _checkSetupStatus() async {
    try {
      final res = await NetworkManager.instance.get(ApiRoutes.setupStatus);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['initialized'] == false && mounted) {
          context.go('/setup');
        }
      }
    } catch (e) {
      debugPrint("Setup status check error: $e");
    }
  }

  void _showRequestAccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Access'),
        content: const Text(
          'Accounts for this system are provisioned by your hospital '
          'administrator. Contact your IT/security administrator to '
          'have an account created for you.',
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
    if (Provider.of<AuthProvider>(context, listen: false).isLoading) return;
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
          backgroundColor: const Color(0xFF93000a), // error container
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
                              margin: const EdgeInsets.all(0),
                              decoration: BoxDecoration(
                                  color:
                                      _primaryFixedDim.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: _primaryFixedDim.withValues(
                                          alpha: 0.3),
                                      width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _primaryFixedDim.withValues(
                                          alpha: 0.2),
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
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.shield,
                                            size: 120,
                                            color: _primaryFixedDim),
                                      ),
                                    )
                                  : Icon(Icons.shield,
                                      size: 120, color: _primaryFixedDim),
                            ),
                            const SizedBox(height: 18),
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
                      'SECURE PERSONNEL LOGIN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _primaryFixedDim,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Personnel ID / Username',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _passwordController,
                      label: 'Security Key / Password',
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
                          backgroundColor: _primaryFixedDim,
                          foregroundColor:
                              const Color(0xFF00382d), // on-primary-fixed
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
                                'LOG IN',
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
                      child: Text("Request Access",
                          style: TextStyle(
                              color: _onSurfaceVariant, fontSize: 14)),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => context.go('/patient-login'),
                      icon: const Icon(Icons.favorite_border,
                          color: Color(0xFFffb4ab), size: 18),
                      label: const Text("Patient? Sign in to your portal",
                          style: TextStyle(
                              color: Color(0xFFffb4ab), fontSize: 13)),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 32),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text('DEV OVERRIDE (DEBUG)',
                          style: TextStyle(
                              color: _onSurfaceVariant,
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildRoleChip('Doctor', 'doctor'),
                          _buildRoleChip('Nurse', 'nurse'),
                          _buildRoleChip('Security', 'security'),
                          _buildRoleChip('Analyst', 'analyst'),
                          _buildRoleChip('Admin', 'admin'),
                          _buildRoleChip('SuperAdmin', 'superadmin'),
                        ],
                      ),
                    ]
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
        prefixIcon: Icon(icon, color: _primaryFixedDim.withValues(alpha: 0.7)),
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
          borderSide: BorderSide(color: _primaryFixedDim),
        ),
      ),
    );
  }

  Widget _buildRoleChip(String label, String username) {
    return ActionChip(
      label:
          Text(label, style: TextStyle(fontSize: 12, color: _primaryFixedDim)),
      backgroundColor: _primaryFixedDim.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _primaryFixedDim.withValues(alpha: 0.3)),
      ),
      onPressed: () {
        _usernameController.text = username;
        _passwordController.text = username;
        _login();
      },
    );
  }
}
