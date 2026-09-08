import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';

class AuthProvider extends ChangeNotifier {
  static const _tokenKey = 'jwt_access_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _isRestoringSession = true; // true until initial check completes
  String? _error;

  String? _role;
  List<String> _permissions = [];
  String? _username;
  bool _mustChangePassword = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  String? get error => _error;
  String? get role => _role;
  List<String> get permissions => _permissions;
  String? get username => _username;
  bool get mustChangePassword => _mustChangePassword;

  bool hasPermission(String perm) {
    if (_role == 'superadmin') return true;
    return _permissions.contains(perm);
  }

  void setAuthenticated(bool val) {
    _isAuthenticated = val;
    notifyListeners();
  }

  /// Attempt to restore a previous session from a persisted JWT token.
  /// Called once on app startup. If the token is valid the user skips login.
  Future<void> tryAutoLogin() async {
    _isRestoringSession = true;
    notifyListeners();

    try {
      String? storedToken;
      try {
        storedToken = await _storage.read(key: _tokenKey);
      } catch (e) {
        debugPrint("Storage read failed (WebCrypto issue?): $e");
      }

      if (storedToken == null || storedToken.isEmpty) {
        _isRestoringSession = false;
        notifyListeners();
        return;
      }

      // Set the token so NetworkManager can attach it to the /me request
      NetworkManager.instance.setToken(storedToken);

      final response = await NetworkManager.instance.get(ApiRoutes.authMe);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _role = data['role'];
        _username = data['username'];
        _permissions = (data['permissions'] as List).cast<String>();
        _mustChangePassword = data['must_change_password'] ?? false;
        _isAuthenticated = true;
      } else {
        // Token expired or invalid — clear it
        try {
          await _storage.delete(key: _tokenKey);
        } catch (_) {}
        NetworkManager.instance.clearToken();
      }
    } catch (e) {
      debugPrint("Auto-login failed: $e");
      // Network error — clear stored token so we don't loop
      try {
        await _storage.delete(key: _tokenKey);
      } catch (_) {}
      NetworkManager.instance.clearToken();
    }

    _isRestoringSession = false;
    notifyListeners();
  }

  Future<void> fetchMe() async {
    try {
      final response = await NetworkManager.instance.get(ApiRoutes.authMe);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _role = data['role'];
        _username = data['username'];
        _permissions = (data['permissions'] as List).cast<String>();
        _mustChangePassword = data['must_change_password'] ?? false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching /me: $e");
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await NetworkManager.instance.post(
        ApiRoutes.login,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        NetworkManager.instance.setToken(token);

        // Persist the token for session survival across refreshes
        try {
          await _storage.write(key: _tokenKey, value: token);
        } catch (e) {
          debugPrint("Storage write failed (WebCrypto issue?): $e");
        }

        _isAuthenticated = true;

        _role = data['role'];
        _username = data['username'];
        _mustChangePassword = data['must_change_password'] ?? false;
        await fetchMe();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        try {
          final data = jsonDecode(response.body);
          _error = data['detail']?.toString() ?? 'Login failed.';
        } catch (_) {
          _error = 'Login failed (${response.statusCode}).';
        }
      }
    } catch (e) {
      _error = 'Network error: $e';
      log("====> $e");
      rethrow;
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    _error = null;
    try {
      final response = await NetworkManager.instance.post(
        ApiRoutes.changePassword,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        _mustChangePassword = false;
        notifyListeners();
        return true;
      }

      try {
        final data = jsonDecode(response.body);
        _error = data['detail']?.toString() ?? 'Failed to change password.';
      } catch (_) {
        _error = 'Failed to change password.';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      notifyListeners();
      return false;
    }
  }

  void logout() async {
    _isAuthenticated = false;
    _role = null;
    _username = null;
    _permissions = [];
    _mustChangePassword = false;
    NetworkManager.instance.clearToken();
    // Remove persisted token
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    notifyListeners();
  }
}
