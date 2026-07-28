import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../network/api_routes.dart';
import '../network/network_manager.dart';

class SiteConfigProvider extends ChangeNotifier {
  String _hospitalName = 'Hospital AI';
  String _agentName = 'AI';
  String? _logoUrl;
  bool _isLoading = false;

  String get hospitalName => _hospitalName;
  String get agentName => _agentName;
  String? get logoUrl => _logoUrl;
  bool get isLoading => _isLoading;

  /// Full URL for the logo image (if set)
  String? get fullLogoUrl {
    if (_logoUrl == null) return null;
    return '${ApiRoutes.baseUrl}$_logoUrl';
  }

  /// Fetch the current site config from the backend
  Future<void> fetchConfig() async {
    try {
      final response = await NetworkManager.instance.get(ApiRoutes.siteConfig);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _hospitalName = data['hospital_name'] ?? 'Hospital AI';
        _agentName = data['agent_name'] ?? 'AI';
        _logoUrl = data['logo_url'];
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching site config: $e");
    }
  }

  /// Update hospital name and/or agent name
  Future<bool> updateConfig({String? hospitalName, String? agentName}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final body = <String, dynamic>{};
      if (hospitalName != null) body['hospital_name'] = hospitalName;
      if (agentName != null) body['agent_name'] = agentName;

      final response = await NetworkManager.instance.put(
        ApiRoutes.siteConfig,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _hospitalName = data['hospital_name'];
        _agentName = data['agent_name'];
        _logoUrl = data['logo_url'];
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint("Error updating site config: $e");
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Upload a logo image using multipart request
  Future<bool> uploadLogo(Uint8List bytes, String filename) async {
    _isLoading = true;
    notifyListeners();

    try {
      final request = NetworkManager.instance.multipartRequest(
        'POST',
        ApiRoutes.siteConfigLogo,
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

      final streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200) {
        final responseBody = await streamedResponse.stream.bytesToString();
        final data = jsonDecode(responseBody);
        _hospitalName = data['hospital_name'];
        _agentName = data['agent_name'];
        _logoUrl = data['logo_url'];
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint("Error uploading logo: $e");
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Delete the current logo
  Future<bool> deleteLogo() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await NetworkManager.instance.delete(
        ApiRoutes.siteConfigLogo,
      );
      if (response.statusCode == 200) {
        _logoUrl = null;
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint("Error deleting logo: $e");
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }
}
