import 'package:intl/intl.dart';

// Standard number display for the whole admin UI: thousands separators on
// anything above 3 digits (human lead's UI/UX rule, 2026-09-25).
final _money = NumberFormat('#,##0.00');
final _count = NumberFormat('#,##0');

/// 5422000 -> "5,422,000.00" (money and other decimal values, always 2 dp).
String fmtMoney(dynamic v) => _money.format(((v as num?) ?? 0).toDouble());

/// 103000 -> "103,000" (whole counts).
String fmtCount(dynamic v) => _count.format(((v as num?) ?? 0).round());

/// Averages: whole values show as a count ("20,600"), fractional ones with
/// 2 dp ("9,363.60").
String fmtAvg(dynamic v) {
  final d = ((v as num?) ?? 0).toDouble();
  return d == d.roundToDouble() ? fmtCount(d) : fmtMoney(d);
}
