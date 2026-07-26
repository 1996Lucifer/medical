import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'package:provider/provider.dart';
import '../providers/security_provider.dart';

class SecurityDashboardScreen extends StatefulWidget {
  const SecurityDashboardScreen({super.key});

  @override
  State<SecurityDashboardScreen> createState() =>
      _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> {
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _rules = [];
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isConnected = false;

  final TextEditingController _ruleController = TextEditingController();

  // Aetheris colors
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurface = Color(0xFFd6e3ff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _primaryContainer = Color(0xFF5ffbd6);
  static const Color _secondary = Color(0xFFa6e6ff);
  static const Color _secondaryContainer = Color(0xFF14d1ff);
  static const Color _surfaceContainerHigh = Color(0xFF1c2a41);
  static const Color _surfaceContainerLowest = Color(0xFF010e24);
  static const Color _error = Color(0xFFffb4ab);

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _fetchRules();
    _connectWebSocket();
  }

  Future<void> _fetchRules() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.securityRules);
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _rules = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _addRule(String area, String text) async {
    try {
      await NetworkManager.instance.post(
        ApiRoutes.securityRules,
        body: jsonEncode({
          "target_area": area.isEmpty ? null : area,
          "rule_text": text,
        }),
      );
      _ruleController.clear();
      _fetchRules();
    } catch (_) {}
  }

  Future<void> _deleteRule(int id) async {
    try {
      await NetworkManager.instance.delete(ApiRoutes.deleteSecurityRule(id));
      _fetchRules();
    } catch (_) {}
  }

  Future<void> _fetchHistory() async {
    try {
      final resp =
          await NetworkManager.instance.get(ApiRoutes.securityAlerts(false));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _alerts = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _connectWebSocket() async {
    try {
      _channel = WebSocketChannel.connect(
          Uri.parse('${ApiRoutes.wsBaseUrl}/api/security/ws/alerts'));
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
    _ruleController.dispose();
    super.dispose();
  }

  Widget _buildMetricsGrid() {
    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 900 ? 3 : 1,
      crossAxisSpacing: 24,
      mainAxisSpacing: 24,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: MediaQuery.of(context).size.width > 900 ? 2.8 : 2.0,
      children: [
        _buildMetricCard('Active Threats', '${_alerts.where((a) => a['resolved'] != true).length}', '+2 since last hour', _error, Icons.emergency_share, true),
        _buildMetricCard('Nodes Monitored', '1,284', '100% Operational', _primaryFixedDim, Icons.sensors, false),
        _buildMetricCard('System Integrity', '99.9%', 'Encrypted', _secondary, Icons.security, false),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle, Color color, IconData icon, bool isError) {
    return GlassCard(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(color: _onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(isError ? Icons.trending_up : Icons.check_circle, color: color, size: 14),
                  const SizedBox(width: 4),
                  Text(subtitle, style: TextStyle(color: color, fontSize: 12)),
                ],
              )
            ],
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          )
        ],
      ),
    );
  }

  Widget _buildAlertsFeed() {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: _primaryFixedDim),
                    SizedBox(width: 12),
                    Text("Active Security Alerts", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: _isConnected ? _primaryFixedDim : _error, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(_isConnected ? 'Live Feed' : 'Disconnected', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _onSurface)),
                    ],
                  ),
                )
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          _alerts.isEmpty 
          ? const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(child: Text('No active security alerts.', style: TextStyle(color: _onSurfaceVariant))),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              padding: const EdgeInsets.all(24),
              itemBuilder: (ctx, i) {
                final alert = _alerts[i];
                final isCritical = alert['severity'] == 'critical';
                final isResolved = alert['resolved'] == true;
                
                final Color alertColor = isResolved ? _onSurfaceVariant : (isCritical ? _error : _secondaryContainer);
                final IconData alertIcon = isCritical ? Icons.security : Icons.masks;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: alertColor.withValues(alpha: 0.05),
                    border: Border.all(color: alertColor.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: alertColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                        child: Icon(alertIcon, color: alertColor),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${isCritical ? 'CRITICAL' : 'ELEVATED'}: ${alert['rule_name']}', style: TextStyle(color: alertColor, fontWeight: FontWeight.w600, fontSize: 14)),
                                Text(alert['timestamp'].toString(), style: const TextStyle(color: _onSurfaceVariant, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Camera: ${alert['camera_name']}. Details: ${alert['details']}', style: const TextStyle(color: _onSurface, fontSize: 13)),
                            const SizedBox(height: 12),
                            if (!isResolved)
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () => _resolveAlert(alert['id']),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: alertColor,
                                      foregroundColor: isCritical ? const Color(0xFF690005) : const Color(0xFF00566b),
                                      minimumSize: const Size(0, 32),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                    ),
                                    child: const Text('Resolve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: () {},
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: alertColor,
                                      side: BorderSide(color: alertColor.withValues(alpha: 0.3)),
                                      minimumSize: const Size(0, 32),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                    ),
                                    child: const Text('View Cam', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              )
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            )
        ],
      ),
    );
  }

  Widget _buildRulesEngine() {
    return Column(
      children: [
        GlassCard(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.smart_toy, color: _primaryContainer),
                  SizedBox(width: 12),
                  Text("AI Rules Engine", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primary)),
                ],
              ),
              const SizedBox(height: 16),
              const Text("Input natural language to deploy new security protocols across the entire facility.", style: TextStyle(color: _onSurfaceVariant, fontSize: 14)),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: _surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _ruleController,
                  maxLines: 4,
                  style: const TextStyle(color: _onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g., Alert me if a person enters the pharmacy without a badge after 10 PM',
                    hintStyle: TextStyle(color: _onSurfaceVariant.withValues(alpha: 0.5)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_ruleController.text.isNotEmpty) {
                      _addRule('Global', _ruleController.text);
                    }
                  },
                  icon: const Icon(Icons.bolt, size: 20),
                  label: const Text('Deploy Rule', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryContainer,
                    foregroundColor: const Color(0xFF00725e),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 10,
                    shadowColor: _primaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text("Recent Deployments", style: TextStyle(color: _onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _rules.length,
                itemBuilder: (ctx, i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: _primaryFixedDim, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_rules[i]['rule_text'], style: const TextStyle(color: _onSurface, fontSize: 12))),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: _error, size: 16),
                          onPressed: () => _deleteRule(_rules[i]['id']),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        )
                      ],
                    ),
                  );
                },
              )
            ],
          ),
        ),
        const SizedBox(height: 24),
        GlassCard(
          height: 160,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _primaryContainer.withValues(alpha: 0.2),
                      Colors.transparent,
                    ]
                  )
                ),
              ),
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.language, color: _primaryContainer, size: 40),
                    SizedBox(height: 8),
                    Text('Network Heatmap Active', style: TextStyle(color: _primaryFixedDim, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: ListView(
          padding: const EdgeInsets.all(40),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Security Command Center', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _primary)),
                const SizedBox(height: 8),
                const Text('Real-time AI-driven monitoring of hospital infrastructure, access points, and personnel compliance.', style: TextStyle(fontSize: 16, color: _onSurfaceVariant)),
                const SizedBox(height: 32),
                _buildMetricsGrid(),
                const SizedBox(height: 24),
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _buildAlertsFeed()),
                      const SizedBox(width: 24),
                      Expanded(flex: 1, child: _buildRulesEngine()),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildAlertsFeed(),
                      const SizedBox(height: 24),
                      _buildRulesEngine(),
                    ],
                  )
              ],
            )
          ],
        ),
      ),
    );
  }
}
