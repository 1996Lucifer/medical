import 'dart:convert';
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

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  String? get error => _error;
  String? get role => _role;
  List<String> get permissions => _permissions;
  String? get username => _username;

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
      final storedToken = await _storage.read(key: _tokenKey);
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
        _isAuthenticated = true;
      } else {
        // Token expired or invalid — clear it
        await _storage.delete(key: _tokenKey);
        NetworkManager.instance.clearToken();
      }
    } catch (e) {
      debugPrint("Auto-login failed: $e");
      // Network error — clear stored token so we don't loop
      await _storage.delete(key: _tokenKey);
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
        await _storage.write(key: _tokenKey, value: token);

        _isAuthenticated = true;

        _role = data['role'];
        _username = data['username'];
        await fetchMe();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Login failed: ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  void logout() {
    _isAuthenticated = false;
    _role = null;
    _username = null;
    _permissions = [];
    NetworkManager.instance.clearToken();
    // Remove persisted token
    _storage.delete(key: _tokenKey);
    notifyListeners();
  }
}
