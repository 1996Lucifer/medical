/// Local dev backend IP, injected via --dart-define=DEV_IP=192.168.x.x so
/// each developer isn't stuck with someone else's LAN address baked into
/// the shipped default.
const String kDevIpAddress =
    String.fromEnvironment('DEV_IP', defaultValue: '192.168.1.52');

abstract class Environment {
  String get name;
  String get baseUrl;
  String get wsBaseUrl;
}

class DevEnvironment implements Environment {
  final String ipAddress;

  DevEnvironment({this.ipAddress = '192.168.1.10'});

  @override
  String get name => 'development';
  @override
  String get baseUrl => 'http://$ipAddress:8000';
  @override
  String get wsBaseUrl => 'ws://$ipAddress:8000';
}

class StagingEnvironment implements Environment {
  @override
  String get name => 'staging';
  @override
  String get baseUrl => 'https://staging-api.example.com';
  @override
  String get wsBaseUrl => 'wss://staging-api.example.com';
}

class ProdEnvironment implements Environment {
  @override
  String get name => 'production';
  @override
  String get baseUrl => 'http://api.example.com';
  @override
  String get wsBaseUrl => 'wss://api.example.com';
}

class EnvironmentConfig {
  static Environment current = DevEnvironment();

  static void setEnvironment(Environment env) {
    current = env;
  }

  /// Initialize environment using --dart-define=ENV=dev|staging|prod
  static Future<void> init() async {
    const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env.toLowerCase()) {
      case 'prod':
      case 'production':
        setEnvironment(ProdEnvironment());
        break;
      case 'staging':
      case 'stg':
        setEnvironment(StagingEnvironment());
        break;
      case 'dev':
      case 'development':
      default:
        setEnvironment(DevEnvironment(ipAddress: kDevIpAddress));
        break;
    }
  }
}
