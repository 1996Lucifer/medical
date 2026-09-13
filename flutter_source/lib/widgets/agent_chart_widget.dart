import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Renders a chart spec sent by the backend's /api/agent/chat response
/// (see backend/services/llm/chart_builder.py) - built directly from real
/// SQL rows server-side, never from LLM-generated text, so the numbers
/// shown here can't be hallucinated. Supports the two chart types the
/// backend currently produces: "pie" and "bar".
class AgentChartWidget extends StatelessWidget {
  final Map<String, dynamic> chart;

  const AgentChartWidget({super.key, required this.chart});

  static const _palette = [
    Color(0xFF2DD4BF),
    Color(0xFF60A5FA),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFA78BFA),
    Color(0xFFF472B6),
    Color(0xFF34D399),
    Color(0xFFFB923C),
  ];

  List<String> get _labels => (chart['labels'] as List).map((e) => e.toString()).toList();
  List<double> get _values => (chart['values'] as List)
      .map((e) => (e as num).toDouble())
      .toList();
  String get _title => chart['title']?.toString() ?? '';
  String get _type => chart['type']?.toString() ?? 'bar';

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    final values = _values;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    if (labels.isEmpty || values.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: onSurfaceVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _title,
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          SizedBox(
            height: 220,
            child: _type == 'pie'
                ? _buildPieChart(labels, values, onSurface)
                : _buildBarChart(labels, values, onSurface, onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart(List<String> labels, List<double> values, Color onSurface) {
    final total = values.fold<double>(0, (sum, v) => sum + v);
    final sections = <PieChartSectionData>[];
    for (int i = 0; i < labels.length; i++) {
      final color = _palette[i % _palette.length];
      final pct = total > 0 ? (values[i] / total * 100) : 0;
      sections.add(PieChartSectionData(
        color: color,
        value: values[i] > 0 ? values[i] : 0.001,
        title: '${pct.toStringAsFixed(0)}%',
        radius: 70,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ));
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
              centerSpaceRadius: 32,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView.builder(
            itemCount: labels.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _palette[i % _palette.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      labels[i],
                      style: TextStyle(color: onSurface, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart(
    List<String> labels,
    List<double> values,
    Color onSurface,
    Color onSurfaceVariant,
  ) {
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(color: onSurfaceVariant, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[i],
                    style: TextStyle(color: onSurfaceVariant, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < labels.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: _palette[i % _palette.length],
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
