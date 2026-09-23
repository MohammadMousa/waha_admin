import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/chart_ticks.dart';

class OrdersChart extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  const OrdersChart({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (series.isEmpty) return const Center(child: Text('No data'));

    final spots = series.asMap().entries.map((e) {
      final v = (e.value['value'] as num?)?.toDouble() ?? 0;
      return FlSpot(e.key.toDouble(), v);
    }).toList();

    final rawMaxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);
    final ticks = niceAxisTicks(rawMaxY);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: ticks.maxY,
        // The default Catmull-Rom smoothing can overshoot past 0 on a sharp
        // spike-then-drop (e.g. one big order day next to near-zero days) —
        // clip drawing to the chart bounds and cap the curve's own overshoot
        // so a non-negative metric never visually dips below the axis
        // (human lead, 2026-09-22).
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              s.y.toStringAsFixed(0),
              TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600, fontSize: 12),
            )).toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ticks.step,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: ticks.step,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: (series.length / 5).ceilToDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                final label = series[i]['label'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(label,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.15,
            preventCurveOverShooting: true,
            color: scheme.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
