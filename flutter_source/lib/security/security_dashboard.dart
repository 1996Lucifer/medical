import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';

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
  Timer? _reconnectTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isConnected = false;
  DateTime? _selectedDate = DateTime.now();

  // Live-pushed alerts have no cap otherwise - a dashboard left open on a
  // wall-mounted security monitor for a full shift would grow this list
  // (and the ListView built from it) without bound. Same reasoning as the
  // 3s fixed-delay reconnect below: matches this codebase's existing
  // pattern (camera_status_service.dart's GlobalCameraStatus) rather than
  // inventing a different one just for this screen.
  static const int _maxAlerts = 200;

  final TextEditingController _ruleController = TextEditingController();

  // Aetheris colors
  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurface => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _primaryContainer => Theme.of(context).colorScheme.primaryContainer;
  Color get _secondary => Theme.of(context).colorScheme.tertiary;
  Color get _surfaceContainerHigh =>
      Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _surfaceContainerLowest =>
      Theme.of(context).colorScheme.surfaceContainerLowest;
  Color get _error => Theme.of(context).colorScheme.error;

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

  void _showActionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
    } catch (_) {
      _showActionError('Could not save the rule. Please try again.');
    }
  }

  Future<void> _deleteRule(int id) async {
    try {
      await NetworkManager.instance.delete(ApiRoutes.deleteSecurityRule(id));
      _fetchRules();
    } catch (_) {
      _showActionError('Could not delete the rule. Please try again.');
    }
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
              if (_alerts.length > _maxAlerts) {
                _alerts.removeRange(_maxAlerts, _alerts.length);
              }
            });
            _playAlarm();
          }
        },
        // A dropped socket (network blip, backend restart) previously
        // just flipped _isConnected to false forever - this is a live
        // security-alert feed, so silently never receiving another alert
        // again until the user manually leaves and re-opens the screen
        // is a real gap, not a cosmetic one.
        onError: (e) {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect();
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect();
        },
      );
      if (mounted) setState(() => _isConnected = true);
    } catch (e) {
      if (mounted) setState(() => _isConnected = false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _sub = null;
    _channel = null;
    if (!mounted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _connectWebSocket();
    });
  }

  Future<void> _playAlarm() async {
    try {
      // Muted to prevent overlap with backend Text-to-Speech system
      // await _audioPlayer.play(AssetSource('alarm.wav'), volume: 1.0);
    } catch (e) {
      debugPrint("Audio error: $e");
    }
  }

  Future<void> _resolveAlert(int id) async {
    try {
      await NetworkManager.instance.post(ApiRoutes.resolveSecurityAlert(id));
      _fetchHistory();
    } catch (_) {
      _showActionError('Could not resolve the alert. Please try again.');
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _audioPlayer.dispose();
    _ruleController.dispose();
    super.dispose();
  }

  Widget _buildMetricsGrid() {
    int recentThreats = _alerts.where((a) {
      if (a['timestamp'] == null) return false;
      try {
        final t = DateTime.parse(a['timestamp'].toString());
        return DateTime.now().toUtc().difference(t.toUtc()).inHours < 1;
      } catch (e) {
        return false;
      }
    }).length;

    // Always exactly 3 cards, so a Row of Expanded + a fixed height is more
    // robust here than GridView's childAspectRatio - that ratio has to
    // guess the right height from a width that changes with the viewport,
    // and got it wrong (2.8 on desktop squeezed each card to ~60-80px tall
    // against ~130-140px of actual content, overflowing the bottom of
    // every card by double-digit pixels).
    const cardHeight = 164.0;
    final isNarrow = MediaQuery.of(context).size.width <= 900;
    final cards = [
      _buildMetricCard(
          'Active Threats',
          '${_alerts.where((a) => a['resolved'] != true).length}',
          '+$recentThreats since last hour',
          _error,
          Icons.emergency_share,
          true),
      _buildMetricCard('Nodes Monitored', '1,284', '100% Operational',
          _primaryFixedDim, Icons.sensors, false),
      _buildMetricCard('System Integrity', '99.9%', 'Encrypted', _secondary,
          Icons.security, false),
    ];
    if (isNarrow) {
      return Column(
        children: cards
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: SizedBox(height: cardHeight, child: c),
                ))
            .toList(),
      );
    }
    return SizedBox(
      height: cardHeight,
      child: Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 24),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle,
      Color color, IconData icon, bool isError) {
    return GlassCard(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 36,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(isError ? Icons.trending_up : Icons.check_circle,
                        color: color, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: color, fontSize: 12)),
                    ),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
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
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: _primaryFixedDim),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text("Active Security Alerts",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _primary)),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                            _selectedDate == null
                                ? Icons.calendar_today
                                : Icons.calendar_month,
                            color: _primaryFixedDim),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (date != null) {
                            setState(() {
                              _selectedDate = date;
                            });
                          } else if (_selectedDate != null) {
                            // Clear filter if they cancel and had a date, or maybe don't clear?
                            // Better provide a way to clear. Let's add a long press or separate clear button.
                            setState(() {
                              _selectedDate = null;
                            });
                          }
                        },
                        tooltip: _selectedDate == null
                            ? "Filter by Date"
                            : "Clear Date Filter",
                      ),
                      if (_selectedDate != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: _primaryFixedDim, fontSize: 14),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: _isConnected ? _primaryFixedDim : _error,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(_isConnected ? 'Live Feed' : 'Disconnected',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _onSurface)),
                    ],
                  ),
                )
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          Builder(builder: (context) {
            final filteredAlerts = _alerts.where((a) {
              if (_selectedDate == null) return true;
              if (a['timestamp'] == null) return false;
              try {
                final t = DateTime.parse(a['timestamp'].toString()).toLocal();
                return t.year == _selectedDate!.year &&
                    t.month == _selectedDate!.month &&
                    t.day == _selectedDate!.day;
              } catch (e) {
                return false;
              }
            }).toList();

            if (filteredAlerts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(40.0),
                child: Center(
                    child: Text('No active security alerts.',
                        style: TextStyle(color: _onSurfaceVariant))),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredAlerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              padding: const EdgeInsets.all(24),
              itemBuilder: (ctx, i) {
                final alert = filteredAlerts[i];
                final isCritical = alert['severity'] == 'critical';
                final isResolved = alert['resolved'] == true;

                // Used directly as icon/text color below, not just a
                // background tint - _secondaryContainer is a low-contrast
                // "container" role color meant for backgrounds, not
                // foreground text/icons.
                final Color alertColor = isResolved
                    ? _onSurfaceVariant
                    : (isCritical ? _error : _secondary);
                final IconData alertIcon =
                    isCritical ? Icons.security : Icons.masks;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: alertColor.withValues(alpha: 0.05),
                    border:
                        Border.all(color: alertColor.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: alertColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8)),
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
                                Text(
                                    '${isCritical ? 'CRITICAL' : 'ELEVATED'}: ${alert['rule_name']}',
                                    style: TextStyle(
                                        color: alertColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                Text(alert['timestamp'].toString(),
                                    style: TextStyle(
                                        color: _onSurfaceVariant,
                                        fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                                'Camera: ${alert['camera_name']}. Details: ${alert['details']}',
                                style:
                                    TextStyle(color: _onSurface, fontSize: 13)),
                            const SizedBox(height: 12),
                            if (!isResolved)
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () => _resolveAlert(alert['id']),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: alertColor,
                                      foregroundColor: isCritical
                                          ? const Color(0xFF690005)
                                          : const Color(0xFF00566b),
                                      minimumSize: const Size(0, 32),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                    ),
                                    child: const Text('Resolve',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: alert['camera_id'] == null
                                        ? null
                                        : () => context.go(
                                            '/camera?expand=${alert['camera_id']}'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: alertColor,
                                      side: BorderSide(
                                          color: alertColor.withValues(
                                              alpha: 0.3)),
                                      minimumSize: const Size(0, 32),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                    ),
                                    child: const Text('View Cam',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
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
            );
          })
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
              Row(
                children: [
                  Icon(Icons.smart_toy, color: _primaryContainer),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text("AI Rules Engine",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _primary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                  "Input natural language to deploy new security protocols across the entire facility.",
                  style: TextStyle(color: _onSurfaceVariant, fontSize: 14)),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: _surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _ruleController,
                  maxLines: 4,
                  style: TextStyle(color: _onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText:
                        'e.g., Alert me if a person enters the pharmacy without a badge after 10 PM',
                    hintStyle: TextStyle(
                        color: _onSurfaceVariant.withValues(alpha: 0.5)),
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
                  label: const Text('Deploy Rule',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryContainer,
                    foregroundColor: const Color(0xFF00725e),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 10,
                    shadowColor: _primaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text("Recent Deployments",
                  style: TextStyle(
                      color: _onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
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
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: _primaryFixedDim,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_rules[i]['rule_text'],
                                style: TextStyle(
                                    color: _onSurface, fontSize: 12))),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: _error, size: 16),
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
                    ])),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.language, color: _primaryContainer, size: 40),
                    const SizedBox(height: 8),
                    Text('Network Heatmap Active',
                        style: TextStyle(
                            color: _primaryFixedDim,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
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
                Text('Security Command Center',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _primary)),
                const SizedBox(height: 8),
                Text(
                    'Real-time AI-driven monitoring of hospital infrastructure, access points, and personnel compliance.',
                    style: TextStyle(fontSize: 16, color: _onSurfaceVariant)),
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
