import 'environment.dart';

class ApiRoutes {
  static String get baseUrl => EnvironmentConfig.current.baseUrl;
  static String get wsBaseUrl => EnvironmentConfig.current.wsBaseUrl;

  // Auth
  static String get login => '$baseUrl/api/auth/login';
  static String get setupAdmin => '$baseUrl/api/auth/setup-admin';

  // Camera
  static String get equipmentLogs => '$baseUrl/api/equipment/logs';

  // Events
  static String get eventsWs => '$wsBaseUrl/api/events/ws';
  static String get timeline => '$baseUrl/api/events/timeline';
  static String get cameraStop => '$baseUrl/api/camera/stop';
  static String get cameras => '$baseUrl/api/cameras';
  static String get camerasStatus => '$baseUrl/api/cameras/status';
  static String get camerasStatusWs => '$wsBaseUrl/api/cameras/ws/status';
  static String camera(int id) => '$baseUrl/api/cameras/$id';
  static String cameraWs(int id, {String mode = 'ai'}) =>
      '$wsBaseUrl/api/ws/camera?camera_id=$id&mode=$mode';
  static String cameraRois(int id) => '$baseUrl/api/cameras/$id/rois';
  static String deleteCameraRoi(int id) => '$baseUrl/api/cameras/rois/$id';
  static String get allUniqueRois => '$baseUrl/api/cameras/rois/all/unique';
  static String cameraStatus(int id) => '$baseUrl/api/cameras/$id/status';
  static String cameraSnapshot(int id) => '$baseUrl/api/cameras/$id/snapshot';

  // Attendance
  static String get attendance => '$baseUrl/api/attendance';
  static String attendanceDelete(int id) => '$baseUrl/api/attendance/$id';
  static String attendanceCheckout(int id) =>
      '$baseUrl/api/attendance/$id/checkout';
  static String attendanceSummary(int days) =>
      '$baseUrl/api/analytics/attendance-summary?days=$days';
  static String analyticsEvents(int limit) =>
      '$baseUrl/api/analytics/events?limit=$limit';

  // Security
  static String securityAlerts(bool unresolvedOnly) =>
      '$baseUrl/api/security/alerts?unresolved_only=$unresolvedOnly';
  static String resolveSecurityAlert(int id) =>
      '$baseUrl/api/security/alerts/$id/resolve';
  static String get securityRules => '$baseUrl/api/security/rules';
  static String get securityRulesSync => '$baseUrl/api/security/rules/sync';
  static String deleteSecurityRule(int id) => '$baseUrl/api/security/rules/$id';

  // Staff
  static String get staff => '$baseUrl/api/staff';
  static String staffSearch(String name) =>
      '$baseUrl/api/staff?name=${Uri.encodeComponent(name)}';
  static String staffMember(int id) => '$baseUrl/api/staff/$id';
  static String staffPhotos(int id) => '$baseUrl/api/staff/$id/photos';
  static String staffPhotoDelete(int staffId, int photoId) =>
      '$baseUrl/api/staff/$staffId/photo/$photoId';
  static String staffPhotoUpload(int staffId, String label) =>
      '$baseUrl/api/staff/$staffId/photo?label=${Uri.encodeComponent(label)}';
  static String staffVideoSetup(int id) => '$baseUrl/api/staff/$id/video_setup';

  static String staffLiveSetupWs(int id) {
    final wsBase = baseUrl.replaceFirst('http', 'ws');
    return '$wsBase/api/staff/$id/live_setup/ws';
  }

  // Consultations
  static String consultations(String patientName) =>
      '$baseUrl/api/consultations?patient_name=${Uri.encodeComponent(patientName)}';

  // RBAC
  static String get rbacGraph => '$baseUrl/api/rbac/graph';
  static String get rbacAssign => '$baseUrl/api/rbac/assign';
  static String get rbacUnassign => '$baseUrl/api/rbac/unassign';
  static String get rbacGroups => '$baseUrl/api/rbac/groups';
  static String get rbacPermissions => '$baseUrl/api/rbac/permissions';
  // Agent
  static String get agentChat => '$baseUrl/api/agent/chat';
  static String get agentHistory => '$baseUrl/api/agent/history';
  static String get agentUsage => '$baseUrl/api/agent/usage';
  static String get agentSessions => '$baseUrl/api/agent/sessions';
  static String agentSession(String id) => '$baseUrl/api/agent/session/$id';
}
