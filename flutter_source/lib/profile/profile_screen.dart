import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../providers/auth_provider.dart';

/// The logged-in user's own account screen - reachable from the mobile top
/// bar's avatar button and, now, from the desktop sidebar's account card
/// (see shared_app_drawer.dart - it previously had no link to this screen
/// at all on desktop/web, despite the old doc comment here claiming
/// otherwise). Shows account info (username, role), the linked staff
/// profile's own name (view + edit, via GET/PUT /api/staff/me) when this
/// account has one, and lets the user change their own password, reusing
/// the exact same AuthProvider.changePassword call and validation rules
/// already proven in auth/change_password_screen.dart (that screen is a
/// forced first-login gate; this is the same action available any time).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _isSubmitting = false;
  bool _showPasswordForm = false;
  String? _error;
  String? _success;

  // Linked staff profile (view/edit side) - not every account has one
  // (e.g. a patient-portal login, or an admin account with no Staff row),
  // so this stays null rather than erroring the whole screen.
  bool _loadingStaffProfile = true;
  Map<String, dynamic>? _staffProfile;
  final _nameController = TextEditingController();
  bool _editingName = false;
  bool _savingName = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _loadStaffProfile();
  }

  Future<void> _loadStaffProfile() async {
    try {
      final response =
          await NetworkManager.instance.get(ApiRoutes.myStaffProfile);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _staffProfile = data;
          _nameController.text = data['name'] as String? ?? '';
          _loadingStaffProfile = false;
        });
      } else {
        // 404 (no linked staff record) is expected for some accounts -
        // not an error state, just nothing to show below.
        setState(() => _loadingStaffProfile = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingStaffProfile = false);
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name cannot be empty.');
      return;
    }
    setState(() {
      _savingName = true;
      _nameError = null;
    });
    try {
      final response = await NetworkManager.instance.put(
        ApiRoutes.myStaffProfile,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _staffProfile = data;
          _savingName = false;
          _editingName = false;
        });
      } else {
        setState(() {
          _savingName = false;
          _nameError = 'Failed to update name (${response.statusCode}).';
        });
      }
    } catch (e) {
      debugPrint('Failed to update staff name: $e');
      if (!mounted) return;
      setState(() {
        _savingName = false;
        _nameError = 'Could not update your name. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submitPasswordChange() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _error = "New passwords don't match.");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _success = null;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ok = await auth.changePassword(
      _currentPasswordController.text,
      _newPasswordController.text,
    );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      if (ok) {
        _success = 'Password updated.';
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _showPasswordForm = false;
      } else {
        _error = auth.error ?? 'Could not change password.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final username = auth.username ?? '—';
    final role = auth.role ?? 'user';
    final initials = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Builder(builder: (context) {
                          final photoUrl = _staffProfile?['photo_url'] as String?;
                          final fullUrl =
                              photoUrl != null ? '${ApiRoutes.baseUrl}$photoUrl' : null;
                          return CircleAvatar(
                            radius: 40,
                            backgroundColor: scheme.secondary.withValues(alpha: 0.15),
                            backgroundImage: fullUrl != null
                                ? NetworkImage(fullUrl,
                                    headers: NetworkManager.instance.authHeaders())
                                : null,
                            child: fullUrl == null
                                ? Text(initials,
                                    style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: scheme.secondary))
                                : null,
                          );
                        }),
                        const SizedBox(height: 12),
                        Text(username, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: scheme.onSurface)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.secondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(role.toUpperCase(),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: scheme.secondary)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_loadingStaffProfile)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    )
                  else if (_staffProfile != null) ...[
                    _buildStaffProfileCard(scheme),
                    const SizedBox(height: 20),
                  ],
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Security', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface, fontSize: 15)),
                            TextButton(
                              onPressed: () => setState(() {
                                _showPasswordForm = !_showPasswordForm;
                                _error = null;
                                _success = null;
                              }),
                              child: Text(_showPasswordForm ? 'Cancel' : 'Change password'),
                            ),
                          ],
                        ),
                        if (_success != null && !_showPasswordForm)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(_success!, style: TextStyle(color: Colors.green.shade600, fontSize: 12)),
                          ),
                        if (_showPasswordForm) ...[
                          const SizedBox(height: 12),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _buildPasswordField(
                                  controller: _currentPasswordController,
                                  label: 'Current password',
                                  obscureText: _obscureCurrent,
                                  onToggleObscure: () => setState(() => _obscureCurrent = !_obscureCurrent),
                                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                ),
                                const SizedBox(height: 12),
                                _buildPasswordField(
                                  controller: _newPasswordController,
                                  label: 'New password',
                                  obscureText: _obscureNew,
                                  onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
                                  validator: (v) {
                                    if (v == null || v.length < 8) return 'At least 8 characters';
                                    const weak = {'admin', 'password', '12345678', 'superadmin'};
                                    if (weak.contains(v.toLowerCase())) return 'Choose something harder to guess';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                _buildPasswordField(
                                  controller: _confirmPasswordController,
                                  label: 'Confirm new password',
                                  obscureText: _obscureNew,
                                  onSubmitted: (_) => _submitPasswordChange(),
                                  validator: (v) => v != _newPasswordController.text
                                      ? "New passwords don't match"
                                      : null,
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Text(_error!, style: TextStyle(color: scheme.error, fontSize: 12)),
                                ],
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isSubmitting ? null : _submitPasswordChange,
                                    child: _isSubmitting
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Update password'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => Provider.of<AuthProvider>(context, listen: false).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaffProfileCard(ColorScheme scheme) {
    final profile = _staffProfile!;
    final role = profile['role'] as String? ?? 'Medical Staff';
    final category = profile['category'] as String? ?? '';
    final shiftStart = profile['shift_start'] as String?;
    final shiftEnd = profile['shift_end'] as String?;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Profile',
                  style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface, fontSize: 15)),
              if (!_editingName)
                TextButton(
                  onPressed: () => setState(() => _editingName = true),
                  child: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_editingName) ...[
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Display name',
                errorText: _nameError,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _saveName(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _savingName
                        ? null
                        : () => setState(() {
                              _editingName = false;
                              _nameError = null;
                              _nameController.text = profile['name'] as String? ?? '';
                            }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _savingName ? null : _saveName,
                    child: _savingName
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ] else
            _profileRow(scheme, Icons.badge_outlined, 'Name', profile['name'] as String? ?? '—'),
          if (!_editingName) ...[
            const Divider(height: 24),
            _profileRow(scheme, Icons.medical_services_outlined, 'Role',
                category.isNotEmpty ? '$role · $category' : role),
            if (shiftStart != null && shiftEnd != null) ...[
              const Divider(height: 24),
              _profileRow(scheme, Icons.schedule, 'Shift', '$shiftStart – $shiftEnd'),
            ],
          ],
        ],
      ),
    );
  }

  Widget _profileRow(ColorScheme scheme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _buildPasswordField({
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
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: onToggleObscure,
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
