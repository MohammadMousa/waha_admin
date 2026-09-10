import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/localized_name.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/product_search_field.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';

/// Matches [ApiClient.getInventoryTransfers] / [ApiClient.getInventoryReturns]
/// exactly, so either can be passed in as [InventoryOperationsScreen.fetcher].
typedef InventoryOperationsFetcher = Future<Map<String, dynamic>> Function(
  String token, {
  int? branchId,
  int? productId,
  int? employeeId,
  String? from,
  String? to,
  int page,
  int size,
});

/// Transfers and Returns are "identical shape and filters" per
/// docs/inventory.md — one screen driven by which endpoint/route/title it's
/// given, instead of two near-duplicate files.
class InventoryOperationsScreen extends StatefulWidget {
  final String title;
  final String route;
  final String exportFilePrefix;
  final InventoryOperationsFetcher fetcher;

  const InventoryOperationsScreen({
    super.key,
    required this.title,
    required this.route,
    required this.exportFilePrefix,
    required this.fetcher,
  });

  @override
  State<InventoryOperationsScreen> createState() => _InventoryOperationsScreenState();
}

class _InventoryOperationsScreenState extends State<InventoryOperationsScreen> {
  // Filters
  int? _branchId;
  int? _productId;
  int? _employeeId;
  DateTimeRange? _dateRange;

  // Sort — index 1 is Date (default sort column), matching the header order
  // Visit ID | Date | Branch | Product | Quantity | Employee.
  int _sortCol = 1;
  bool _sortAsc = false;

  // Lookups
  List<Map<String, dynamic>> _branches = [];
  List<Employee> _employees = [];
  Map<int, Employee> _employeesById = {};
  // `getReportStores` (used for `_branches`, above) returns only `{id, name}`
  // — no display name — so branch labels are resolved through this map,
  // built from `getAdminStores` (the same endpoint the Stores admin screen
  // uses), keyed by store id.
  Map<int, Store> _storesById = {};

  // Data
  List<Map<String, dynamic>> _items = [];
  int _totalCount = 0;
  int _page = 0;
  static const _pageSize = 20;

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dispFmt = DateFormat('MMM d, yyyy');
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void didUpdateWidget(covariant InventoryOperationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) {
      // Navigating between the Transfers/Returns nav items reuses this
      // widget type — reset filters/paging and refetch for the new route.
      _branchId = null;
      _productId = null;
      _employeeId = null;
      _dateRange = null;
      _page = 0;
      _load();
    }
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final results = await Future.wait([
        ApiClient().getReportStores(token),
        ApiClient().getEmployees(token),
        ApiClient().getAdminStores(token),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = (results[0] as List).cast<Map<String, dynamic>>();
        _employees = (results[1] as List).cast<Employee>();
        _employeesById = {for (final e in _employees) e.id: e};
        _storesById = {for (final s in (results[2] as List<Store>)) s.id: s};
      });
      await _load();
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final data = await widget.fetcher(
        token,
        branchId: _branchId,
        productId: _productId,
        employeeId: _employeeId,
        from: _dateRange != null ? _dateFmt.format(_dateRange!.start) : null,
        to: _dateRange != null ? _dateFmt.format(_dateRange!.end) : null,
        page: _page,
        size: _pageSize,
      );
      if (!mounted) return;
      final newItems = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      _applySortToList(newItems);
      setState(() {
        _items = newItems;
        _totalCount = (data['totalCount'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  String _branchLabel(Map<String, dynamic> s) {
    final id = (s['id'] as num?)?.toInt();
    final displayName = _storesById[id]?.displayName;
    return displayName?['en'] ?? displayName?['ar'] ?? s['name']?.toString() ?? '';
  }

  String _employeeLabel(Employee e) {
    final full = [e.firstName, e.lastName].where((s) => s != null && s.isNotEmpty).join(' ');
    return full.isEmpty ? e.username : full;
  }

  String _rowBranchName(Map<String, dynamic> row) =>
      parseLocalizedName(row['branch_display_name'], fallback: row['branch_name']?.toString() ?? '—');

  String _rowProductName(Map<String, dynamic> row) =>
      parseLocalizedName(row['product_name'], fallback: '—');

  /// `employee_name` is blank/whitespace-only on some rows (backend
  /// first-name+last-name concat bug when both are unset) — fall back to
  /// username via the already-loaded employees lookup.
  String _rowEmployeeName(Map<String, dynamic> row) {
    final name = row['employee_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final id = (row['employee_id'] as num?)?.toInt();
    return _employeesById[id]?.username ?? '—';
  }

  Future<void> _pickDateRange() async {
    final result = await showWahaDateRangePicker(context, initial: _dateRange);
    if (result != null) {
      setState(() { _dateRange = result; _page = 0; });
      _load();
    }
  }

  // Matches the header order: Visit ID | Date | Branch | Product | Quantity | Employee.
  static const _sortKeys = [
    'visit_id', 'date', 'branch_name', 'product_name', 'quantity', 'employee_name',
  ];

  void _applySortToList(List<Map<String, dynamic>> list) {
    final key = _sortCol < _sortKeys.length ? _sortKeys[_sortCol] : 'date';
    list.sort((a, b) {
      final va = a[key], vb = b[key];
      if (va is num && vb is num) return _sortAsc ? va.compareTo(vb) : vb.compareTo(va);
      return _sortAsc
          ? '${va ?? ''}'.compareTo('${vb ?? ''}')
          : '${vb ?? ''}'.compareTo('${va ?? ''}');
    });
  }

  void _sort(int col, bool asc) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = true;
      }
      _applySortToList(_items);
    });
  }

  /// Pages through the API at its max page size to fetch every row matching
  /// the current filters — `size: 10000` (the old approach) is silently
  /// clamped by the backend down to the default of 20, which made exports
  /// incomplete.
  Future<List<Map<String, dynamic>>> _fetchAllForExport(String token) async {
    final all = <Map<String, dynamic>>[];
    var page = 0;
    while (true) {
      final data = await widget.fetcher(
        token,
        branchId: _branchId,
        productId: _productId,
        employeeId: _employeeId,
        from: _dateRange != null ? _dateFmt.format(_dateRange!.start) : null,
        to: _dateRange != null ? _dateFmt.format(_dateRange!.end) : null,
        page: page,
        size: kMaxApiPageSize,
      );
      final items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      all.addAll(items);
      final totalCount = (data['totalCount'] as num?)?.toInt() ?? all.length;
      if (all.length >= totalCount || items.isEmpty) break;
      page++;
    }
    return all;
  }

  Future<void> _exportCsv() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _exporting = true);
    try {
      final rows = await _fetchAllForExport(token);
      if (!mounted) return;
      final lines = [
        'Visit ID,Date,Branch,Product,Quantity,Employee',
        ...rows.map((r) => [
              r['visit_id'] ?? '',
              r['date'] ?? '',
              '"${_rowBranchName(r)}"',
              '"${_rowProductName(r)}"',
              r['quantity'] ?? 0,
              '"${_rowEmployeeName(r)}"',
            ].join(',')),
      ];
      _downloadCsv('${widget.exportFilePrefix}.csv', lines.join('\n'));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _downloadCsv(String filename, String content) {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          AdminSidebar(currentRoute: widget.route),
          Expanded(
            child: _loading && _items.isEmpty && _error == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _items.isEmpty
                    ? _buildError(scheme)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(scheme),
                          _buildFilters(scheme),
                          Expanded(child: _buildTableArea(scheme)),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme scheme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );

  Widget _buildHeader(ColorScheme scheme) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(
          children: [
            Text(widget.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            FilledButton.icon(
              icon: _exporting
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export CSV'),
              onPressed: _exporting ? null : _exportCsv,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.refresh_outlined), tooltip: 'Refresh', onPressed: _load),
          ],
        ),
      );

  Widget _buildFilters(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          WahaFilterDropdown<int?>(
            value: _branchId,
            hint: 'Select Branch',
            items: [
              const DropdownMenuItem(value: null, child: Text('Select Branch')),
              ..._branches.map((s) => DropdownMenuItem(
                    value: (s['id'] as num).toInt(),
                    child: Text(_branchLabel(s)),
                  )),
            ],
            onChanged: (v) { setState(() { _branchId = v; _page = 0; }); _load(); },
          ),
          WahaFilterDropdown<int?>(
            value: _employeeId,
            hint: 'Select Employee',
            items: [
              const DropdownMenuItem(value: null, child: Text('Select Employee')),
              ..._employees.map((e) => DropdownMenuItem(value: e.id, child: Text(_employeeLabel(e)))),
            ],
            onChanged: (v) { setState(() { _employeeId = v; _page = 0; }); _load(); },
          ),
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(border: Border.all(color: scheme.outline), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    _dateRange == null
                        ? 'Select date range'
                        : '${_dispFmt.format(_dateRange!.start)}  –  ${_dispFmt.format(_dateRange!.end)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          ProductSearchField(
            hintText: 'Search product…',
            onSearch: (query) async {
              final token = context.read<AuthState>().token;
              if (token == null) return [];
              return ApiClient().getAdminProducts(token, search: query);
            },
            labelBuilder: (p) => parseLocalizedName(p['name']),
            onSelected: (p) {
              setState(() { _productId = p == null ? null : (p['id'] as num).toInt(); _page = 0; });
              _load();
            },
          ),
        ],
      ),
    );
  }

  DataColumn _dataColumn(ColorScheme scheme, String label, int i, {bool center = false}) {
    final isActive = _sortCol == i;
    return DataColumn(
      // `columnWidth` gives this column a fixed width instead of the default
      // IntrinsicColumnWidth — needed because `headingRowAlignment: center`
      // only centers the header *within* the column's own width, and because
      // an unbounded width (Container(width: double.infinity), tried
      // earlier) breaks DataTable's intrinsic-width measurement and made the
      // header vanish entirely.
      columnWidth: center ? const FixedColumnWidth(110) : null,
      headingRowAlignment: center ? MainAxisAlignment.center : null,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 3),
          Icon(
            isActive ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
            size: 13,
            color: isActive ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
          ),
        ],
      ),
      onSort: (c, a) => _sort(c, a),
    );
  }

  Widget _buildTableArea(ColorScheme scheme) {
    final from = _page * _pageSize + 1;
    final to = ((_page + 1) * _pageSize).clamp(0, _totalCount);
    final cols = ['Visit ID', 'Date', 'Branch', 'Product', 'Quantity', 'Employee'];

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 18,
                      horizontalMargin: 20,
                      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 48,
                      columns: List.generate(cols.length, (i) => _dataColumn(scheme, cols[i], i, center: i == 4)),
                      rows: _items.map((row) {
                        final dt = row['date'] != null
                            ? _dtFmt.format(DateTime.parse(row['date'].toString()).toLocal())
                            : '—';
                        return DataRow(cells: [
                          DataCell(Text('${row['visit_id'] ?? '—'}')),
                          DataCell(Text(dt)),
                          DataCell(SizedBox(width: 140, child: Text(_rowBranchName(row), overflow: TextOverflow.ellipsis))),
                          DataCell(SizedBox(width: 160, child: Text(_rowProductName(row), overflow: TextOverflow.ellipsis))),
                          DataCell(Center(child: Text('${row['quantity'] ?? 0}'))),
                          DataCell(Text(_rowEmployeeName(row))),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  _totalCount == 0 ? 'No entries' : 'Showing $from–$to of $_totalCount entries',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                WahaPaginationBar(
                  page: _page,
                  totalCount: _totalCount,
                  pageSize: _pageSize,
                  onPage: (p) { setState(() => _page = p); _load(); },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
