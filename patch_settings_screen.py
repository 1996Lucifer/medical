import re

with open('flutter_source/lib/settings/settings_screen.dart', 'r') as f:
    content = f.read()

# Add import
content = content.replace("import 'camera_status_dot.dart';", "import 'camera_status_dot.dart';\nimport 'camera_management_screen.dart';")

# Change onTap for Manage Cameras
content = re.sub(
    r"subtitle: const Text\('Add or remove registered RTSP camera sources'\),\n                      onTap: _showCameraSourceDialog,",
    "subtitle: const Text('Add or remove registered RTSP camera sources'),\n                      onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraManagementScreen())); },",
    content
)

# Remove all camera logic from settings_screen.dart
# Starting from "// ── Camera source management dialog ──" up to right before "  // ── Staff Management Dialog ──"
# Let's check the exact string of the staff management dialog comment. Let's just use the function name.
content = re.sub(r'  // ── Camera source management dialog ──[\s\S]*?(?=  Future<void> _showStaffManagementDialog)', '', content)

# Remove `List<Map<String, dynamic>> _savedCameras = [];` and `_fetchCameras`
content = re.sub(r'  List<Map<String, dynamic>> _savedCameras = \[\];\n\n  // ── Camera API ──[\s\S]*?  // ── Staff API ──', '  // ── Staff API ──', content)

with open('flutter_source/lib/settings/settings_screen.dart', 'w') as f:
    f.write(content)
