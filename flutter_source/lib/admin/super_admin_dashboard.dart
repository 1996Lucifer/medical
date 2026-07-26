import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../network/admin_dashboard_service.dart';

// Brand Colors from Aetheris Command
const Color _bgBase = Color(0xFF041329);
const Color _surfaceContainer = Color(0xFF112036);
const Color _surfaceBright = Color(0xFF2c3951);
const Color _tealAccent = Color(0xFF64ffda);
const Color _cyanAccent = Color(0xFF00d1ff);
const Color _textColor = Color(0xFFd6e3ff);
const Color _textVariant = Color(0xFFbacac3);
const Color _critical = Color(0xFFffb4ab);
const Color _criticalContainer = Color(0xFF93000a);

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final AdminDashboardService _service = AdminDashboardService();
  Timer? _timer;
  
  bool _isLoading = true;
  String? _error;
  
  Map<String, dynamic>? _systemHealth;
  List<dynamic>? _departmentResources;
  List<dynamic>? _patientFlow;
  List<dynamic>? _securityVault;

  @override
  void initState() {
    super.initState();
    _fetchData();
    // Auto-refresh every 10 seconds for real-time monitoring
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchData(isRefresh: true);
    });
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData({bool isRefresh = false}) async {
    try {
      final data = await _service.fetchDashboardData();
      if (mounted) {
        setState(() {
          _systemHealth = data['system_health'];
          _departmentResources = data['department_resources'];
          _patientFlow = data['patient_flow'];
          _securityVault = data['security_vault'];
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !isRefresh) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: _bgBase,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _tealAccent))
                : _error != null
                    ? Center(child: Text('Error: $_error', style: const TextStyle(color: _critical)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 24),
                            _buildSystemHealthRow(isDesktop),
                            const SizedBox(height: 24),
                            _buildChartsRow(isDesktop),
                            const SizedBox(height: 32),
                            _buildSecurityVault(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: _bgBase,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildTopLink('Dashboard', isActive: true),
          const SizedBox(width: 24),
          _buildTopLink('Resources'),
          const SizedBox(width: 24),
          _buildTopLink('Patients'),
          const SizedBox(width: 32),
          const Icon(Icons.notifications_none, color: _textColor, size: 20),
          const SizedBox(width: 24),
          const Icon(Icons.settings_outlined, color: _textColor, size: 20),
          const SizedBox(width: 24),
          const CircleAvatar(
            radius: 14,
            backgroundColor: _surfaceBright,
            child: Icon(Icons.person, size: 16, color: _textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTopLink(String text, {bool isActive = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          text,
          style: TextStyle(
            color: isActive ? _tealAccent : _textColor,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
        if (isActive)
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 24,
            height: 2,
            color: _tealAccent,
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System Health',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'Real-time neural network performance across Aegis Node Alpha.',
              style: TextStyle(color: _textVariant, fontSize: 14),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: _tealAccent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('Live Stream Active', style: TextStyle(color: _tealAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemHealthRow(bool isDesktop) {
    final cards = [
      _buildGPUCard(),
      _buildCPUCard(),
      _buildModelCard(),
    ];

    if (!isDesktop) {
      return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)).toList());
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 16),
        Expanded(child: cards[1]),
        const SizedBox(width: 16),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _buildGPUCard() {
    final gpuValue = (_systemHealth?['gpu_utilization'] ?? 0.0) as num;
    final nodeName = _systemHealth?['active_node'] ?? 'NODE_01';
    
    return _buildStatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildIconBox(Icons.memory, _tealAccent),
              _buildNodePill(nodeName),
            ],
          ),
          const SizedBox(height: 24),
          Text('${gpuValue.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          const Text('GPU UTILIZATION', style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: (gpuValue / 100).clamp(0.0, 1.0), backgroundColor: _surfaceBright, color: _tealAccent, minHeight: 4, borderRadius: BorderRadius.circular(2)),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.trending_up, color: _textVariant, size: 14),
              SizedBox(width: 8),
              Text('Live analytics streaming active', style: TextStyle(color: _textVariant, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCPUCard() {
    final cpuValue = (_systemHealth?['cpu_utilization'] ?? 0.0) as num;
    final nodeName = _systemHealth?['active_node'] ?? 'NODE_01';
    
    return _buildStatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildIconBox(Icons.developer_board, Colors.white),
              _buildNodePill(nodeName),
            ],
          ),
          const SizedBox(height: 24),
          Text('${cpuValue.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          const Text('CPU CAPACITY', style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: (cpuValue / 100).clamp(0.0, 1.0), backgroundColor: _surfaceBright, color: Colors.white, minHeight: 4, borderRadius: BorderRadius.circular(2)),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.check_circle_outline, color: _textVariant, size: 14),
              SizedBox(width: 8),
              Text('Optimized background task distribution', style: TextStyle(color: _textVariant, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard() {
    final modelStatus = _systemHealth?['model_status'] ?? {};
    final modelName = modelStatus['name'] ?? 'Model Llama-X4';
    final state = modelStatus['state'] ?? 'ACTIVE';
    final progress = modelStatus['progress'] ?? 94;
    final latency = modelStatus['latency_ms'] ?? 12;
    
    return _buildStatCard(
      borderColor: _tealAccent.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildIconBox(Icons.data_usage, _tealAccent, bgOpacity: 0.0),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(modelName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text('Optimizing Weights', style: TextStyle(color: _tealAccent, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _tealAccent, borderRadius: BorderRadius.circular(4)),
                child: Text(state.toString().toUpperCase(), style: const TextStyle(color: Color(0xFF00382d), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Optimization Progress', style: TextStyle(color: _textVariant, fontSize: 11)),
              Text('$progress%', style: const TextStyle(color: _textVariant, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              6,
              (index) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  height: 6,
                  decoration: BoxDecoration(
                    color: index < (progress / 100 * 6).ceil() ? _tealAccent : _surfaceBright,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.bolt, color: _tealAccent, size: 16),
              const SizedBox(width: 8),
              Text('Inference latency: ${latency}ms', style: const TextStyle(color: _tealAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconBox(IconData icon, Color color, {double bgOpacity = 0.1}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withValues(alpha: bgOpacity), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildNodePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _surfaceBright,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: _textVariant, fontSize: 10, letterSpacing: 0.5)),
    );
  }

  Widget _buildChartsRow(bool isDesktop) {
    if (!isDesktop) {
      return Column(
        children: [
          _buildDonutChartCard(),
          const SizedBox(height: 16),
          _buildLineChartCard(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildDonutChartCard()),
        const SizedBox(width: 16),
        Expanded(flex: 3, child: _buildLineChartCard()),
      ],
    );
  }

  Widget _buildDonutChartCard() {
    final departments = _departmentResources ?? [];
    
    // Fallback if empty
    final displayDepts = departments.isNotEmpty ? departments : [
      {"name": "No Data", "percentage": 100, "raw_count": 0}
    ];
    
    final List<Color> palette = [
      _tealAccent,
      _cyanAccent,
      const Color(0xFF2DD4BF),
      _surfaceBright,
      Colors.orange,
      Colors.purple,
      Colors.pink,
    ];
    
    List<PieChartSectionData> sections = [];
    List<Widget> legendItems = [];
    
    for (int i = 0; i < displayDepts.length; i++) {
      final dept = displayDepts[i];
      final color = palette[i % palette.length];
      final percentage = (dept['percentage'] as num).toDouble();
      
      sections.add(PieChartSectionData(
        color: color,
        value: percentage > 0 ? percentage : 1, // ensure it shows a little sliver if 0
        title: '',
        radius: 12,
      ));
      
      legendItems.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildLegendItem(dept['name'], '${percentage.toInt()}%', color),
        ),
      );
    }

    return _buildStatCard(
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Departmental Resources', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Icon(Icons.more_vert, color: _textVariant, size: 20),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 4,
                        centerSpaceRadius: 55,
                        startDegreeOffset: 270,
                        sections: sections,
                      ),
                    ),
                    const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          Text('TOTAL LOAD', style: TextStyle(color: _textVariant, fontSize: 10, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: legendItems,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, String value, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLineChartCard() {
    final flowData = _patientFlow ?? [];
    List<FlSpot> spots = [];
    
    if (flowData.isNotEmpty) {
      for (var p in flowData) {
        spots.add(FlSpot((p['hour'] as num).toDouble(), (p['count'] as num).toDouble()));
      }
    } else {
      spots = const [FlSpot(0, 0)];
    }

    return _buildStatCard(
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Patient Flow (24h)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: _tealAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('Live', style: TextStyle(color: _tealAccent, fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  const Text('History', style: TextStyle(color: _textVariant, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withValues(alpha: 0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final v = value.toInt();
                        if (v % 4 == 0) {
                          final hourStr = v.toString().padLeft(2, '0');
                          return Text('$hourStr:00', style: TextStyle(color: _textVariant.withValues(alpha: 0.5), fontSize: 10));
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: _tealAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.x == spots.last.x, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: _tealAccent, strokeWidth: 0)),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [_tealAccent.withValues(alpha: 0.2), _tealAccent.withValues(alpha: 0.0)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityVault() {
    final alerts = _securityVault ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: _tealAccent, size: 24),
                SizedBox(width: 12),
                Text('Security Vault', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                Text('View Full Archive', style: TextStyle(color: _tealAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward, color: _tealAccent, size: 16),
              ],
            )
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('Timestamp', style: TextStyle(color: _textVariant, fontSize: 12, fontWeight: FontWeight.bold))),
                    Expanded(flex: 3, child: Text('Anomaly Type', style: TextStyle(color: _textVariant, fontSize: 12, fontWeight: FontWeight.bold))),
                    Expanded(flex: 3, child: Text('Detection Engine', style: TextStyle(color: _textVariant, fontSize: 12, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text('Risk Level', style: TextStyle(color: _textVariant, fontSize: 12, fontWeight: FontWeight.bold))),
                    Expanded(flex: 1, child: Text('Actions', style: TextStyle(color: _textVariant, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                  ],
                ),
              ),
              Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
              
              if (alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: Text('No recent security alerts', style: TextStyle(color: _textVariant))),
                )
              else
                ...alerts.map((alert) {
                  final severity = (alert['risk'] ?? 'ROUTINE').toString().toUpperCase();
                  Color iconColor = _tealAccent;
                  Color riskBg = Colors.white.withValues(alpha: 0.1);
                  IconData icon = Icons.verified_user_outlined;
                  
                  if (severity == 'CRITICAL' || severity == 'HIGH') {
                    iconColor = _critical;
                    riskBg = _criticalContainer;
                    icon = Icons.warning_amber_rounded;
                  } else if (severity == 'ELEVATED' || severity == 'MEDIUM') {
                    iconColor = _cyanAccent;
                    riskBg = _cyanAccent.withValues(alpha: 0.2);
                    icon = Icons.analytics_outlined;
                  }
                  
                  return Column(
                    children: [
                      _buildTableRow(
                        alert['timestamp'] ?? '',
                        alert['type'] ?? '',
                        icon,
                        iconColor,
                        alert['engine'] ?? '',
                        severity,
                        riskBg,
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                    ],
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTableRow(String time, String type, IconData icon, Color iconColor, String engine, String risk, Color riskBg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(time, style: const TextStyle(color: _textVariant, fontSize: 12))),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 8),
                Text(type, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text(engine, style: const TextStyle(color: _textVariant, fontSize: 13))),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: riskBg, borderRadius: BorderRadius.circular(4)),
                child: Text(risk, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.remove_red_eye_outlined, color: _tealAccent, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({required Widget child, double? height, Color? borderColor}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }
}
