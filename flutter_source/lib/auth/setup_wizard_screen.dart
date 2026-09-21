import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

/// First-run setup for a fresh deployment. Replaces the old flow where the
/// login screen auto-created "admin"/"admin" with superadmin the instant
/// anyone opened it (see routers/setup.py for the backend side of this fix).
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hospitalNameController = TextEditingController();
  final _agentNameController = TextEditingController(text: 'AI');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _error;

  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _error_ => Theme.of(context).colorScheme.error;

  @override
  void dispose() {
    _hospitalNameController.dispose();
    _agentNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _error = "Passwords don't match.");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final res = await NetworkManager.instance.post(
        ApiRoutes.setupInitialize,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'hospital_name': _hospitalNameController.text.trim(),
          'agent_name': _agentNameController.text.trim().isEmpty
              ? 'AI'
              : _agentNameController.text.trim(),
          'admin_username': _usernameController.text.trim(),
          'admin_password': _passwordController.text,
        }),
      );

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Setup complete. Sign in with your new admin account.',
              style: TextStyle(color: _primary),
            ),
          ),
        );
        context.go('/login');
      } else {
        final body = jsonDecode(res.body);
        final detail = body['detail'];
        setState(() {
          _error = detail is List
              ? (detail.isNotEmpty ? detail.first['msg']?.toString() : null)
              : detail?.toString();
          _error ??= 'Setup failed (${res.statusCode}).';
        });
      }
    } catch (e) {
      debugPrint('Setup wizard submit failed: $e');
      setState(() => _error =
          'Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: GlassCard(
                padding: const EdgeInsets.all(40.0),
                borderRadius: 24.0,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield, size: 56, color: _primaryFixedDim),
                      const SizedBox(height: 16),
                      Text(
                        'Welcome — first-time setup',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This deployment has no admin account yet. Set up your '
                        'hospital and create the first administrator below — '
                        'this only runs once.',
                        style: TextStyle(color: _onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 28),
                      _sectionLabel('HOSPITAL DETAILS'),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _hospitalNameController,
                        label: 'Hospital name',
                        icon: Icons.local_hospital_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _agentNameController,
                        label: 'AI agent name (optional)',
                        icon: Icons.smart_toy_outlined,
                      ),
                      const SizedBox(height: 28),
                      _sectionLabel('ADMINISTRATOR ACCOUNT'),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _usernameController,
                        label: 'Admin username',
                        icon: Icons.person_outline,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Admin password',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        onToggleObscure: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                        validator: (v) {
                          if (v == null || v.length < 8) {
                            return 'At least 8 characters';
                          }
                          const weak = {
                            'admin',
                            'password',
                            '12345678',
                            'superadmin',
                          };
                          if (weak.contains(v.toLowerCase())) {
                            return 'Choose something harder to guess';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _confirmPasswordController,
                        label: 'Confirm password',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _submit(),
                        validator: (v) => v != _passwordController.text
                            ? "Passwords don't match"
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: TextStyle(color: _error_)),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryFixedDim,
                            foregroundColor: const Color(0xFF00382d),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: _isSubmitting ? null : _submit,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Color(0xFF00382d),
                                      strokeWidth: 2),
                                )
                              : const Text(
                                  'COMPLETE SETUP',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: _primaryFixedDim,
        letterSpacing: 1.2,
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(color: _primary),
      onFieldSubmitted: onSubmitted,
      validator: validator,
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
        fillColor: _onSurfaceVariant.withValues(alpha: 0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _onSurfaceVariant.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryFixedDim),
        ),
      ),
    );
  }
}
