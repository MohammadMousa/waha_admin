import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/chart_ticks.dart';

class MonthlyBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  const MonthlyBarChart({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const Center(child: Text('No data'));

    final maxVal = series
        .map((e) => (e['value'] as num?)?.toDouble() ?? 0)
        .fold(0.0, (a, b) => a > b ? a : b);

    final ticks = niceAxisTicks(maxVal);

    return BarChart(
      BarChartData(
        maxY: ticks.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ticks.step,
          getDrawingHorizontalLine: (v) {
            // Make the zero line more visible
            if (v == 0) {
              return FlLine(
                color: Colors.grey.withValues(alpha: 0.5),
                strokeWidth: 1.5,
              );
            }
            return FlLine(
              color: Colors.grey.withValues(alpha: 0.12),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: ticks.step,
              getTitlesWidget: (v, meta) {
                final label = v >= 1000
                    ? '${(v / 1000).toStringAsFixed(1)}k'
                    : v.toStringAsFixed(0);
                return Text(label,
                    style: const TextStyle(fontSize: 10, color: Colors.grey));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32, // more space between bars and labels
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                final label = series[i]['label'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.4), width: 1),
          ),
        ),
        barGroups: series.asMap().entries.map((e) {
          final v = (e.value['value'] as num?)?.toDouble() ?? 0;
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: v,
                color: const Color(0xFF7C7CED),
                width: 22,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
