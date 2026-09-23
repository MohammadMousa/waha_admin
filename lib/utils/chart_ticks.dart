import 'dart:math' as math;

/// A Y-axis tick plan: a clean, round step and the axis's rounded max, so
/// gridlines and axis labels always land on the same human-friendly numbers
/// (0, 1k, 2k, 3k... never 0, 1.1k, 2.3k, 3.6k...).
class AxisTicks {
  final double step;
  final double maxY;
  const AxisTicks(this.step, this.maxY);
}

/// Classic "nice numbers" axis-tick algorithm (Heckbert): picks a step from
/// {1, 2, 5} × 10^n closest to `maxValue / targetTicks`, then rounds
/// maxValue up to the next multiple of that step. Use the same `step` for
/// both grid lines and axis label `interval` so a chart's whole Y-axis uses
/// one fixed, consistent increment (human lead, 2026-09-22).
AxisTicks niceAxisTicks(double maxValue, {int targetTicks = 5}) {
  if (maxValue <= 0) return AxisTicks(1, targetTicks.toDouble());
  final step = _niceStep(maxValue / targetTicks);
  var maxY = (maxValue / step).ceil() * step;
  // Keep the top bar/line off the very edge when the data max already lands
  // exactly on a tick.
  if (maxY - maxValue < step * 0.1) maxY += step;
  return AxisTicks(step, maxY);
}

double _niceStep(double rawStep) {
  final exponent = (math.log(rawStep) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  final fraction = rawStep / magnitude;
  final double niceFraction;
  if (fraction <= 1) {
    niceFraction = 1;
  } else if (fraction <= 2) {
    niceFraction = 2;
  } else if (fraction <= 5) {
    niceFraction = 5;
  } else {
    niceFraction = 10;
  }
  return niceFraction * magnitude;
}
