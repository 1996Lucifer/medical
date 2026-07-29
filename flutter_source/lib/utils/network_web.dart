class NetworkUtils {
  Future<String?> getLocalIpAddress() async {
    // In a web environment, we extract the hostname from the browser URL.
    // If you access the app via http://192.168.1.99, this correctly returns 192.168.1.99.
    final host = Uri.base.host;
    return (host.isEmpty || host == 'localhost') ? '127.0.0.1' : host;
  }
}
