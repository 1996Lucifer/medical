import 'environment.dart';

class ApiRoutes {
  static String get baseUrl => EnvironmentConfig.current.baseUrl;
  static String get wsBaseUrl => EnvironmentConfig.current.wsBaseUrl;

  // Auth
  static String get login => '$baseUrl/api/auth/login';
  static String get authMe => '$baseUrl/api/auth/me';
  static String get changePassword => '$baseUrl/api/auth/change-password';

  // First-run deployment setup (replaces the old auto-created admin/admin
  // setup-admin endpoint — see routers/setup.py).
  static String get setupStatus => '$baseUrl/api/setup/status';
  static String get setupInitialize => '$baseUrl/api/setup/initialize';

  // Camera
  static String get equipmentLogs => '$baseUrl/api/equipment/logs';

  // Events
  static String get eventsWs => '$wsBaseUrl/api/events/ws';
  static String get timeline => '$baseUrl/api/events/timeline';
  static String get cameraStop => '$baseUrl/api/camera/stop';
  static String get cameras => '$baseUrl/api/cameras';
  static String get camerasWarmup => '$baseUrl/api/cameras/warmup';
  static String get camerasStatus => '$baseUrl/api/cameras/status';
  static String get camerasStatusWs => '$wsBaseUrl/api/cameras/ws/status';
  static String camera(int id) => '$baseUrl/api/cameras/$id';
  static String cameraWs(int id, {String mode = 'ai'}) =>
      '$wsBaseUrl/api/ws/camera?camera_id=$id&mode=$mode';
  static String webrtcOffer(int id, {String mode = 'webrtc_ai'}) =>
      '$baseUrl/api/webrtc/offer?camera_id=$id&mode=$mode';
  static String cameraRois(int id) => '$baseUrl/api/cameras/$id/rois';
  static String deleteCameraRoi(int id) => '$baseUrl/api/cameras/rois/$id';
  static String get allUniqueRois => '$baseUrl/api/cameras/rois/all/unique';
  static String cameraStatus(int id) => '$baseUrl/api/cameras/$id/status';
  static String cameraSnapshot(int id) => '$baseUrl/api/cameras/$id/snapshot';

  // Attendance
  static String get attendance => '$baseUrl/api/attendance';
  static String get myAttendanceSession => '$baseUrl/api/attendance/me';
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

  // Analytics
  static String adminDashboard() => '$baseUrl/api/analytics/dashboard';

  // GET /api/staff is now paginated (routers/staff.py) - {items, total,
  // page, limit} instead of a bare list. limit=200 is the endpoint's max
  // page size, so this keeps every existing "list all staff" call site
  // showing the full roster exactly like before, up to that cap.
  static String get staff => '$baseUrl/api/staff?limit=200';
  static String get myStaffProfile => '$baseUrl/api/staff/me';
  static String get staffActivity => '$baseUrl/api/staff/activity';
  // Reporting hierarchy (routers/staff.py, services/staff/hierarchy.py)
  static String get myTeam => '$baseUrl/api/staff/my-team';
  static String staffAssignment(int staffId) => '$baseUrl/api/staff/$staffId/assignment';
  static String registerStaff(String name, String role, String category) =>
      '$baseUrl/api/staff?name=${Uri.encodeComponent(name)}&role=${Uri.encodeComponent(role)}&category=${Uri.encodeComponent(category)}';
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
  static String deleteRbacGroup(int id) => '$baseUrl/api/rbac/groups/$id';
  static String deleteRbacPermission(int id) =>
      '$baseUrl/api/rbac/permissions/$id';
  // Agent
  static String get agentChat => '$baseUrl/api/agent/chat';
  static String get agentHistory => '$baseUrl/api/agent/history';
  static String get agentUsage => '$baseUrl/api/agent/usage';
  static String get agentSessions => '$baseUrl/api/agent/sessions';
  static String agentSession(String id) => '$baseUrl/api/agent/session/$id';

  // Site Config
  static String get siteConfig => '$baseUrl/api/site-config';
  static String get siteConfigLogo => '$baseUrl/api/site-config/logo';

  // Patients / doctor-patient calling
  // GET /api/patients is now paginated (routers/patients.py) - {items,
  // total, page, limit} instead of a bare list. limit=200 is the
  // endpoint's max page size, so this keeps every existing "list all
  // patients" call site showing the full list exactly like before, up to
  // that cap.
  static String patients() => '$baseUrl/api/patients?limit=200';
  static String patient(int id) => '$baseUrl/api/patients/$id';
  static String patientCreateLogin(int id) =>
      '$baseUrl/api/patients/$id/create-login';
  static String patientDoctors(int id) => '$baseUrl/api/patients/$id/doctors';
  static String get doctorsDirectory => '$baseUrl/api/staff/doctors';
  static String staffPatients(int staffId) => '$baseUrl/api/staff/$staffId/patients';

  // Call signaling
  // No token in the URL - the JWT travels as the first WS message instead
  // (see backend/services/ws_auth.py). A URL-embedded token lands in
  // server/proxy access logs and browser history, letting anyone with
  // log access replay a live signaling/tracking session.
  static String get callsWs {
    final wsBase = baseUrl.replaceFirst('http', 'ws');
    return '$wsBase/ws/calls';
  }

  // Staff/doctor/patient messaging (routers/messages.py) - persisted chat,
  // live delivery still pushed over the calls.py signaling socket while
  // both sides are connected.
  static String get messageConversations => '$baseUrl/api/messages/conversations';
  static String messagesWith(int peerId) => '$baseUrl/api/messages/with/$peerId';
  static String get sendMessage => '$baseUrl/api/messages';
  static String markMessagesRead(int peerId) =>
      '$baseUrl/api/messages/with/$peerId/read';

  // Call history (routers/calls.py) - lets a recipient see who called them
  // even if that caller never shows up as a card in the People Directory
  // (e.g. an admin/superadmin login with no Staff row).
  static String get callLog => '$baseUrl/api/calls/log';

  // Indoor location tracking (routers/indoor_tracking.py)
  static String get indoorTrackingPublishedFloors =>
      '$baseUrl/api/indoor-tracking/floors';
  static String indoorTrackingViewRooms(int floorId) =>
      '$baseUrl/api/indoor-tracking/floors/$floorId/rooms';
  static String get indoorTrackingSignal =>
      '$baseUrl/api/indoor-tracking/signal';
  static String indoorTrackingFloorActive(int floorId) =>
      '$baseUrl/api/indoor-tracking/floors/$floorId/active';
  // Same "no token in the URL" rationale as callsWs above - especially
  // important here since this socket streams live physical locations.
  static String indoorTrackingWs(int floorId) {
    final wsBase = baseUrl.replaceFirst('http', 'ws');
    return '$wsBase/api/indoor-tracking/ws?floor_id=$floorId';
  }

  static String get indoorTrackingHospital =>
      '$baseUrl/api/indoor-tracking/admin/hospital';
  static String get indoorTrackingHospitalGeofence =>
      '$baseUrl/api/indoor-tracking/admin/hospital/geofence';
  static String get indoorTrackingBuildings =>
      '$baseUrl/api/indoor-tracking/admin/buildings';
  static String get indoorTrackingFloors =>
      '$baseUrl/api/indoor-tracking/admin/floors';
  static String indoorTrackingFloorplanImageUpload(int floorId) =>
      '$baseUrl/api/indoor-tracking/admin/floors/$floorId/floorplan-image';
  static String indoorTrackingFloorplanImageUrl(String path) =>
      '$baseUrl/uploads/$path';
  static String indoorTrackingPublishFloor(int floorId) =>
      '$baseUrl/api/indoor-tracking/admin/floors/$floorId/publish';
  static String indoorTrackingRooms(int floorId) =>
      '$baseUrl/api/indoor-tracking/admin/floors/$floorId/rooms';
  static String get indoorTrackingWifiAps =>
      '$baseUrl/api/indoor-tracking/admin/wifi-aps';
  static String indoorTrackingFloorWifiAps(int floorId) =>
      '$baseUrl/api/indoor-tracking/admin/floors/$floorId/wifi-aps';
  static String indoorTrackingCameraPosition(int cameraId, int floorId, double x, double y) =>
      '$baseUrl/api/indoor-tracking/admin/cameras/$cameraId/position?floor_id=$floorId&x=$x&y=$y';

  // RFID devices / card enrollment (routers/rfid.py)
  static String get rfidDevices => '$baseUrl/api/rfid/devices';
  static String get rfidEnrollSessions => '$baseUrl/api/rfid/enroll-sessions';
  static String rfidEnrollSessionStatus(int sessionId) =>
      '$baseUrl/api/rfid/enroll-sessions/$sessionId';
  static String get rfidStationResetConfig =>
      '$baseUrl/api/rfid/station/reset-config';
}
