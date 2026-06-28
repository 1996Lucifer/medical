import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class SecurityDashboardScreen extends StatefulWidget {
  const SecurityDashboardScreen({super.key});

  @override
  State<SecurityDashboardScreen> createState() => _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> {
  List<Map<String, dynamic>> _alerts = [];
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _connectWebSocket();
  }

  Future<void> _fetchHistory() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.securityAlerts(false));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _alerts = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _connectWebSocket() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse('${ApiRoutes.wsBaseUrl}/api/security/ws/alerts'));
      await _channel!.ready;
      _sub = _channel!.stream.listen(
        (message) {
          if (mounted) {
            final alert = jsonDecode(message) as Map<String, dynamic>;
            setState(() {
              _alerts.insert(0, alert);
            });
            _playAlarm();
          }
        },
        onError: (e) {
          if (mounted) setState(() => _isConnected = false);
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
        },
      );
      if (mounted) setState(() => _isConnected = true);
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  Future<void> _playAlarm() async {
    try {
      await _audioPlayer.play(AssetSource('alarm.wav'), volume: 1.0);
    } catch (e) {
      debugPrint("Audio error: $e");
    }
  }

  Future<void> _resolveAlert(int id) async {
    try {
      await NetworkManager.instance.post(ApiRoutes.resolveSecurityAlert(id));
      _fetchHistory();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Security Alerts',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.black.withOpacity(0.05), height: 1.0),
        ),
        actions: [
          Icon(
            _isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: _isConnected ? Colors.teal : const Color(0xFFF43F5E),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: GlassBackground(
        child: _alerts.isEmpty
            ? Center(
                child: GlassCard(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_rounded, size: 56, color: Colors.teal.shade600),
                      const SizedBox(height: 16),
                      const Text(
                        'All clear.',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'No active security alerts.',
                        style: TextStyle(fontSize: 14, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    itemCount: _alerts.length,
                    itemBuilder: (ctx, i) {
                      final alert = _alerts[i];
                      final isCritical = alert['severity'] == 'critical';
                      final isResolved = alert['resolved'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isResolved
                                    ? Colors.white.withOpacity(0.50)
                                    : (isCritical 
                                        ? const Color(0xFFFFF1F2).withOpacity(0.75) 
                                        : Colors.amber.shade50.withOpacity(0.75)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isResolved
                                      ? Colors.white.withOpacity(0.3)
                                      : (isCritical 
                                          ? const Color(0xFFFECDD3).withOpacity(0.4) 
                                          : Colors.amber.shade200.withOpacity(0.4)),
                                  width: 1.5,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: isResolved
                                      ? Colors.grey.shade200
                                      : (isCritical ? const Color(0xFFFFE4E6) : Colors.amber.shade100),
                                  child: Icon(
                                    isCritical ? Icons.warning_rounded : Icons.info_outline_rounded,
                                    color: isResolved
                                        ? Colors.grey
                                        : (isCritical ? const Color(0xFFBE123C) : Colors.amber.shade800),
                                  ),
                                ),
                                title: Text(
                                  '${alert['rule_name']} - ${alert['camera_name']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isResolved ? Colors.grey.shade600 : const Color(0xFF0F172A),
                                  ),
                                ),
                                subtitle: Text(
                                  'Details: ${alert['details']}\nTime: ${alert['timestamp']}',
                                  style: TextStyle(
                                    color: isResolved ? Colors.grey.shade500 : const Color(0xFF334155),
                                    height: 1.4,
                                  ),
                                ),
                                trailing: isResolved
                                    ? const Icon(Icons.check_circle_rounded, color: Colors.teal)
                                    : ElevatedButton(
                                        onPressed: () => _resolveAlert(alert['id']),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal.shade700,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        child: const Text('Resolve'),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}
