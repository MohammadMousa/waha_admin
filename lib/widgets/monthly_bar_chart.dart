import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/chart_ticks.dart';

class MonthlyBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  const MonthlyBarChart({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    if (series.isEmpty) return const Center(child: Text('No data'));

    final maxVal = series
        .map((e) => (e['value'] as num?)?.toDouble() ?? 0)
        .fold(0.0, (a, b) => a > b ? a : b);

    final ticks = niceAxisTicks(maxVal);
    final scheme = Theme.of(context).colorScheme;

    // The month still in progress is drawn lighter and labelled "(to date)",
    // so a partly finished month does not look like a drop in sales.
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final thisMonth = '${months[now.month - 1]} ${now.year}';
    final partial = series.isNotEmpty && series.last['label'] == thisMonth
        ? series.length - 1
        : -1;

    String short(double v) {
      if (v >= 1000) {
        final k = v / 1000;
        return '${k.toStringAsFixed(k >= 100 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '')}k';
      }
      return v.toStringAsFixed(0);
    }

    return BarChart(
      BarChartData(
        maxY: ticks.maxY,
        // Values are always shown above the bars, so no hover is needed.
        barTouchData: BarTouchData(
          handleBuiltInTouches: false,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 2,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              short(rod.toY),
              TextStyle(fontSize: 10, color: scheme.onSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ),
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
                var label = series[i]['label'] as String? ?? '';
                if (i == partial && !narrow) {
                  label = '${label.split(' ').first} (to date)';
                }
                // Phones: "Jun 2026" becomes "Jun 26" and long ranges show
                // only some months, so the labels never overlap.
                if (narrow) {
                  final step = (series.length / 6).ceil();
                  if (i % (step < 1 ? 1 : step) != 0) return const SizedBox.shrink();
                  final parts = label.split(' ');
                  if (parts.length == 2 && parts[1].length == 4) {
                    label = '${parts[0]} ${parts[1].substring(2)}';
                  }
                }
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
          final isPartial = e.key == partial;
          return BarChartGroupData(
            x: e.key,
            showingTooltipIndicators: v > 0 ? [0] : const [],
            barRods: [
              BarChartRodData(
                toY: v,
                color: const Color(0xFF7C7CED).withValues(alpha: isPartial ? 0.35 : 1),
                borderSide: isPartial
                    ? const BorderSide(color: Color(0xFF7C7CED), width: 1)
                    : BorderSide.none,
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
