import 'environment.dart';

class ApiRoutes {
  static String get baseUrl => EnvironmentConfig.current.baseUrl;
  static String get wsBaseUrl => EnvironmentConfig.current.wsBaseUrl;

  // Auth
  static String get login => '$baseUrl/api/auth/login';
  static String get setupAdmin => '$baseUrl/api/auth/setup-admin';

  // Camera
  static String get cameraStop => '$baseUrl/api/camera/stop';
  static String get cameras => '$baseUrl/api/cameras';
  static String camera(int id) => '$baseUrl/api/cameras/$id';
  static String cameraWs(int id) => '$wsBaseUrl/api/ws/camera?camera_id=$id';
  
  // Attendance
  static String get attendance => '$baseUrl/api/attendance';
  static String attendanceDelete(int id) => '$baseUrl/api/attendance/$id';
  static String attendanceCheckout(int id) => '$baseUrl/api/attendance/$id/checkout';
  static String attendanceSummary(int days) => '$baseUrl/api/analytics/attendance-summary?days=$days';

  // Security
  static String securityAlerts(bool unresolvedOnly) => '$baseUrl/api/security/alerts?unresolved_only=$unresolvedOnly';
  static String resolveSecurityAlert(int id) => '$baseUrl/api/security/alerts/$id/resolve';

  // Staff
  static String get staff => '$baseUrl/api/staff';
  static String staffSearch(String name) => '$baseUrl/api/staff?name=${Uri.encodeComponent(name)}';
  static String staffMember(int id) => '$baseUrl/api/staff/$id';
  static String staffPhotos(int id) => '$baseUrl/api/staff/$id/photos';
  static String staffPhotoDelete(int staffId, int photoId) => '$baseUrl/api/staff/$staffId/photo/$photoId';
  static String staffPhotoUpload(int staffId, String label) => '$baseUrl/api/staff/$staffId/photo?label=${Uri.encodeComponent(label)}';

  // Consultations
  static String consultations(String patientName) => '$baseUrl/api/consultations?patient_name=${Uri.encodeComponent(patientName)}';
}
