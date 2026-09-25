import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/chart_ticks.dart';
import '../widgets/error_dialog.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/waha_date_picker.dart';

// ── Visualization type ────────────────────────────────────────────────────────

enum _Vis { line, bar, pie }

// ── Per-endpoint state ────────────────────────────────────────────────────────

class _EpState {
  List<Map<String, dynamic>> data;
  bool loading;
  String? error;
  bool generated;

  _EpState()
      : data = [],
        loading = false,
        error = null,
        generated = false;
}

// ── Per-group state ───────────────────────────────────────────────────────────

class _Group {
  DateTimeRange range;
  _Vis vis;
  int cols;
  double heightMult;
  bool collapsed;
  Map<String, _EpState> eps;

  _Group({
    required this.range,
    required this.vis,
    required List<String> endpoints,
  })  : cols = 2,
        heightMult = 1.0,
        collapsed = true,
        eps = Map.fromEntries(endpoints.map((e) => MapEntry(e, _EpState())));
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  late final _Group _hourly;
  late final _Group _daily;
  late final _Group _monthly;
  late final _Group _entity;

  static const _hourlyEps   = ['revenue-by-hours', 'orders-by-hours'];
  static const _dailyEps    = ['revenue-by-days', 'orders-by-days'];
  static const _monthlyEps  = ['revenue-by-months', 'orders-by-months'];
  static const _entityEps   = ['revenue-by-products', 'revenue-by-categories', 'revenue-by-branches'];

  static const _epLabels = {
    'revenue-by-hours':      'Revenue by Hour',
    'orders-by-hours':       'Orders by Hour',
    'revenue-by-days':       'Revenue by Day',
    'orders-by-days':        'Orders by Day',
    'revenue-by-months':     'Revenue by Month',
    'orders-by-months':      'Orders by Month',
    'revenue-by-products':   'By Products',
    'revenue-by-categories': 'By Categories',
    'revenue-by-branches':   'By Branches',
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _hourly = _Group(
      range: DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now),
      vis: _Vis.line,
      endpoints: _hourlyEps,
    );
    _daily = _Group(
      range: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      vis: _Vis.line,
      endpoints: _dailyEps,
    );
    _monthly = _Group(
      range: DateTimeRange(start: DateTime(now.year - 1, now.month, 1), end: now),
      vis: _Vis.bar,
      endpoints: _monthlyEps,
    );
    _entity = _Group(
      range: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      vis: _Vis.bar,
      endpoints: _entityEps,
    );
  }

  Future<void> _generate(_Group g, String ep) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() {
      g.eps[ep]!.loading = true;
      g.eps[ep]!.error = null;
    });
    try {
      final rows = await ApiClient().getChartData(
          token: token, endpoint: ep, from: g.range.start, to: g.range.end);
      if (!mounted) return;
      setState(() {
        g.eps[ep]!.data = rows;
        g.eps[ep]!.loading = false;
        g.eps[ep]!.generated = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          g.eps[ep]!.error = e.toString();
          g.eps[ep]!.loading = false;
          g.eps[ep]!.generated = true;
        });
      }
    }
  }

  Future<void> _refreshAll(_Group g, List<String> endpoints) async {
    for (final ep in endpoints) {
      if (g.eps[ep]!.generated) _generate(g, ep);
    }
  }

  Future<void> _pickRange(_Group g, List<String> endpoints, {int maxDays = 0}) async {
    final picked = await showWahaDateRangePicker(context, initial: g.range);
    if (picked == null || !mounted) return;
    if (maxDays > 0 && picked.end.difference(picked.start).inDays > maxDays) {
      showErrorDialog(context, 'Range cannot exceed $maxDays days for this group');
      return;
    }
    setState(() => g.range = picked);
    _refreshAll(g, endpoints);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.charts),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Text('Charts',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    child: Column(
                      children: [
                        _GroupSection(
                          title: 'Hourly Reports',
                          subtitle: 'Max 24 hours — pick a single day',
                          group: _hourly,
                          visOptions: const [_Vis.line, _Vis.bar],
                          endpoints: _hourlyEps,
                          epLabels: _epLabels,
                          onToggleCollapse: () => setState(() => _hourly.collapsed = !_hourly.collapsed),
                          onPickRange: () => _pickRange(_hourly, _hourlyEps, maxDays: 1),
                          onVisChange: (v) => setState(() => _hourly.vis = v),
                          onRefreshAll: () => _refreshAll(_hourly, _hourlyEps),
                          onGenerate: (ep) => _generate(_hourly, ep),
                          onColsChange: (c) => setState(() => _hourly.cols = c),
                          onHeightChange: (h) => setState(() => _hourly.heightMult = h),
                        ),
                        const SizedBox(height: 20),
                        _GroupSection(
                          title: 'Daily Reports',
                          subtitle: 'Max 2 months',
                          group: _daily,
                          visOptions: const [_Vis.line, _Vis.bar],
                          endpoints: _dailyEps,
                          epLabels: _epLabels,
                          onToggleCollapse: () => setState(() => _daily.collapsed = !_daily.collapsed),
                          onPickRange: () => _pickRange(_daily, _dailyEps, maxDays: 62),
                          onVisChange: (v) => setState(() => _daily.vis = v),
                          onRefreshAll: () => _refreshAll(_daily, _dailyEps),
                          onGenerate: (ep) => _generate(_daily, ep),
                          onColsChange: (c) => setState(() => _daily.cols = c),
                          onHeightChange: (h) => setState(() => _daily.heightMult = h),
                        ),
                        const SizedBox(height: 20),
                        _GroupSection(
                          title: 'Monthly Reports',
                          subtitle: 'Max 24 months',
                          group: _monthly,
                          visOptions: const [_Vis.line, _Vis.bar],
                          endpoints: _monthlyEps,
                          epLabels: _epLabels,
                          onToggleCollapse: () => setState(() => _monthly.collapsed = !_monthly.collapsed),
                          onPickRange: () => _pickRange(_monthly, _monthlyEps, maxDays: 730),
                          onVisChange: (v) => setState(() => _monthly.vis = v),
                          onRefreshAll: () => _refreshAll(_monthly, _monthlyEps),
                          onGenerate: (ep) => _generate(_monthly, ep),
                          onColsChange: (c) => setState(() => _monthly.cols = c),
                          onHeightChange: (h) => setState(() => _monthly.heightMult = h),
                        ),
                        const SizedBox(height: 20),
                        _GroupSection(
                          title: 'Performance Reports',
                          subtitle: 'Revenue by products, categories, and branches',
                          group: _entity,
                          visOptions: const [_Vis.bar, _Vis.pie],
                          endpoints: _entityEps,
                          epLabels: _epLabels,
                          onToggleCollapse: () => setState(() => _entity.collapsed = !_entity.collapsed),
                          onPickRange: () => _pickRange(_entity, _entityEps),
                          onVisChange: (v) => setState(() => _entity.vis = v),
                          onRefreshAll: () => _refreshAll(_entity, _entityEps),
                          onGenerate: (ep) => _generate(_entity, ep),
                          onColsChange: (c) => setState(() => _entity.cols = c),
                          onHeightChange: (h) => setState(() => _entity.heightMult = h),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group section card ────────────────────────────────────────────────────────

class _GroupSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final _Group group;
  final List<_Vis> visOptions;
  final List<String> endpoints;
  final Map<String, String> epLabels;
  final VoidCallback onToggleCollapse;
  final VoidCallback onPickRange;
  final ValueChanged<_Vis> onVisChange;
  final VoidCallback onRefreshAll;
  final ValueChanged<String> onGenerate;
  final ValueChanged<int> onColsChange;
  final ValueChanged<double> onHeightChange;

  const _GroupSection({
    required this.title,
    required this.subtitle,
    required this.group,
    required this.visOptions,
    required this.endpoints,
    required this.epLabels,
    required this.onToggleCollapse,
    required this.onPickRange,
    required this.onVisChange,
    required this.onRefreshAll,
    required this.onGenerate,
    required this.onColsChange,
    required this.onHeightChange,
  });

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anyLoading = group.eps.values.any((s) => s.loading);
    final collapsed = group.collapsed;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: collapsed
                  ? BorderRadius.circular(16)
                  : const BorderRadius.vertical(top: Radius.circular(16)),
              border: collapsed
                  ? null
                  : Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700,
                                  color: scheme.onSurface)),
                          Text(subtitle,
                              style: TextStyle(fontSize: 11, color: scheme.outline)),
                        ],
                      ),
                    ),
                    if (!collapsed) ...[
                      // Date picker
                      GestureDetector(
                        onTap: onPickRange,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.calendar_today_outlined, size: 14, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              '${_fmtDate(group.range.start)}  –  ${_fmtDate(group.range.end)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Vis type picker
                      _VisPicker(
                        options: visOptions,
                        selected: group.vis,
                        onSelect: onVisChange,
                      ),
                      const SizedBox(width: 6),
                      // Refresh all generated
                      IconButton(
                        icon: anyLoading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.refresh_outlined, color: scheme.primary),
                        tooltip: 'Refresh all generated',
                        onPressed: anyLoading ? null : onRefreshAll,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                    // Collapse / expand toggle
                    IconButton(
                      icon: AnimatedRotation(
                        turns: collapsed ? 0.0 : 0.5,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more_rounded, color: scheme.outline),
                      ),
                      tooltip: collapsed ? 'Expand' : 'Collapse',
                      onPressed: onToggleCollapse,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (!collapsed) ...[
                  const SizedBox(height: 10),
                  // Layout controls row
                  Row(
                    children: [
                      Text('Columns:', style: TextStyle(fontSize: 11, color: scheme.outline)),
                      const SizedBox(width: 6),
                      ...[1, 2, 3].map((c) => _SmallToggleBtn(
                            label: '$c',
                            selected: group.cols == c,
                            onTap: () => onColsChange(c),
                          )),
                      const SizedBox(width: 16),
                      Text('Height:', style: TextStyle(fontSize: 11, color: scheme.outline)),
                      const SizedBox(width: 6),
                      ...const [
                        (1.0, 'x'),
                        (1.5, '1.5x'),
                        (2.0, '2x'),
                      ].map(((double, String) entry) => _SmallToggleBtn(
                            label: entry.$2,
                            selected: group.heightMult == entry.$1,
                            onTap: () => onHeightChange(entry.$1),
                          )),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Chart grid — hidden when collapsed
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildGrid(context, scheme),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, ColorScheme scheme) {
    final chartH = 220.0 * group.heightMult;
    final cols = group.cols;

    final panels = endpoints.map((ep) {
      final st = group.eps[ep]!;
      return _ChartPanel(
        label: epLabels[ep] ?? ep,
        vis: group.vis,
        epState: st,
        chartHeight: chartH,
        onGenerate: () => onGenerate(ep),
      );
    }).toList();

    // Build rows of `cols` panels
    final rows = <Widget>[];
    for (int i = 0; i < panels.length; i += cols) {
      final rowItems = panels.sublist(i, (i + cols).clamp(0, panels.length));
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int j = 0; j < rowItems.length; j++) ...[
            if (j > 0) const SizedBox(width: 12),
            Expanded(child: rowItems[j]),
          ],
          // Fill empty cells to keep grid shape
          for (int j = rowItems.length; j < cols; j++) ...[
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ],
        ],
      );
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(row);
    }

    return Column(children: rows);
  }
}

// ── Small toggle button ───────────────────────────────────────────────────────

class _SmallToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SmallToggleBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? scheme.primary : scheme.outline)),
      ),
    );
  }
}

// ── Visualization picker ──────────────────────────────────────────────────────

class _VisPicker extends StatelessWidget {
  final List<_Vis> options;
  final _Vis selected;
  final ValueChanged<_Vis> onSelect;

  const _VisPicker(
      {required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: options.map((v) => _VisCard(
            vis: v,
            selected: selected == v,
            onTap: () => onSelect(v),
          )).toList(),
    );
  }
}

class _VisCard extends StatelessWidget {
  final _Vis vis;
  final bool selected;
  final VoidCallback onTap;
  const _VisCard({required this.vis, required this.selected, required this.onTap});

  static const _labels = {_Vis.line: 'Line', _Vis.bar: 'Bar', _Vis.pie: 'Pie'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.outline;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(right: 6),
        width: 68,
        padding: const EdgeInsets.fromLTRB(5, 6, 5, 5),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Container(
                height: 46,
                color: selected
                    ? scheme.primary.withValues(alpha: 0.07)
                    : scheme.surface.withValues(alpha: 0.7),
                child: _VisMini(vis: vis, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(_labels[vis] ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.normal,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

class _VisMini extends StatelessWidget {
  final _Vis vis;
  final Color color;
  const _VisMini({required this.vis, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: switch (vis) {
        _Vis.line => _MiniLinePainter(color),
        _Vis.bar  => _MiniBarPainter(color),
        _Vis.pie  => _MiniPiePainter(color),
      },
    );
  }
}

class _MiniLinePainter extends CustomPainter {
  final Color color;
  const _MiniLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    // Rising trend with natural variation
    final ys = [0.78, 0.62, 0.70, 0.42, 0.55, 0.30, 0.45, 0.18];
    final pts = List.generate(
        ys.length, (i) => Offset(i / (ys.length - 1) * w, ys[i] * h));

    // Smooth bezier path
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final mx = (pts[i].dx + pts[i + 1].dx) / 2;
      path.cubicTo(mx, pts[i].dy, mx, pts[i + 1].dy,
          pts[i + 1].dx, pts[i + 1].dy);
    }

    // Gradient fill under curve
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Line stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots at notable points
    for (final pt in [pts[3], pts[5], pts[7]]) {
      canvas.drawCircle(pt, 2.5, Paint()..color = color);
      canvas.drawCircle(pt, 1.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_MiniLinePainter o) => o.color != color;
}

class _MiniBarPainter extends CustomPainter {
  final Color color;
  const _MiniBarPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const hs = [0.45, 0.62, 0.38, 0.85, 0.55, 0.72, 0.92, 0.50];
    final n = hs.length;
    final barW = size.width / n * 0.62;
    final step = size.width / n;
    final offset = (step - barW) / 2;

    for (int i = 0; i < n; i++) {
      final x = i * step + offset;
      final h = size.height * hs[i];
      final rect = Rect.fromLTWH(x, size.height - h, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect,
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withValues(alpha: 0.45)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_MiniBarPainter o) => o.color != color;
}

class _MiniPiePainter extends CustomPainter {
  final Color color;
  const _MiniPiePainter(this.color);

  // Fixed vivid palette — looks good regardless of the card's tint color
  static const _slices = [
    (0.32, Color(0xFF4FC3F7)),
    (0.23, Color(0xFFFF8A65)),
    (0.20, Color(0xFF81C784)),
    (0.15, Color(0xFFCE93D8)),
    (0.10, Color(0xFFFFD54F)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = size.shortestSide / 2 - 2;
    final c = Offset(size.width / 2, size.height / 2);
    double start = -1.5708;
    const gap = 0.05; // radians gap between slices

    for (final (pct, cl) in _slices) {
      final sweep = pct * 6.2832 - gap;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start + gap / 2,
        sweep,
        true,
        Paint()..color = cl,
      );
      start += pct * 6.2832;
    }
  }

  @override
  bool shouldRepaint(_MiniPiePainter o) => o.color != color;
}

// ── Chart panel ───────────────────────────────────────────────────────────────

class _ChartPanel extends StatelessWidget {
  final String label;
  final _Vis vis;
  final _EpState epState;
  final double chartHeight;
  final VoidCallback onGenerate;

  const _ChartPanel({
    required this.label,
    required this.vis,
    required this.epState,
    required this.chartHeight,
    required this.onGenerate,
  });

  void _openFullscreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 48,
            maxHeight: MediaQuery.of(context).size.height - 80,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _buildChart(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (epState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (epState.error != null) {
      return Center(
        child: Text(epState.error!,
            style: TextStyle(color: scheme.error, fontSize: 12)),
      );
    }
    if (epState.data.isEmpty) {
      return Center(child: Text('No data', style: TextStyle(color: scheme.outline)));
    }
    return vis == _Vis.pie
        ? _PieChart(data: epState.data)
        : _SeriesChart(vis: vis, data: epState.data);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (epState.generated)
                IconButton(
                  icon: Icon(Icons.fullscreen_outlined, size: 18, color: scheme.outline),
                  tooltip: 'Fullscreen',
                  onPressed: () => _openFullscreen(context),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Not yet generated — show Generate button
          if (!epState.generated)
            SizedBox(
              height: chartHeight,
              child: Center(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.bar_chart_outlined, size: 18),
                  label: const Text('Generate'),
                  onPressed: onGenerate,
                ),
              ),
            )
          else
            SizedBox(
              height: chartHeight,
              child: _buildChart(context),
            ),
        ],
      ),
    );
  }
}

// ── Pie chart ─────────────────────────────────────────────────────────────────

class _PieChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _PieChart({required this.data});

  static const _palette = [
    Color(0xFF7C7CED), Color(0xFF4CAF50), Color(0xFFFF9800),
    Color(0xFFE91E63), Color(0xFF00BCD4), Color(0xFF9C27B0),
    Color(0xFF795548), Color(0xFF607D8B),
  ];

  @override
  Widget build(BuildContext context) {
    final total =
        data.fold<double>(0, (s, e) => s + ((e['value'] as num?)?.toDouble() ?? 0));
    final sections = data.asMap().entries.map((e) {
      final v = (e.value['value'] as num?)?.toDouble() ?? 0;
      return PieChartSectionData(
        value: v,
        color: _palette[e.key % _palette.length],
        title: total > 0 ? '${(v / total * 100).toStringAsFixed(1)}%' : '',
        radius: 70,
        titleStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
      );
    }).toList();

    return Row(children: [
      Expanded(
        child: PieChart(PieChartData(sections: sections, sectionsSpace: 2)),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.asMap().entries.map((e) {
            final lbl = (e.value['label'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _palette[e.key % _palette.length],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(lbl,
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }
}

// ── Line / Bar chart ──────────────────────────────────────────────────────────

class _SeriesChart extends StatelessWidget {
  final _Vis vis;
  final List<Map<String, dynamic>> data;
  const _SeriesChart({required this.vis, required this.data});

  // Shorten axis date labels so fl_chart never needs to skip them
  static String _fmtAxisLabel(dynamic raw) {
    final s = raw?.toString() ?? '';
    // YYYY-MM-DD → MM/DD
    if (s.length == 10 && s[4] == '-' && s[7] == '-') {
      return '${s.substring(5, 7)}/${s.substring(8)}';
    }
    // YYYY-MM → MonYY
    if (s.length == 7 && s[4] == '-') {
      const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final idx = int.tryParse(s.substring(5)) ?? 0;
      return "${m[idx]}'${s.substring(2, 4)}";
    }
    return s; // hour integers pass through unchanged
  }

  @override
  Widget build(BuildContext context) {
    final maxV = data.fold<double>(0, (a, e) {
      final v = (e['value'] as num?)?.toDouble() ?? 0;
      return v > a ? v : a;
    });
    final ticks = niceAxisTicks(maxV);
    final maxY = ticks.maxY;
    final useK = maxV >= 1000;

    final bottomInterval =
        (data.length / 6).ceilToDouble().clamp(1.0, double.infinity);

    final titles = FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 52,
          interval: ticks.step,
          getTitlesWidget: (v, _) {
            // Consistent format: always k if max >= 1000, always int otherwise
            final label = useK
                ? '${(v / 1000).toStringAsFixed(1)}k'
                : v.toStringAsFixed(0);
            return Text(label,
                style: const TextStyle(fontSize: 9, color: Colors.grey));
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: bottomInterval,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= data.length) return const SizedBox.shrink();
            final lbl = _fmtAxisLabel(data[i]['label']);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(lbl,
                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
            );
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );

    final gridData = FlGridData(
      drawVerticalLine: false,
      horizontalInterval: ticks.step,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: Colors.grey.withValues(alpha: 0.12), strokeWidth: 1),
    );
    final borderData = FlBorderData(show: false);

    if (vis == _Vis.bar) {
      return BarChart(BarChartData(
        maxY: maxY,
        titlesData: titles,
        gridData: gridData,
        borderData: borderData,
        barGroups: data.asMap().entries.map((e) {
          final v = (e.value['value'] as num?)?.toDouble() ?? 0;
          return BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY: v,
              color: const Color(0xFF7C7CED),
              width: (320 / data.length).clamp(6.0, 24.0),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ]);
        }).toList(),
      ));
    }

    final spots = data.asMap().entries.map((e) {
      final v = (e.value['value'] as num?)?.toDouble() ?? 0;
      return FlSpot(e.key.toDouble(), v);
    }).toList();

    return LineChart(LineChartData(
      minY: 0,
      maxY: maxY,
      // Spline smoothing can overshoot past 0 on a sharp spike-then-drop;
      // clip to bounds and cap curve overshoot so this non-negative metric
      // never visually dips below the axis (human lead, 2026-09-22).
      clipData: const FlClipData.all(),
      titlesData: titles,
      gridData: gridData,
      borderData: borderData,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.15,
          preventCurveOverShooting: true,
          color: const Color(0xFF7C7CED),
          barWidth: 2,
          dotData: FlDotData(show: data.length <= 12),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF7C7CED).withValues(alpha: 0.08),
          ),
        ),
      ],
    ));
  }
}
