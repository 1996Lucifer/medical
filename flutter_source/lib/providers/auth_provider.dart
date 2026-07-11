import 'dart:convert';
import 'package:flutter/material.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;
  
  String? _role;
  List<String> _permissions = [];
  String? _username;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
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
    NetworkManager.instance.setToken('');
    notifyListeners();
  }
}
