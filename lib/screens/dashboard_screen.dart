import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/kpi_card.dart';
import '../widgets/revenue_chart.dart';
import '../widgets/orders_chart.dart';
import '../widgets/monthly_bar_chart.dart';
import '../widgets/recent_orders_table.dart';
import '../widgets/waha_filter_controls.dart';

String branchLabel(Map<String, dynamic> s) {
  final raw = s['display_name'];
  if (raw != null) {
    try {
      final m = (raw is Map)
          ? Map<String, dynamic>.from(raw)
          : Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
      final name = (m['en'] ?? m['ar'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
  }
  return s['name']?.toString() ?? '';
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _kpis;
  List<Map<String, dynamic>> _revenueSeries = [];
  List<Map<String, dynamic>> _ordersSeries = [];
  List<Map<String, dynamic>> _monthlyRevenue = [];
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _stores = [];
  int? _storeId;

  bool _loading = true;
  String? _error;

  String _revenuePeriod = '1m';
  String _ordersPeriod = '1m';
  String _monthlyPeriod = '6m';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _logout(); return; }
    final api = ApiClient();
    try {
      final results = await Future.wait([
        api.getDashboardKpis(token, storeId: _storeId),
        api.getDashboardSeries(token, 'revenue', _revenuePeriod, storeId: _storeId),
        api.getDashboardSeries(token, 'orders', _ordersPeriod, storeId: _storeId),
        api.getDashboardMonthly(token, _monthlyPeriod, storeId: _storeId),
        api.getRecentOrders(token, storeId: _storeId),
        if (_stores.isEmpty) api.getReportStores(token),
      ]);
      if (!mounted) return;
      // ignore: unnecessary_cast
      setState(() {
        _kpis = results[0] as Map<String, dynamic>;
        _revenueSeries = (results[1] as List).cast<Map<String, dynamic>>();
        _ordersSeries = (results[2] as List).cast<Map<String, dynamic>>();
        _monthlyRevenue = (results[3] as List).cast<Map<String, dynamic>>();
        _recentOrders = (results[4] as List).cast<Map<String, dynamic>>();
        if (results.length > 5) _stores = (results[5] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _logout(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _loadSeries() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final api = ApiClient();
    final results = await Future.wait([
      api.getDashboardSeries(token, 'revenue', _revenuePeriod, storeId: _storeId),
      api.getDashboardSeries(token, 'orders', _ordersPeriod, storeId: _storeId),
      api.getDashboardMonthly(token, _monthlyPeriod, storeId: _storeId),
    ]);
    if (!mounted) return;
    setState(() {
      _revenueSeries = (results[0] as List).cast<Map<String, dynamic>>();
      _ordersSeries = (results[1] as List).cast<Map<String, dynamic>>();
      _monthlyRevenue = (results[2] as List).cast<Map<String, dynamic>>();
    });
  }

  void _logout() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  void _onStoreChanged(int? storeId) {
    setState(() => _storeId = storeId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          // ── Sidebar ───────────────────────────────────────────────────────
          const AdminSidebar(currentRoute: Routes.dashboard),

          // ── Main content ──────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: TextStyle(color: scheme.error)),
                            const SizedBox(height: 16),
                            FilledButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Header(
                                onRefresh: _load,
                                stores: _stores,
                                selectedStoreId: _storeId,
                                onStoreChanged: _onStoreChanged,
                              ),
                              const SizedBox(height: 24),

                              // ── KPI cards ───────────────────────────────
                              _KpiRow(
                                kpis: _kpis ?? {},
                                revenueSeries: _revenueSeries,
                                ordersSeries:  _ordersSeries,
                              ),
                              const SizedBox(height: 24),

                              // ── Overview + Revenue line chart ────────────
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: _OverviewCard(kpis: _kpis ?? {}),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      flex: 3,
                                      child: _ChartCard(
                                        title: 'Revenue',
                                        periods: const ['7d', '15d', '1m', '3m'],
                                        selected: _revenuePeriod,
                                        onPeriod: (p) {
                                          setState(() => _revenuePeriod = p);
                                          _loadSeries();
                                        },
                                        child: RevenueChart(series: _revenueSeries),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // ── Revenue by months bar chart ──────────────
                              _ChartCard(
                                title: 'Revenue by months',
                                periods: const ['6m', '1y', '2y'],
                                selected: _monthlyPeriod,
                                onPeriod: (p) {
                                  setState(() => _monthlyPeriod = p);
                                  _loadSeries();
                                },
                                child: MonthlyBarChart(series: _monthlyRevenue),
                              ),
                              const SizedBox(height: 20),

                              // ── Orders chart + Recent orders ─────────────
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _ChartCard(
                                        title: 'Orders',
                                        periods: const ['7d', '15d', '1m', '3m'],
                                        selected: _ordersPeriod,
                                        onPeriod: (p) {
                                          setState(() => _ordersPeriod = p);
                                          _loadSeries();
                                        },
                                        child: OrdersChart(series: _ordersSeries),
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: RecentOrdersTable(
                                        orders: _recentOrders.take(5).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  final List<Map<String, dynamic>> stores;
  final int? selectedStoreId;
  final ValueChanged<int?> onStoreChanged;

  const _Header({
    required this.onRefresh,
    required this.stores,
    required this.selectedStoreId,
    required this.onStoreChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('Dashboard',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          WahaFilterDropdown<int?>(
            value: selectedStoreId,
            hint: 'Select Branch',
            items: [
              const DropdownMenuItem(value: null, child: Text('Select Branch')),
              ...stores.map((s) => DropdownMenuItem(
                    value: (s['id'] as num).toInt(),
                    child: Text(branchLabel(s)),
                  )),
            ],
            onChanged: onStoreChanged,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: onRefresh,
          ),
        ],
      );
}

// ── KPI row ───────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final Map<String, dynamic> kpis;
  final List<Map<String, dynamic>> revenueSeries;
  final List<Map<String, dynamic>> ordersSeries;

  const _KpiRow({
    required this.kpis,
    required this.revenueSeries,
    required this.ordersSeries,
  });

  List<double> _spark(List<Map<String, dynamic>> series) =>
      series.map((e) => (e['value'] as num?)?.toDouble() ?? 0.0).toList();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, box) {
          final narrow = box.maxWidth < 700;
          final revSpark = _spark(revenueSeries);
          final ordSpark = _spark(ordersSeries);

          final cards = [
            KpiCard(
              label: 'TODAY REVENUE',
              value: 'SAR ${_fmt(kpis['todayRevenue'])}',
              pctChange:  (kpis['todayRevenuePct']  as num?)?.toDouble(),
              sparkline:  revSpark,
            ),
            KpiCard(
              label: 'TOTAL REVENUE',
              value: 'SAR ${_fmt(kpis['totalRevenue'])}',
              icon: Icons.shopping_bag_outlined,
            ),
            KpiCard(
              label: 'TODAY ORDERS',
              value: '${kpis['todayOrders'] ?? 0}',
              pctChange: (kpis['todayOrdersPct'] as num?)?.toDouble(),
              sparkline: ordSpark,
            ),
            KpiCard(
              label: 'TOTAL ORDERS',
              value: '${kpis['totalOrders'] ?? 0}',
              icon: Icons.shopping_bag_outlined,
            ),
          ];
          if (narrow) {
            return Column(children: cards.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: c,
            )).toList());
          }
          return Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: c,
                      ),
                    ))
                .toList(),
          );
        },
      );

  String _fmt(dynamic v) {
    if (v == null) return '0.00';
    final d = (v as num).toDouble();
    return d.toStringAsFixed(2);
  }
}

// ── Overview card ─────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final Map<String, dynamic> kpis;
  const _OverviewCard({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Overview',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            _OverviewRow(
              icon: Icons.tablet_outlined,
              value: '${kpis['totalKiosks'] ?? 0}',
              label: 'Total installed Kiosks',
              scheme: scheme,
            ),
            const SizedBox(height: 20),
            _OverviewRow(
              icon: Icons.track_changes_outlined,
              value: _fmt(kpis['avgRevenuePerKiosk']),
              label: 'Average Revenue Per Kiosk',
              scheme: scheme,
            ),
            const SizedBox(height: 20),
            _OverviewRow(
              icon: Icons.track_changes_outlined,
              value: _fmtOrders(kpis['avgOrdersPerKiosk']),
              label: 'Avg Num of Orders / Kiosk',
              scheme: scheme,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '0.00';
    return (v as num).toDouble().toStringAsFixed(2);
  }

  String _fmtOrders(dynamic v) {
    if (v == null) return '0';
    final d = (v as num).toDouble();
    return d == d.roundToDouble() ? '${d.round()}' : d.toStringAsFixed(1);
  }
}

class _OverviewRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final ColorScheme scheme;
  const _OverviewRow(
      {required this.icon,
      required this.value,
      required this.label,
      required this.scheme});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(icon, color: scheme.outline, size: 24),
        ],
      );
}

// ── Chart card wrapper ────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final List<String> periods;
  final String selected;
  final ValueChanged<String> onPeriod;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.periods,
    required this.selected,
    required this.onPeriod,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                ...periods.map((p) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: () => onPeriod(p),
                        child: Text(
                          p,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: p == selected
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: p == selected
                                ? scheme.primary
                                : scheme.outline,
                          ),
                        ),
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: child),
          ],
        ),
      ),
    );
  }
}
