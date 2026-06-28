class NetworkUtils {
  Future<String?> getLocalIpAddress() async {
    // In a web environment, we cannot get the local IP address
    // So we just return localhost.
    return '127.0.0.1';
  }
}
