import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/localized_name.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/product_search_field.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';
import '../utils/number_format.dart';

class InventoryStockScreen extends StatefulWidget {
  const InventoryStockScreen({super.key});

  @override
  State<InventoryStockScreen> createState() => _InventoryStockScreenState();
}

class _InventoryStockScreenState extends State<InventoryStockScreen> {
  // Filters
  String _scope = 'BRANCHES'; // or 'COMPANY'
  int? _branchId;
  int? _productId;
  int? _categoryId;

  // Sort
  int _sortCol = 0;
  bool _sortAsc = true;

  // Lookups
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _categories = [];
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final results = await Future.wait([
        ApiClient().getReportStores(token),
        ApiClient().getReportCategories(token),
        ApiClient().getAdminStores(token),
      ]);
      if (!mounted) return;
      setState(() {
        _branches = (results[0] as List).cast<Map<String, dynamic>>();
        _categories = (results[1] as List).cast<Map<String, dynamic>>();
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
      final data = await ApiClient().getInventoryStock(
        token,
        scope: _scope,
        branchId: _scope == 'BRANCHES' ? _branchId : null,
        productId: _productId,
        categoryId: _categoryId,
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

  String _categoryLabel(Map<String, dynamic> c) => c['name_en']?.toString() ?? '—';

  String _rowBranchName(Map<String, dynamic> row) =>
      parseLocalizedName(row['branch_display_name'], fallback: row['branch_name']?.toString() ?? '—');

  String _rowProductName(Map<String, dynamic> row) =>
      parseLocalizedName(row['product_name'], fallback: '—');

  void _setScope(String scope) {
    setState(() {
      _scope = scope;
      _page = 0;
      _sortCol = 0;
      _sortAsc = true;
    });
    _load();
  }

  List<String> get _sortKeys => _scope == 'BRANCHES'
      ? const ['branch_name', 'product_name', 'quantity']
      : const ['product_name', 'total_quantity'];

  void _applySortToList(List<Map<String, dynamic>> list) {
    final keys = _sortKeys;
    final key = _sortCol < keys.length ? keys[_sortCol] : keys.first;
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
      final data = await ApiClient().getInventoryStock(
        token,
        scope: _scope,
        branchId: _scope == 'BRANCHES' ? _branchId : null,
        productId: _productId,
        categoryId: _categoryId,
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
      final lines = _scope == 'BRANCHES'
          ? [
              'Branch,Product,Quantity',
              ...rows.map((r) => [
                    '"${_rowBranchName(r)}"',
                    '"${_rowProductName(r)}"',
                    r['quantity'] ?? 0,
                  ].join(',')),
            ]
          : [
              'Product,Total Quantity',
              ...rows.map((r) => [
                    '"${_rowProductName(r)}"',
                    r['total_quantity'] ?? 0,
                  ].join(',')),
            ];
      _downloadCsv('inventory_stock_${_scope.toLowerCase()}.csv', lines.join('\n'));
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
          const AdminSidebar(currentRoute: Routes.inventoryStock),
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
            Text('Inventory Stock',
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
          SizedBox(
            height: kWahaFilterControlHeight,
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, kWahaFilterControlHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: 'BRANCHES', label: Text('Branches'), icon: Icon(Icons.store_outlined, size: 16)),
                ButtonSegment(value: 'COMPANY', label: Text('Company'), icon: Icon(Icons.apartment_outlined, size: 16)),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => _setScope(s.first),
              showSelectedIcon: false,
            ),
          ),
          IgnorePointer(
            ignoring: _scope == 'COMPANY',
            child: Opacity(
              opacity: _scope == 'COMPANY' ? 0.5 : 1,
              child: WahaFilterDropdown<int?>(
                value: _scope == 'BRANCHES' ? _branchId : null,
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
            ),
          ),
          WahaFilterDropdown<int?>(
            value: _categoryId,
            hint: 'Select Category',
            items: [
              const DropdownMenuItem(value: null, child: Text('Select Category')),
              ..._categories.map((c) => DropdownMenuItem(
                    value: (c['id'] as num).toInt(),
                    child: Text(_categoryLabel(c)),
                  )),
            ],
            onChanged: (v) { setState(() { _categoryId = v; _page = 0; }); _load(); },
          ),
          ProductSearchField(
            hintText: 'Search product…',
            onSearch: (query) async {
              final token = context.read<AuthState>().token;
              if (token == null) return [];
              return ApiClient().getAdminProducts(token, search: query, categoryId: _categoryId);
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
    final cols = _scope == 'BRANCHES'
        ? const ['Branch', 'Product', 'Quantity']
        : const ['Product', 'Total Quantity'];

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
                      columns: List.generate(cols.length, (i) => _dataColumn(scheme, cols[i], i, center: i == cols.length - 1)),
                      rows: _items.map((row) {
                        if (_scope == 'BRANCHES') {
                          return DataRow(cells: [
                            DataCell(SizedBox(width: 140, child: Text(_rowBranchName(row), overflow: TextOverflow.ellipsis))),
                            DataCell(SizedBox(width: 180, child: Text(_rowProductName(row), overflow: TextOverflow.ellipsis))),
                            DataCell(Center(child: Text(fmtCount(row['quantity'])))),
                          ]);
                        }
                        return DataRow(cells: [
                          DataCell(SizedBox(width: 220, child: Text(_rowProductName(row), overflow: TextOverflow.ellipsis))),
                          DataCell(Center(child: Text(fmtCount(row['total_quantity'])))),
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
                  _totalCount == 0 ? 'No entries' : 'Showing ${fmtCount(from)}–${fmtCount(to)} of ${fmtCount(_totalCount)} entries',
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
