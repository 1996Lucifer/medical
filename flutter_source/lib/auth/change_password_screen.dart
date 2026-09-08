import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/auth_provider.dart';

/// Forced gate shown instead of the main app when the signed-in account
/// still carries a system-generated temporary password (see
/// AuthProvider.mustChangePassword / routers/auth.py's
/// must_change_password flag) — most commonly a new staff member's first
/// login after onboarding. The app only proceeds past this once the
/// change succeeds; there is no skip/back option.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _isSubmitting = false;
  String? _error;

  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _error_ => Theme.of(context).colorScheme.error;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _error = "New passwords don't match.");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.changePassword(
      _currentPasswordController.text,
      _newPasswordController.text,
    );

    if (!mounted) return;
    if (!success) {
      setState(() {
        _error = auth.error ?? 'Could not change password.';
        _isSubmitting = false;
      });
      return;
    }
    // On success AuthProvider clears mustChangePassword and notifies — the
    // router (refreshListenable: authProvider) re-runs its redirect and
    // routes away from here on its own; nothing to navigate here.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassCard(
                padding: const EdgeInsets.all(40.0),
                borderRadius: 24.0,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_reset, size: 56, color: _primaryFixedDim),
                      const SizedBox(height: 16),
                      Text(
                        'Set a new password',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You are signed in with a temporary password. Choose '
                        'a new password to continue.',
                        style: TextStyle(color: _onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 28),
                      _buildTextField(
                        controller: _currentPasswordController,
                        label: 'Temporary password',
                        obscureText: _obscureCurrent,
                        onToggleObscure: () => setState(
                            () => _obscureCurrent = !_obscureCurrent),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _newPasswordController,
                        label: 'New password',
                        obscureText: _obscureNew,
                        onToggleObscure: () =>
                            setState(() => _obscureNew = !_obscureNew),
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
                        label: 'Confirm new password',
                        obscureText: _obscureNew,
                        onSubmitted: (_) => _submit(),
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
                                  'UPDATE PASSWORD',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              Provider.of<AuthProvider>(context, listen: false)
                                  .logout(),
                          child: Text('Sign out instead',
                              style: TextStyle(
                                  color: _onSurfaceVariant, fontSize: 13)),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
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
        prefixIcon: Icon(Icons.lock_outline,
            color: _primaryFixedDim.withValues(alpha: 0.7)),
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
