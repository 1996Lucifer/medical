import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../indoor_tracking/tracking_signal_service.dart';

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
  // The linked Staff/Patient record's real name, from /api/auth/me's
  // display_name - the login username is often a generated handle (e.g.
  // "dr.deepak"), not what should be shown as "you" in the sidebar/top
  // bar account card. Falls back to username itself when absent (older
  // cached /me responses, or an account with neither link).
  String? _displayName;
  bool _mustChangePassword = false;
  // The logged-in User.id itself - this is the identity used by the call
  // signaling WebSocket (see call/call_service.dart), distinct from
  // patient_id/staff_id below (which record, if any, this login is linked
  // to - lets the patient portal and doctor-side screens know "who am I"
  // without a separate lookup; see routers/auth.py's /me response).
  int? _userId;
  int? _patientId;
  int? _staffId;
  String? _staffCategory;
  bool _isHead = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get isRestoringSession => _isRestoringSession;
  String? get error => _error;
  String? get role => _role;
  List<String> get permissions => _permissions;
  String? get username => _username;
  String? get displayName => _displayName ?? _username;
  bool get mustChangePassword => _mustChangePassword;
  int? get userId => _userId;
  int? get patientId => _patientId;
  int? get staffId => _staffId;
  String? get staffCategory => _staffCategory;
  bool get isDoctor => _staffCategory == 'Doctor';
  // Whether this account leads a team (services/staff/hierarchy.py on the
  // backend) - gates the People Directory's "My Team" entry point so a
  // regular staff member never lands on a screen that's always empty for
  // them.
  bool get isHead => _isHead;

  bool hasPermission(String perm) {
    // An empty permission requirement means "every authenticated staff
    // login, no RBAC gate" - used for capabilities (like the Inbox) that
    // were never actually permission-gated in the first place (calling and
    // messaging staff/admins freely has always been unconditional, see
    // services/calls/authorization.can_call), so the nav entry that
    // surfaces them shouldn't invent a gate either.
    if (perm.isEmpty) return true;
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
        _displayName = data['display_name'];
        _permissions = (data['permissions'] as List).cast<String>();
        _mustChangePassword = data['must_change_password'] ?? false;
        _userId = data['id'];
        _patientId = data['patient_id'];
        _staffId = data['staff_id'];
        _staffCategory = data['staff_category'];
        _isHead = data['is_head'] ?? false;
        _isAuthenticated = true;
        _maybeStartTracking();
        _maybeWarmupCamera();
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
        _displayName = data['display_name'];
        _permissions = (data['permissions'] as List).cast<String>();
        _mustChangePassword = data['must_change_password'] ?? false;
        _userId = data['id'];
        _patientId = data['patient_id'];
        _staffId = data['staff_id'];
        _staffCategory = data['staff_category'];
        _isHead = data['is_head'] ?? false;
        notifyListeners();
        _maybeStartTracking();
        _maybeWarmupCamera();
      }
    } catch (e) {
      debugPrint("Error fetching /me: $e");
    }
  }

  /// Only staff accounts get tracked (attendance is a staff concept); a
  /// patient-portal or admin-only login never triggers it.
  void _maybeStartTracking() {
    if (_staffId != null) {
      TrackingSignalService.requestPermissions();
      TrackingSignalService.start();
    }
  }

  /// The AI vision models (InsightFace/YOLO) take ~30-60s to cold-load on
  /// first use. For any role that can actually see the camera feature,
  /// kick that load off right after login in the background instead of
  /// waiting for them to open the camera screen and eat the delay there.
  /// Fire-and-forget - failures are logged, never surfaced to the user,
  /// since the camera screen's own on-demand start still works as a
  /// fallback if this didn't get a chance to finish (or run at all).
  Future<void> _maybeWarmupCamera() async {
    if (!hasPermission('view_camera')) return;
    try {
      await NetworkManager.instance.post(ApiRoutes.camerasWarmup);
    } catch (e) {
      debugPrint("Camera warmup request failed (non-fatal): $e");
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
      // Neither call site (login_screen.dart, patient_login_screen.dart)
      // catches this - `rethrow` used to leave it as an unhandled async
      // exception AND skip the `_isLoading = false` below, permanently
      // stranding the login button in its spinner/disabled state on any
      // network failure. There is nothing for a caller to usefully catch
      // here that isn't already expressed by `_error` + the `false`
      // return value below, so this now behaves like the "bad
      // credentials" branch above instead of throwing.
      _error = 'Network error. Check your connection and try again.';
      log("Login network error: $e");
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
    TrackingSignalService.stop();
    _isAuthenticated = false;
    _role = null;
    _username = null;
    _displayName = null;
    _permissions = [];
    _mustChangePassword = false;
    _userId = null;
    _patientId = null;
    _staffId = null;
    _staffCategory = null;
    _isHead = false;
    NetworkManager.instance.clearToken();
    // Remove persisted token
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    notifyListeners();
  }
}
