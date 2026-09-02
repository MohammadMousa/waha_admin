import 'dart:math' as math;

import 'package:flutter/material.dart';

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final double? pctChange;
  final IconData icon;
  final List<double>? sparkline;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.pctChange,
    this.icon = Icons.shopping_bag_outlined,
    this.sparkline,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNeg  = pctChange != null && pctChange! < 0;
    final pctColor = isNeg ? const Color(0xFFE53935) : const Color(0xFF43A047);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label + icon/sparkline
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Sparkline or icon
                if (sparkline != null && sparkline!.length > 1)
                  ClipRect(
                    child: SizedBox(
                      width: 72,
                      height: 40,
                      child: _Sparkline(
                        data: sparkline!,
                        color: isNeg ? const Color(0xFFE53935) : scheme.primary,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: scheme.primary, size: 20),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Value
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),

            // % change badge
            if (pctChange != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: pctColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isNeg ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 11,
                          color: pctColor,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${pctChange!.abs().toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: pctColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Mini sparkline ────────────────────────────────────────────────────────────

class _Sparkline extends StatelessWidget {
  final List<double> data;
  final Color color;
  const _Sparkline({required this.data, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _SparklinePainter(data, color),
      );
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  const _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).abs();
    final effectiveRange = range < 1e-6 ? 1.0 : range;

    double x(int i) =>
        (i / (data.length - 1)) * size.width;
    double y(double v) =>
        size.height - ((v - minV) / effectiveRange) * size.height * 0.8 - size.height * 0.1;

    final path = Path()..moveTo(x(0), y(data[0]));
    for (int i = 1; i < data.length; i++) {
      final cx = (x(i - 1) + x(i)) / 2;
      path.cubicTo(cx, y(data[i - 1]), cx, y(data[i]), x(i), y(data[i]));
    }

    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    // Fill under the line
    final fill = Path.from(path)
      ..lineTo(x(data.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..color = color.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data != data || old.color != color;
}
