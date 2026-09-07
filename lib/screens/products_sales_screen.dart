import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';

class ProductsSalesScreen extends StatefulWidget {
  const ProductsSalesScreen({super.key});

  @override
  State<ProductsSalesScreen> createState() => _ProductsSalesScreenState();
}

class _ProductsSalesScreenState extends State<ProductsSalesScreen> {
  // Filters
  int? _storeId;
  int? _categoryId;
  DateTimeRange? _dateRange;

  // Sort
  int  _sortColIndex = 0;
  bool _sortAsc      = true;

  // Lookups
  List<Map<String, dynamic>> _stores     = [];
  List<Map<String, dynamic>> _categories = [];

  // Data
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _items = [];
  int _totalCount = 0;
  int _page       = 0;
  static const _pageSize = 10;

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dispFmt = DateFormat('MMM d, yyyy');
  static final _numFmt  = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: now.subtract(const Duration(days: 7)),
      end: now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    final api = ApiClient();
    try {
      final results = await Future.wait([
        api.getReportStores(token),
        api.getReportCategories(token),
      ]);
      if (!mounted) return;
      setState(() {
        _stores     = (results[0] as List).cast<Map<String, dynamic>>();
        _categories = (results[1] as List).cast<Map<String, dynamic>>();
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
      final data = await ApiClient().getProductsSales(
        token,
        storeId:    _storeId,
        categoryId: _categoryId,
        from:       _dateRange != null ? _dateFmt.format(_dateRange!.start) : null,
        to:         _dateRange != null ? _dateFmt.format(_dateRange!.end)   : null,
        page:       _page,
        size:       _pageSize,
      );
      if (!mounted) return;
      final newItems = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      _applySortToList(newItems);
      setState(() {
        _summary    = data['summary'] as Map<String, dynamic>?;
        _items      = newItems;
        _totalCount = (data['totalCount'] as num?)?.toInt() ?? 0;
        _loading    = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  String _branchLabel(Map<String, dynamic> s) {
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

  String _parseBranchName(Map<String, dynamic> row) {
    final raw = row['branch_display_name'];
    if (raw != null) {
      try {
        final m = (raw is Map)
            ? Map<String, dynamic>.from(raw)
            : Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
        final name = (m['en'] ?? m['ar'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      } catch (_) {}
    }
    return row['branch_name']?.toString() ?? '—';
  }

  Future<void> _pickDateRange() async {
    final result = await showWahaDateRangePicker(context, initial: _dateRange);
    if (result != null) {
      setState(() { _dateRange = result; _page = 0; });
      _load();
    }
  }

  Future<void> _exportCsv() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _exporting = true);
    try {
      final params = <String, String>{
        if (_storeId    != null) 'storeId':    '$_storeId',
        if (_categoryId != null) 'categoryId': '$_categoryId',
        if (_dateRange  != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange  != null) 'to':   _dateFmt.format(_dateRange!.end),
        'size': '10000',
        'page': '0',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/products-sales')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final rows = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        final lines = <String>[
          '#ID,Product,SKU,Barcode,Category,Branch,Qty Sold,Unit Price,Total',
          ...rows.map((r) => [
            r['product_id'],
            '"${_displayName(r['product_name'])}"',
            r['sku'] ?? '',
            r['barcode'] ?? '',
            '"${r['category_name'] ?? ''}"',
            '"${_parseBranchName(r)}"',
            r['qty_sold'] ?? 0,
            r['unit_price'] ?? 0,
            r['total'] ?? 0,
          ].join(',')),
        ];
        _downloadCsv('products_sales.csv', lines.join('\n'));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _downloadCsv(String filename, String content) {
    final bytes = utf8.encode(content);
    final blob  = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url   = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _exportPdf() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _exporting = true);
    try {
      final params = <String, String>{
        if (_storeId    != null) 'storeId':    '$_storeId',
        if (_categoryId != null) 'categoryId': '$_categoryId',
        if (_dateRange  != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange  != null) 'to':   _dateFmt.format(_dateRange!.end),
        'size': '10000', 'page': '0',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/products-sales')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode != 200 || !mounted) return;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rows = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      final headers = ['#ID', 'Product', 'SKU', 'Barcode', 'Category', 'Branch', 'Qty', 'Unit Price', 'Total'];
      final rowsHtml = rows.map((r) => '<tr>'
          '<td>${r['product_id'] ?? ''}</td>'
          '<td>${_displayName(r['product_name'])}</td>'
          '<td>${r['sku'] ?? '—'}</td>'
          '<td>${r['barcode'] ?? ''}</td>'
          '<td>${_displayName(r['category_name'])}</td>'
          '<td>${_parseBranchName(r)}</td>'
          '<td>${r['qty_sold'] ?? 0}</td>'
          '<td>${_fmtNum(r['unit_price'])}</td>'
          '<td>${_fmtNum(r['total'])}</td>'
          '</tr>').join();
      final htmlContent = '''<!DOCTYPE html><html><head><title>Products Sales</title>
<style>body{font-family:sans-serif;font-size:11px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ccc;padding:4px 8px}th{background:#f0f0f0}</style></head>
<body><h3>Products Sales Report</h3><table><thead><tr>${headers.map((h) => '<th>$h</th>').join()}</tr></thead>
<tbody>$rowsHtml</tbody></table><script>window.print();</script></body></html>''';
      final blob = html.Blob([utf8.encode(htmlContent)], 'text/html;charset=utf-8');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(blobUrl, '_blank');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static const _sortKeys = [
    'product_id', 'product_name', 'sku', 'barcode',
    'category_name', 'branch_name', 'qty_sold', 'unit_price', 'total',
  ];

  void _applySortToList(List<Map<String, dynamic>> list) {
    final key = _sortColIndex < _sortKeys.length ? _sortKeys[_sortColIndex] : 'product_id';
    list.sort((a, b) {
      final va = a[key], vb = b[key];
      if (va is num && vb is num) return _sortAsc ? va.compareTo(vb) : vb.compareTo(va);
      return _sortAsc
          ? '${va ?? ''}'.compareTo('${vb ?? ''}')
          : '${vb ?? ''}'.compareTo('${va ?? ''}');
    });
  }

  void _sort(int colIndex, bool asc) {
    setState(() {
      if (_sortColIndex == colIndex) {
        _sortAsc = !_sortAsc;
      } else {
        _sortColIndex = colIndex;
        _sortAsc = true;
      }
      _applySortToList(_items);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.productsSales),
          Expanded(
            child: _loading && _summary == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _summary == null
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
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(scheme),
                          _buildFilters(scheme),
                          _buildSummaryPanel(scheme),
                          Expanded(child: _buildTableArea(scheme)),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(ColorScheme scheme) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(
          children: [
            Text('Products Sales',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            FilledButton.icon(
              icon: _exporting
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export CSV'),
              onPressed: _exporting ? null : _exportCsv,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Export PDF'),
              onPressed: _exporting ? null : _exportPdf,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: _load,
            ),
          ],
        ),
      );

  // ── Filters ───────────────────────────────────────────────────────────────

  Widget _buildFilters(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          WahaFilterDropdown<int?>(
            hint: 'Select Branch',
            value: _storeId,
            items: [
              const DropdownMenuItem(value: null, child: Text('Select Branch')),
              ..._stores.map((s) => DropdownMenuItem(
                    value: (s['id'] as num).toInt(),
                    child: Text(_branchLabel(s)),
                  )),
            ],
            onChanged: (v) { setState(() { _storeId = v; _page = 0; }); _load(); },
          ),
          const SizedBox(width: 10),
          WahaFilterDropdown<int?>(
            hint: 'Select Category',
            value: _categoryId,
            items: [
              const DropdownMenuItem(value: null, child: Text('Select Category')),
              ..._categories.map((c) => DropdownMenuItem(
                    value: (c['id'] as num).toInt(),
                    child: Text(_displayName(c['name_en'])),
                  )),
            ],
            onChanged: (v) { setState(() { _categoryId = v; _page = 0; }); _load(); },
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
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
        ],
      ),
    );
  }

  // ── Summary panel ─────────────────────────────────────────────────────────

  Widget _buildSummaryPanel(ColorScheme scheme) {
    final s = _summary ?? {};
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: scheme.outline)),
          const SizedBox(width: 24),
          _SummaryTile(Icons.inventory_2_outlined,  '${s['total_products'] ?? 0}',  'Number of products'),
          _SummaryTile(Icons.storefront_outlined,   '${s['total_branches'] ?? 0}',  'Number of branches'),
          _SummaryTile(Icons.shopping_cart_outlined, '${s['total_qty_sold'] ?? 0}', 'Total Qty sold'),
          _SummaryTile(Icons.attach_money_outlined,  _fmtNum(s['total_sales']),     'Total Sales'),
        ],
      ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _buildTableArea(ColorScheme scheme) {
    final from = _page * _pageSize + 1;
    final to   = ((_page + 1) * _pageSize).clamp(0, _totalCount);

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
              builder: (_, box) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 20,
                      horizontalMargin: 20,
                      headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 48,
                      columns: _buildColumns(scheme),
                      rows: _items.map((row) => DataRow(cells: [
                        DataCell(Text('${row['product_id'] ?? ''}')),
                        DataCell(SizedBox(width: 180, child: Text(_displayName(row['product_name']), overflow: TextOverflow.ellipsis))),
                        DataCell(Text('${row['sku'] ?? '—'}')),
                        DataCell(Text('${row['barcode'] ?? ''}')),
                        DataCell(SizedBox(width: 140, child: Text(_displayName(row['category_name']), overflow: TextOverflow.ellipsis))),
                        DataCell(SizedBox(width: 160, child: Text(_parseBranchName(row), overflow: TextOverflow.ellipsis))),
                        DataCell(Text('${row['qty_sold'] ?? 0}', textAlign: TextAlign.right)),
                        DataCell(Text(_fmtNum(row['unit_price']), textAlign: TextAlign.right)),
                        DataCell(Text(_fmtNum(row['total']),      textAlign: TextAlign.right)),
                      ])).toList(),
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
                  _totalCount == 0
                      ? 'No entries'
                      : 'Showing $from–$to of $_totalCount entries',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                _PaginationBar(
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

  List<DataColumn> _buildColumns(ColorScheme scheme) {
    final cols = ['#ID', 'Product', 'SKU', 'Barcode', 'Category', 'Branch', 'Qty Sold', 'Unit Price', 'Total'];
    return List.generate(cols.length, (i) {
      final isActive = _sortColIndex == i;
      return DataColumn(
        numeric: i >= 6,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(cols[i], style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 3),
            Icon(
              isActive ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
              size: 13,
              color: isActive ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
            ),
          ],
        ),
        onSort: (col, asc) => _sort(col, asc),
      );
    });
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  String _displayName(dynamic raw) {
    if (raw == null) return '—';
    final s = raw.toString().trim();
    if (s.startsWith('{') || s.startsWith('[')) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return (m['en'] ?? m['ar'] ?? m.values.first ?? '—').toString();
      } catch (_) {}
    }
    return s.isEmpty ? '—' : s;
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '0.00';
    return _numFmt.format((v as num).toDouble());
  }
}

// ── Summary tile ──────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _SummaryTile(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 28, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pagination bar ────────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int page;
  final int totalCount;
  final int pageSize;
  final ValueChanged<int> onPage;

  const _PaginationBar({
    required this.page,
    required this.totalCount,
    required this.pageSize,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    final total = (totalCount / pageSize).ceil();
    if (total <= 1) return const SizedBox.shrink();

    // Show « prev pages... current ...pages next »
    final first = (page - 2).clamp(0, (total - 5).clamp(0, total - 1));
    final last  = (first + 5).clamp(0, total);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // « first
        if (page > 0) ...[
          _PageBtn(label: '«', onTap: () => onPage(0)),
          _PageBtn(label: '‹', onTap: () => onPage(page - 1)),
        ],
        if (first > 0)
          _PageBtn(label: '…', onTap: null),
        // numbered
        for (int i = first; i < last; i++)
          _PageBtn(
            label: '${i + 1}',
            selected: i == page,
            onTap: i == page ? null : () => onPage(i),
          ),
        if (last < total)
          _PageBtn(label: '…', onTap: null),
        // » last
        if (page < total - 1) ...[
          _PageBtn(label: '›', onTap: () => onPage(page + 1)),
          _PageBtn(label: '»', onTap: () => onPage(total - 1)),
        ],
      ],
    );
  }
}

class _PageBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _PageBtn({required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        constraints: const BoxConstraints(minWidth: 30),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected ? null : Border.all(color: scheme.outlineVariant),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? scheme.onPrimary : scheme.onSurface)),
      ),
    );
  }
}
