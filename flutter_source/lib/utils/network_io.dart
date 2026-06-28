import 'dart:developer';
import 'dart:io';

class NetworkUtils {
  Future<String?> getLocalIpAddress() async {
    try {
      // List all network interfaces available on the device
      List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false, // Exclude 127.0.0.1
        type: InternetAddressType.IPv4, // Force IPv4 addresses
      );

      for (var interface in interfaces) {
        // Loop through addresses bound to each interface (WiFi, Cellular, Ethernet)
        for (var address in interface.addresses) {
          // Return the first valid non-loopback IP address
          if (!address.isLoopback) {
            return address.address;
          }
        }
      }
    } catch (e) {
      log("Error fetching network interfaces: $e");
    }
    return null;
  }
}
