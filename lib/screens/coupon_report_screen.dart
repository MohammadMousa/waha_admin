import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/number_format.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';

/// Sales of paid orders that used a coupon, backed by /api/admin/coupons/report.
/// Rows are orders, employees or coupons; the summary cards cover the whole
/// filter, not just the page.
class CouponReportScreen extends StatefulWidget {
  const CouponReportScreen({super.key});

  @override
  State<CouponReportScreen> createState() => _CouponReportScreenState();
}

const _groups = <String, String>{
  'orders': 'Orders',
  'employee': 'Employees',
  'coupon': 'Coupons',
};

class _CouponReportScreenState extends State<CouponReportScreen> {
  static const _pageSize = 20;
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  String _groupBy = 'orders';
  String? _sort;
  bool _asc = false;
  int _page = 0;
  int? _storeId;
  int? _employeeId;
  int? _couponId;
  DateTimeRange? _range;
  List<Store> _stores = [];
  List<Employee> _employees = [];
  List<Map<String, dynamic>> _coupons = [];
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _summary = {};
  int _total = 0;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  final _userCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // This month by default, like the reference report.
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFilters();
      _load();
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    super.dispose();
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  /// Dropdown sources; a failure only leaves that filter empty.
  Future<void> _loadFilters() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final stores = await ApiClient().getAdminStores(token);
      if (mounted) setState(() => _stores = stores);
    } catch (_) {}
    try {
      final emps = await ApiClient().getEmployees(token);
      if (mounted) setState(() => _employees = emps);
    } catch (_) {}
    try {
      final data = await ApiClient().getCoupons(token, size: 200);
      if (mounted) setState(() => _coupons = (data['items'] as List? ?? []).cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  Map<String, String?> _filters({bool paged = true}) => {
        'groupBy': _groupBy,
        'from': _range == null ? null : _dateFmt.format(_range!.start),
        'to': _range == null ? null : _dateFmt.format(_range!.end),
        'storeId': _storeId?.toString(),
        'employeeId': _employeeId?.toString(),
        'couponId': _couponId?.toString(),
        'username': _groupBy == 'orders' ? _userCtrl.text.trim() : null,
        'sort': _sort,
        'dir': _sort == null ? null : (_asc ? 'asc' : 'desc'),
        if (paged) 'page': '$_page',
        if (paged) 'size': '$_pageSize',
      };

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final data = await ApiClient().getCouponReport(token, _filters());
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) { _redirectLogin(); return; }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Could not load the report: $e'; _loading = false; });
    }
  }

  void _reload({bool resetPage = true}) {
    if (resetPage) _page = 0;
    _load();
  }

  Future<void> _export(String format) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ApiClient().exportCouponReport(
          token, {..._filters(paged: false), 'format': format});
      final mime = format == 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/csv;charset=utf-8';
      final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));
      html.AnchorElement(href: url)
        ..setAttribute('download', 'coupon-sales-$_groupBy.$format')
        ..click();
      html.Url.revokeObjectUrl(url);
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) showErrorDialog(context, e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _sortBy(String key) {
    setState(() {
      if (_sort == key) {
        _asc = !_asc;
      } else {
        _sort = key;
        _asc = false;
      }
    });
    _reload();
  }

  Future<void> _pickRange() async {
    final r = await showWahaDateRangePicker(context, initial: _range);
    if (r != null) {
      setState(() => _range = r);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.couponReport),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Coupon Sales',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 24),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          for (final e in _groups.entries)
                            ButtonSegment(value: e.key, label: Text(e.value)),
                        ],
                        selected: {_groupBy},
                        onSelectionChanged: (v) {
                          setState(() { _groupBy = v.first; _sort = null; });
                          _reload();
                        },
                      ),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        enabled: !_exporting,
                        onSelected: _export,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'csv', child: Text('Export as CSV')),
                          PopupMenuItem(value: 'xlsx', child: Text('Export as Excel (XLSX)')),
                        ],
                        child: IgnorePointer(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.file_download_outlined, size: 18),
                            label: const Text('Export'),
                            onPressed: _exporting ? null : () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _cards(scheme),
                _filterBar(scheme),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _table(scheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cards(ColorScheme scheme) {
    Widget card(String label, String value, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        children: [
          card('Number of orders', fmtCount(_summary['orders']), Icons.grid_view_outlined),
          const SizedBox(width: 12),
          card('Sub-total', fmtMoney(_summary['subTotal']), Icons.attach_money),
          const SizedBox(width: 12),
          card('VAT', fmtMoney(_summary['vat']), Icons.percent),
          const SizedBox(width: 12),
          card('Total', fmtMoney(_summary['total']), Icons.payments_outlined),
          const SizedBox(width: 12),
          card('Coupon discount', fmtMoney(_summary['discount']), Icons.sell_outlined),
        ],
      ),
    );
  }

  Widget _filterBar(ColorScheme scheme) {
    Widget pick<T>(String hint, T value, List<DropdownMenuItem<T>> items, void Function(T) set) =>
        WahaFilterDropdown<T>(
          value: value,
          hint: hint,
          items: items,
          onChanged: (v) {
            setState(() => set(v as T));
            _reload();
          },
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          WahaFilterDateRange(
            range: _range,
            onTap: _pickRange,
            onClear: () { setState(() => _range = null); _reload(); },
          ),
          pick<int?>('Select Branch', _storeId, [
            const DropdownMenuItem(value: null, child: Text('Select Branch')),
            for (final s in _stores) DropdownMenuItem(value: s.id, child: Text(s.label())),
          ], (v) => _storeId = v),
          pick<int?>('Select Coupon', _couponId, [
            const DropdownMenuItem(value: null, child: Text('Select Coupon')),
            for (final c in _coupons)
              DropdownMenuItem(value: (c['id'] as num).toInt(), child: Text(c['code']?.toString() ?? '')),
          ], (v) => _couponId = v),
          pick<int?>('Select Employee', _employeeId, [
            const DropdownMenuItem(value: null, child: Text('Select Employee')),
            for (final e in _employees) DropdownMenuItem(value: e.id, child: Text(e.displayName)),
          ], (v) => _employeeId = v),
          if (_groupBy == 'orders')
            WahaSearchField(
              controller: _userCtrl,
              hintText: 'Search kiosk username',
              width: 200,
              onSubmitted: _reload,
              onClear: _reload,
            ),
        ],
      ),
    );
  }

  /// Column definitions per grouping: header, sort key, cell text, numeric.
  List<_Col> get _cols {
    String time(dynamic v) {
      final d = DateTime.tryParse(v?.toString() ?? '');
      return d == null ? '—' : _dtFmt.format(d.toLocal());
    }

    String employee(Map<String, dynamic> r) =>
        r['employeeName']?.toString() ?? (r['employeeId'] == null ? 'No employee' : '—');

    final money = <_Col>[
      _Col('Sub total', 'subTotal', (r) => fmtMoney(r['subTotal']), numeric: true),
      _Col('VAT', 'vat', (r) => fmtMoney(r['vat']), numeric: true),
      _Col('Total', 'total', (r) => fmtMoney(r['total']), numeric: true),
      _Col('Discount', 'discount', (r) => fmtMoney(r['discount']), numeric: true),
    ];
    switch (_groupBy) {
      case 'employee':
        return [
          _Col('Employee', 'employeeName', employee),
          _Col('Orders', 'orders', (r) => fmtCount(r['orders']), numeric: true),
          ...money,
        ];
      case 'coupon':
        return [
          _Col('Coupon code', 'code', (r) => r['code']?.toString() ?? '—'),
          _Col('Name', null, (r) => r['name']?.toString() ?? '—'),
          _Col('Employee', 'employeeName', employee),
          _Col('Orders', 'orders', (r) => fmtCount(r['orders']), numeric: true),
          ...money,
        ];
      default:
        return [
          _Col('#ID', 'displayId', (r) => '#${r['displayId'] ?? r['orderId']}'),
          _Col('Branch', null, (r) => r['storeName']?.toString() ?? '—'),
          _Col('Kiosk', 'username', (r) => r['username']?.toString() ?? '—'),
          _Col('Date order', 'paidAt', (r) => time(r['paidAt'] ?? r['createdAt'])),
          _Col('Coupon code', 'code', (r) => r['code']?.toString() ?? '—'),
          _Col('Employee', 'employeeName', employee),
          ...money,
        ];
    }
  }

  Widget _table(ColorScheme scheme) {
    const head = TextStyle(fontWeight: FontWeight.w600);
    final cols = _cols;
    final sortKey = _sort ?? (_groupBy == 'orders' ? 'paidAt' : 'total');
    final asc = _sort == null ? false : _asc;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _items.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No coupon sales for these filters.')))
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: SingleChildScrollView(
                          child: DataTable(
                                                                                    columnSpacing: 20,
                            horizontalMargin: 20,
                            headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                            columns: [
                              for (final c in cols)
                                DataColumn(
                                  label: c.sortKey == null
                                      ? Text(c.label, style: head)
                                      : wahaSortableLabel(context, c.label,
                                          active: c.sortKey == sortKey, asc: asc),
                                  numeric: c.numeric,
                                  onSort: c.sortKey == null ? null : (_, __) => _sortBy(c.sortKey!),
                                ),
                            ],
                            rows: [
                              for (final r in _items)
                                DataRow(cells: [for (final c in cols) DataCell(Text(c.cell(r)))]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text('${fmtCount(_total)} rows',
                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                      const Spacer(),
                      WahaPaginationBar(
                        page: _page,
                        totalCount: _total,
                        pageSize: _pageSize,
                        onPage: (p) { setState(() => _page = p); _reload(resetPage: false); },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Col {
  final String label;
  final String? sortKey;
  final String Function(Map<String, dynamic>) cell;
  final bool numeric;
  const _Col(this.label, this.sortKey, this.cell, {this.numeric = false});
}
