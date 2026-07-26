import 'dart:convert';

import 'api_routes.dart';
import 'network_manager.dart';

class AdminDashboardService {
  Future<Map<String, dynamic>> fetchDashboardData() async {
    final response =
        await NetworkManager.instance.get(ApiRoutes.adminDashboard());

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load dashboard data: ${response.statusCode}');
    }
  }
}
