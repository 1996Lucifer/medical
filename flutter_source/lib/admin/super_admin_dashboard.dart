import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:frontend/network/environment.dart';

import '../network/admin_dashboard_service.dart';
import '../network/network_manager.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
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

  // Theme-derived colors (Aetheris Command dark / Clinical Clarity light)
  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _bgBase => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceContainer => Theme.of(context).colorScheme.surfaceContainer;
  Color get _surfaceBright => Theme.of(context).colorScheme.surfaceBright;
  Color get _tealAccent => Theme.of(context).colorScheme.secondary;
  Color get _cyanAccent => Theme.of(context).colorScheme.tertiary;
  Color get _textVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _critical => Theme.of(context).colorScheme.error;
  Color get _criticalContainer => Theme.of(context).colorScheme.errorContainer;

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
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: _tealAccent))
                : _error != null
                    ? Center(
                        child: Text('Error: $_error',
                            style: TextStyle(color: _critical)))
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

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System Health',
              style: TextStyle(
                  color: _primary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Real-time neural network performance across the local node.',
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
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: _tealAccent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('Live Stream Active',
                  style: TextStyle(
                      color: _tealAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
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
      _buildRAMCard(),
    ];

    if (!isDesktop) {
      return Column(
          children: cards
              .map((c) =>
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: c))
              .toList());
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
          Text('${gpuValue.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: _primary,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          Text('GPU UTILIZATION',
              style: TextStyle(
                  color: _textVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          const SizedBox(height: 16),
          LinearProgressIndicator(
              value: (gpuValue / 100).clamp(0.0, 1.0),
              backgroundColor: _surfaceBright,
              color: _tealAccent,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2)),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.trending_up, color: _textVariant, size: 14),
              const SizedBox(width: 8),
              Text('Live analytics streaming active',
                  style: TextStyle(color: _textVariant, fontSize: 11)),
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
              _buildIconBox(Icons.developer_board, _primary),
              _buildNodePill(nodeName),
            ],
          ),
          const SizedBox(height: 24),
          Text('${cpuValue.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: _primary,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          Text('CPU CAPACITY',
              style: TextStyle(
                  color: _textVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          const SizedBox(height: 16),
          LinearProgressIndicator(
              value: (cpuValue / 100).clamp(0.0, 1.0),
              backgroundColor: _surfaceBright,
              color: _primary,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2)),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: _textVariant, size: 14),
              const SizedBox(width: 8),
              Text('Optimized background task distribution',
                  style: TextStyle(color: _textVariant, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRAMCard() {
    final ramValue = (_systemHealth?['ram_utilization'] ?? 0.0) as num;
    final nodeName = _systemHealth?['active_node'] ?? 'NODE_01';

    return _buildStatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildIconBox(Icons.storage, _cyanAccent),
              _buildNodePill(nodeName),
            ],
          ),
          const SizedBox(height: 24),
          Text('${ramValue.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: _primary,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          Text('RAM UTILIZATION',
              style: TextStyle(
                  color: _textVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          const SizedBox(height: 16),
          LinearProgressIndicator(
              value: (ramValue / 100).clamp(0.0, 1.0),
              backgroundColor: _surfaceBright,
              color: _cyanAccent,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2)),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.data_usage, color: _textVariant, size: 14),
              const SizedBox(width: 8),
              Text('Live memory tracking active',
                  style: TextStyle(color: _textVariant, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconBox(IconData icon, Color color, {double bgOpacity = 0.1}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: color.withValues(alpha: bgOpacity),
          borderRadius: BorderRadius.circular(8)),
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
      child: Text(text,
          style: TextStyle(
              color: _textVariant, fontSize: 10, letterSpacing: 0.5)),
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
    final displayDepts = departments.isNotEmpty
        ? departments
        : [
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
        value: percentage > 0
            ? percentage
            : 1, // ensure it shows a little sliver if 0
        title: '',
        radius: 12,
      ));

      legendItems.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child:
              _buildLegendItem(dept['name'], '${percentage.toInt()}%', color),
        ),
      );
    }

    return _buildStatCard(
      height: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Departmental Resources',
                  style: TextStyle(
                      color: _primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
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
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('LIVE',
                              style: TextStyle(
                                  color: _primary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold)),
                          Text('TOTAL LOAD',
                              style: TextStyle(
                                  color: _textVariant,
                                  fontSize: 10,
                                  letterSpacing: 0.5)),
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
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(title,
                style: TextStyle(color: _primary, fontSize: 12),
                overflow: TextOverflow.ellipsis)),
        Text(value,
            style: TextStyle(
                color: _primary,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLineChartCard() {
    final flowData = _patientFlow ?? [];
    List<FlSpot> spots = [];

    if (flowData.isNotEmpty) {
      for (var p in flowData) {
        spots.add(FlSpot(
            (p['hour'] as num).toDouble(), (p['count'] as num).toDouble()));
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
              Text('Patient Flow (24h)',
                  style: TextStyle(
                      color: _primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: _tealAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('Live',
                        style: TextStyle(color: _tealAccent, fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  Text('History',
                      style: TextStyle(color: _textVariant, fontSize: 11)),
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
                  getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white.withValues(alpha: 0.05),
                      strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final v = value.toInt();
                        if (v % 4 == 0) {
                          final hourStr = v.toString().padLeft(2, '0');
                          return Text('$hourStr:00',
                              style: TextStyle(
                                  color: _textVariant.withValues(alpha: 0.5),
                                  fontSize: 10));
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
                    dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, barData) =>
                            spot.x == spots.last.x,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                                radius: 4, color: _tealAccent, strokeWidth: 0)),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          _tealAccent.withValues(alpha: 0.2),
                          _tealAccent.withValues(alpha: 0.0)
                        ],
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: _tealAccent, size: 24),
                const SizedBox(width: 12),
                Text('Security Vault',
                    style: TextStyle(
                        color: _primary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                Text('View Full Archive',
                    style: TextStyle(
                        color: _tealAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text('Timestamp',
                            style: TextStyle(
                                color: _textVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 3,
                        child: Text('Anomaly Type',
                            style: TextStyle(
                                color: _textVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 3,
                        child: Text('Detection Engine',
                            style: TextStyle(
                                color: _textVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('Risk Level',
                            style: TextStyle(
                                color: _textVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 1,
                        child: Text('Actions',
                            style: TextStyle(
                                color: _textVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right)),
                  ],
                ),
              ),
              Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
              if (alerts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                      child: Text('No recent security alerts',
                          style: TextStyle(color: _textVariant))),
                )
              else
                ...alerts.map((alert) {
                  final severity =
                      (alert['risk'] ?? 'ROUTINE').toString().toUpperCase();
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
                        context,
                        alert['timestamp'] ?? '',
                        alert['type'] ?? '',
                        icon,
                        iconColor,
                        alert['engine'] ?? '',
                        severity,
                        riskBg,
                        alert['snapshot_path'],
                        alert['zone'],
                        alert['camera_name'],
                        alert['staff_name'],
                      ),
                      Divider(
                          color: Colors.white.withValues(alpha: 0.05),
                          height: 1),
                    ],
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTableRow(
      BuildContext context,
      String time,
      String type,
      IconData icon,
      Color iconColor,
      String engine,
      String risk,
      Color riskBg,
      String? snapshotPath,
      String? zone,
      String? cameraName,
      String? staffName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(time,
                  style: TextStyle(color: _textVariant, fontSize: 12))),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 8),
                Text(type,
                    style: TextStyle(
                        color: _primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
              flex: 3,
              child: Text(engine,
                  style: TextStyle(color: _textVariant, fontSize: 13))),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: riskBg, borderRadius: BorderRadius.circular(4)),
                child: Text(risk,
                    style: TextStyle(
                        color: _primary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: snapshotPath != null
                  ? IconButton(
                      icon: Icon(Icons.remove_red_eye_outlined,
                          color: _tealAccent, size: 18),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (dialogContext) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(dialogContext).pop(),
                            child: Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 24),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 520,
                                  maxHeight:
                                      MediaQuery.of(dialogContext).size.height *
                                          0.85,
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (zone != null ||
                                            cameraName != null ||
                                            staffName != null)
                                          Container(
                                            width: double.infinity,
                                            margin:
                                                const EdgeInsets.only(bottom: 12),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: Theme.of(dialogContext)
                                                  .colorScheme
                                                  .surfaceContainerHigh,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (zone != null ||
                                                    cameraName != null)
                                                  Row(
                                                    children: [
                                                      Icon(Icons.location_on,
                                                          color: _tealAccent,
                                                          size: 16),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          [
                                                            if (zone != null)
                                                              zone,
                                                            if (cameraName !=
                                                                null)
                                                              cameraName,
                                                          ].join(' · '),
                                                          style: TextStyle(
                                                              color: _primary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 14),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                if (zone != null ||
                                                    cameraName != null)
                                                  const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Icon(
                                                        staffName != null
                                                            ? Icons
                                                                .badge_outlined
                                                            : Icons
                                                                .person_off_outlined,
                                                        color: staffName != null
                                                            ? _tealAccent
                                                            : _critical,
                                                        size: 16),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                        staffName != null
                                                            ? 'Recognized: $staffName'
                                                            : 'Unrecognized person',
                                                        style: TextStyle(
                                                            color: staffName !=
                                                                    null
                                                                ? _primary
                                                                : _critical,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                            fontSize: 13)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        Flexible(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.network(
                                              '${EnvironmentConfig.current.baseUrl.replaceAll('/api', '')}/$snapshotPath',
                                              headers: NetworkManager.instance
                                                          .token !=
                                                      null
                                                  ? {
                                                      'Authorization':
                                                          'Bearer ${NetworkManager.instance.token}'
                                                    }
                                                  : null,
                                              fit: BoxFit.contain,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  Padding(
                                                padding:
                                                    const EdgeInsets.all(16.0),
                                                child: Text(
                                                    "Error loading image",
                                                    style: TextStyle(
                                                        color: _primary)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Positioned(
                                      top: -14,
                                      right: -14,
                                      child: Material(
                                        color: Colors.black87,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () =>
                                              Navigator.of(dialogContext).pop(),
                                          child: const Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Icon(Icons.close,
                                                color: Colors.white, size: 18),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : Icon(Icons.remove_red_eye_outlined,
                      color: _textVariant, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      {required Widget child, double? height, Color? borderColor}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }
}
