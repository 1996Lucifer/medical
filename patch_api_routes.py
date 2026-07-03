import re

with open('flutter_source/lib/network/api_routes.dart', 'r') as f:
    content = f.read()

content = content.replace(
    "static String get camerasStatus => '$baseUrl/api/cameras/status';",
    "static String get camerasStatus => '$baseUrl/api/cameras/status';\n  static String get camerasStatusWs => '${EnvironmentConfig.websocketBaseUrl}/api/cameras/ws/status';"
)

with open('flutter_source/lib/network/api_routes.dart', 'w') as f:
    f.write(content)
