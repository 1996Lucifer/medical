import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../providers/auth_provider.dart';
import '../patient_portal/patient_dashboard_screen.dart' as patient_portal;

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
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _surfaceContainerHighest = Color(0xFF27354c);
  static const Color _error = Color(0xFFffb4ab);

  @override
  void initState() {
    super.initState();
    _checkSetupAdmin();
  }

  Future<void> _checkSetupAdmin() async {
    try {
      final res = await NetworkManager.instance.post(ApiRoutes.setupAdmin);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['msg'] == 'Admin created') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Default admin account created (admin/admin)', style: TextStyle(color: _primary)),
              backgroundColor: _surfaceContainerHighest,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Setup Admin Error: $e");
    }
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
          content: Text(authProvider.error ?? 'Login failed', style: const TextStyle(color: _error)),
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _primaryFixedDim.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: _primaryFixedDim.withValues(alpha: 0.3), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: _primaryFixedDim.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          )
                        ]
                      ),
                      child: const Icon(Icons.shield, size: 56, color: _primaryFixedDim),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Aegis Hospital AI',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
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
                      onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryFixedDim,
                          foregroundColor: const Color(0xFF00382d), // on-primary-fixed
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: isLoading ? null : _login,
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Color(0xFF00382d), strokeWidth: 2))
                            : const Text(
                                'INITIALIZE SECURE SESSION',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () {
                        // Request access
                      },
                      child: const Text("Request Access", style: TextStyle(color: _onSurfaceVariant, fontSize: 14)),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const patient_portal.PatientDashboardScreen(patientId: 1),
                          ),
                        );
                      },
                      icon: const Icon(Icons.favorite_border, color: Color(0xFFffb4ab), size: 18),
                      label: const Text("Enter Patient Portal (Demo)", style: TextStyle(color: Color(0xFFffb4ab), fontSize: 13)),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 32),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      const Text('DEV OVERRIDE (DEBUG)', style: TextStyle(color: _onSurfaceVariant, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
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
      style: const TextStyle(color: _primary),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _onSurfaceVariant),
        prefixIcon: Icon(icon, color: _primaryFixedDim.withValues(alpha: 0.7)),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
          borderSide: const BorderSide(color: _primaryFixedDim),
        ),
      ),
    );
  }

  Widget _buildRoleChip(String label, String username) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12, color: _primaryFixedDim)),
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
