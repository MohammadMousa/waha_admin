import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';
import '../utils/number_format.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  // Filters
  int?    _storeId;
  String? _status;
  String? _kiosk;
  String? _paymentType;
  bool?   _synced;
  String  _reference = '';
  final _refCtrl = TextEditingController();
  DateTimeRange? _dateRange;

  // Sort
  int  _sortCol = 0;
  Set<String> _hidden = {'sub', 'vat', 'synced'};
  static const _hiddenPrefKey = 'orders_hidden_columns';
  bool _sortAsc = false;

  // Lookups
  List<Map<String, dynamic>> _stores        = [];
  List<String>               _kiosks        = [];
  List<String>               _paymentMethods = [];
  // `getReportStores` (used for `_stores`, above) returns only `{id, name}`
  // — no display name — so branch labels are resolved through this map,
  // built from `getAdminStores` (the same endpoint the Stores admin screen
  // uses), keyed by store id.
  Map<int, Store> _storesById = {};

  // Data
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _items = [];
  int _totalCount = 0;
  int _page       = 0;
  int _pageSize   = 10;
  static const _pageSizeOptions = [10, 25, 50, 100, 250, 500];

  bool _loading   = true;
  bool _exporting = false;
  String? _error;

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dispFmt = DateFormat('MMM d, yyyy');
  static final _dtFmt   = DateFormat('yyyy-MM-dd HH:mm');
  static final _numFmt  = NumberFormat('#,##0.00');

  static const _statuses = [null, 'PAID', 'CREATED', 'PENDING', 'CANCELLED'];
  static const _statusLabels = {
    null: 'Select Status',
    'PAID': 'Paid',
    'CREATED': 'Created',
    'PENDING': 'Pending',
    'CANCELLED': 'Cancelled',
  };

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    _loadHiddenColumns();
  }

  Future<void> _loadHiddenColumns() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getStringList(_hiddenPrefKey);
      if (saved != null && mounted) setState(() => _hidden = saved.toSet());
    } catch (_) {}
  }

  Future<void> _saveHiddenColumns() async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_hiddenPrefKey, _hidden.toList());
    } catch (_) {}
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final results = await Future.wait([
        ApiClient().getReportStores(token),
        ApiClient().getReportKiosks(token),
        ApiClient().getReportPaymentMethods(token),
        ApiClient().getAdminStores(token),
      ]);
      if (!mounted) return;
      setState(() {
        _stores         = (results[0] as List).cast<Map<String, dynamic>>();
        _kiosks         = (results[1] as List).map((e) => e['username']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        _paymentMethods = (results[2] as List).map((e) => e['provider']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        _storesById     = {for (final s in (results[3] as List<Store>)) s.id: s};
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
      final params = <String, String>{
        if (_storeId      != null) 'storeId':     '$_storeId',
        if (_status       != null) 'status':       _status!,
        if (_kiosk        != null) 'kiosk':        _kiosk!,
        if (_paymentType  != null) 'paymentType':  _paymentType!,
        if (_synced       != null) 'synced':       '$_synced',
        if (_reference.isNotEmpty) 'reference': _reference,
        if (_dateRange    != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange    != null) 'to':   _dateFmt.format(_dateRange!.end),
        'page': '$_page',
        'size': '$_pageSize',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/orders')
          .replace(queryParameters: params);
      final resp = await http.get(uri,
          headers: ApiClient.authHeaders(token));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final newItems = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _applySortToList(newItems);
        setState(() {
          _summary    = data['summary'] as Map<String, dynamic>?;
          _items      = newItems;
          _totalCount = (data['totalCount'] as num?)?.toInt() ?? 0;
          _loading    = false;
        });
      } else {
        setState(() {
          _error   = 'Request failed (${resp.statusCode})';
          _loading = false;
        });
      }
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
        if (_storeId     != null) 'storeId':    '$_storeId',
        if (_status      != null) 'status':      _status!,
        if (_kiosk       != null) 'kiosk':       _kiosk!,
        if (_paymentType != null) 'paymentType': _paymentType!,
        if (_synced      != null) 'synced':      '$_synced',
        if (_reference.isNotEmpty) 'reference': _reference,
        if (_dateRange   != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange   != null) 'to':   _dateFmt.format(_dateRange!.end),
        'page': '0', 'size': '10000',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/orders')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: ApiClient.authHeaders(token));
      if (resp.statusCode == 200 && mounted) {
        final data  = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final rows  = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        final lines = [
          '#ID,DID,Branch,Kiosk,Payment Ref,Date,Sub-Total,VAT,Total,Currency,Payment Type,Status,Synced',
          ...rows.map((r) => [
            r['display_id'] == null ? '' : '${r['display_id']}',
            r['order_reference'] ?? '',
            '"${_parseBranchName(r)}"',
            '"${r['kiosk'] ?? ''}"',
            r['ref'] ?? '',
            _dtFmt.format(DateTime.parse(r['created_at'].toString())),
            r['subtotal_amount'] ?? 0,
            r['tax_amount'] ?? 0,
            r['total_amount'] ?? 0,
            r['currency'] ?? '',
            r['payment_type'] ?? '',
            r['status'] ?? '',
            r['synced'] == true ? 'true' : 'false',
          ].join(',')),
        ];
        _downloadCsv('orders.csv', lines.join('\n'));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _downloadCsv(String filename, String content) {
    final bytes  = utf8.encode(content);
    final blob   = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url    = html.Url.createObjectUrlFromBlob(blob);
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
        if (_storeId     != null) 'storeId':    '$_storeId',
        if (_status      != null) 'status':      _status!,
        if (_kiosk       != null) 'kiosk':       _kiosk!,
        if (_paymentType != null) 'paymentType': _paymentType!,
        if (_synced      != null) 'synced':      '$_synced',
        if (_reference.isNotEmpty) 'reference': _reference,
        if (_dateRange   != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange   != null) 'to':   _dateFmt.format(_dateRange!.end),
        'page': '0', 'size': '10000',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/orders')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: ApiClient.authHeaders(token));
      if (resp.statusCode != 200 || !mounted) return;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rows = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      final headers = ['#ID', 'DID', 'Branch', 'Kiosk', 'Payment Ref', 'Date', 'Sub-Total', 'VAT', 'Total', 'Payment', 'Status', 'Synced'];
      final rowsHtml = rows.map((r) {
        final dt = r['created_at'] != null
            ? _dtFmt.format(DateTime.parse(r['created_at'].toString()).toLocal()) : '—';
        return '<tr>'
            '<td>${r['display_id'] ?? ''}</td>'
            '<td>${r['order_reference'] ?? ''}</td>'
            '<td>${_parseBranchName(r)}</td>'
            '<td>${r['kiosk'] ?? ''}</td>'
            '<td>${r['ref'] ?? '—'}</td>'
            '<td>$dt</td>'
            '<td>${_fmtNum(r['subtotal_amount'])}</td>'
            '<td>${_fmtNum(r['tax_amount'])}</td>'
            '<td>${_fmtNum(r['total_amount'])}</td>'
            '<td>${r['payment_type'] ?? '—'}</td>'
            '<td>${r['status'] ?? ''}</td>'
            '<td>${r['synced'] == true ? 'Yes' : 'No'}</td>'
            '</tr>';
      }).join();
      final htmlContent = '''<!DOCTYPE html><html><head><title>Orders</title>
<style>body{font-family:sans-serif;font-size:11px}table{border-collapse:collapse;width:100%}
th,td{border:1px solid #ccc;padding:4px 8px}th{background:#f0f0f0}</style></head>
<body><h3>Orders Report</h3><table><thead><tr>${headers.map((h) => '<th>$h</th>').join()}</tr></thead>
<tbody>$rowsHtml</tbody></table><script>window.print();</script></body></html>''';
      final blob = html.Blob([utf8.encode(htmlContent)], 'text/html;charset=utf-8');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(blobUrl, '_blank');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Every grid column. `fixed` ones cannot be hidden; `key` is the row field
  /// used for sorting (null = not sortable).
  static const _allCols = <_OrderCol>[
    _OrderCol('id', '#ID', 'display_id', fixed: true),
    _OrderCol('did', 'DID', 'order_reference', fixed: true,
        tip: 'Device order reference, e.g. 5-01-0002 (store - device - serial)'),
    _OrderCol('branch', 'Branch', 'branch_name'),
    _OrderCol('kiosk', 'Kiosk', 'kiosk'),
    _OrderCol('payref', 'Payment Ref', 'ref'),
    _OrderCol('date', 'Date', 'created_at'),
    _OrderCol('sub', 'Sub-Total', 'subtotal_amount', numeric: true),
    _OrderCol('vat', 'VAT', 'tax_amount', numeric: true),
    _OrderCol('total', 'Total', 'total_amount', numeric: true, fixed: true),
    _OrderCol('paytype', 'Payment Type', 'payment_type'),
    _OrderCol('status', 'Status', 'status'),
    _OrderCol('synced', 'Synced', 'synced'),
    _OrderCol('invoice', 'Invoice', null),
    _OrderCol('products', 'Products', null),
  ];

  void _applySortToList(List<Map<String, dynamic>> list) {
    final key = _allCols[_sortCol].key ?? 'display_id';
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.orders),
          Expanded(
            child: _loading && _summary == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _summary == null
                    ? _buildError(scheme)
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
            Text('Orders',
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
              icon: const Icon(Icons.view_column_outlined),
              tooltip: 'Columns',
              onPressed: _chooseColumns,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: _load,
            ),
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
          WahaSearchField(
            controller: _refCtrl,
            hintText: 'Order reference',
            width: 180,
            onSubmitted: () { setState(() { _reference = _refCtrl.text.trim(); _page = 0; }); _load(); },
            onClear: () { setState(() { _reference = ''; _page = 0; }); _load(); },
          ),
          WahaFilterDropdown<int?>(
            value: _storeId,
            hint: 'Select Branch',
            items: [
              const DropdownMenuItem(value: null, child: Text('Select Branch')),
              ..._stores.map((s) => DropdownMenuItem(
                    value: (s['id'] as num).toInt(),
                    child: Text(_branchLabel(s)),
                  )),
            ],
            onChanged: (v) { setState(() { _storeId = v; _page = 0; }); _load(); },
          ),
          WahaFilterDropdown<String?>(
            value: _status,
            hint: 'Select Status',
            items: _statuses.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(_statusLabels[s] ?? s ?? 'Select Status'),
                )).toList(),
            onChanged: (v) { setState(() { _status = v; _page = 0; }); _load(); },
          ),
          if (_kiosks.isNotEmpty)
            WahaFilterDropdown<String?>(
              value: _kiosk,
              hint: 'Select Kiosk',
              items: [
                const DropdownMenuItem(value: null, child: Text('Select Kiosk')),
                ..._kiosks.map((k) => DropdownMenuItem(value: k, child: Text(k))),
              ],
              onChanged: (v) { setState(() { _kiosk = v; _page = 0; }); _load(); },
            ),
          if (_paymentMethods.isNotEmpty)
            WahaFilterDropdown<String?>(
              value: _paymentType,
              hint: 'Select Payment Method',
              items: [
                const DropdownMenuItem(value: null, child: Text('Select Payment Method')),
                ..._paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(m))),
              ],
              onChanged: (v) { setState(() { _paymentType = v; _page = 0; }); _load(); },
            ),
          WahaFilterDropdown<bool?>(
            value: _synced,
            hint: 'Select Sync',
            items: const [
              DropdownMenuItem(value: null,  child: Text('Select Sync')),
              DropdownMenuItem(value: true,  child: Text('Yes')),
              DropdownMenuItem(value: false, child: Text('No')),
            ],
            onChanged: (v) { setState(() { _synced = v; _page = 0; }); _load(); },
          ),
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
          Text('Total', style: TextStyle(fontWeight: FontWeight.w700,
              fontSize: 13, color: scheme.outline)),
          const SizedBox(width: 24),
          _SumTile(Icons.receipt_long_outlined, '${s['total_orders'] ?? 0}', 'Number of orders'),
          _SumTile(Icons.attach_money_outlined,  _fmtNum(s['sub_total']),    'Sub-Total'),
          _SumTile(Icons.percent_outlined,       _fmtNum(s['vat']),          'VAT'),
          _SumTile(Icons.paid_outlined,          _fmtNum(s['total']),        'Total'),
        ],
      ),
    );
  }

  Widget _orderFlag(String label, Color color, String tip) => Tooltip(
        message: tip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
      );

  DataColumn _dataColumn(ColorScheme scheme, int i) {
    final c = _allCols[i];
    final label = c.key == null
        ? Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600))
        : wahaSortableLabel(context, c.label, active: _sortCol == i, asc: _sortAsc);
    return DataColumn(
      numeric: c.numeric,
      tooltip: c.tip,
      label: label,
      onSort: c.key == null ? null : (_, __) => _sort(i, true),
    );
  }

  Future<void> _chooseColumns() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Columns'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in _allCols)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(c.label),
                      subtitle: c.fixed ? const Text('Always shown', style: TextStyle(fontSize: 11)) : null,
                      value: c.fixed || !_hidden.contains(c.id),
                      onChanged: c.fixed
                          ? null
                          : (v) {
                              setSt(() {});
                              setState(() => v == true ? _hidden.remove(c.id) : _hidden.add(c.id));
                              _saveHiddenColumns();
                            },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setSt(() {});
                setState(() => _hidden = {'sub', 'vat', 'synced'});
                _saveHiddenColumns();
              },
              child: const Text('Reset'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Widget _buildTableArea(ColorScheme scheme) {
    final from = _page * _pageSize + 1;
    final to   = ((_page + 1) * _pageSize).clamp(0, _totalCount);

    final visible = [
      for (var i = 0; i < _allCols.length; i++)
        if (_allCols[i].fixed || !_hidden.contains(_allCols[i].id)) i,
    ];

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
                  columns: [for (final i in visible) _dataColumn(scheme, i)],
                  rows: _items.map((row) {
                    final dt = row['created_at'] != null
                        ? _dtFmt.format(DateTime.parse(row['created_at'].toString()).toLocal())
                        : '—';
                    final synced = row['synced'] == true || row['synced'] == 1;
                    final orderId = row['id'];
                    Widget cell(String id) {
                      switch (id) {
                        case 'id':
                          return Text('#${row['display_id'] ?? ''}');
                        case 'did':
                          return Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('${row['order_reference'] ?? '—'}',
                                style: TextStyle(
                                    color: row['order_reference'] == null ? scheme.outline : null)),
                            if (row['offline_pushed'] == true) ...[
                              const SizedBox(width: 6),
                              const Tooltip(
                                message: 'Taken offline: created and paid on a kiosk without the server, then sent later.',
                                child: Icon(Icons.cloud_off_outlined, size: 16, color: Colors.indigo),
                              ),
                            ],
                            if (row['price_differs'] == true) ...[
                              const SizedBox(width: 6),
                              const Tooltip(
                                message: 'Price differs: prices or tax rate on the kiosk differed from the server when it was sent.',
                                child: Icon(Icons.price_change_outlined, size: 16, color: Colors.orange),
                              ),
                            ],
                          ]);
                        case 'branch':
                          return SizedBox(width: 140, child: Text(_parseBranchName(row), overflow: TextOverflow.ellipsis));
                        case 'kiosk':
                          return SizedBox(width: 100, child: Text('${row['kiosk'] ?? ''}', overflow: TextOverflow.ellipsis));
                        case 'payref':
                          return SizedBox(width: 130, child: Text('${row['ref'] ?? '—'}', overflow: TextOverflow.ellipsis));
                        case 'date':
                          return Text(dt);
                        case 'sub':
                          return Text(_fmtNum(row['subtotal_amount']), textAlign: TextAlign.right);
                        case 'vat':
                          return Text(_fmtNum(row['tax_amount']), textAlign: TextAlign.right);
                        case 'total':
                          return Text(_fmtNum(row['total_amount']), textAlign: TextAlign.right);
                        case 'paytype':
                          return Text('${row['payment_type'] ?? '—'}');
                        case 'status':
                          return _StatusChip(row['status']?.toString());
                        case 'synced':
                          return _SyncChip(synced);
                        case 'invoice':
                          return _invoiceButtons(orderId);
                        default:
                          return IconButton(
                            icon: const Icon(Icons.inventory_2_outlined, size: 20),
                            tooltip: 'View products',
                            onPressed: orderId == null ? null : () => _showProductsDialog(orderId.toString()),
                          );
                      }
                    }
                    return DataRow(cells: [for (final i in visible) DataCell(cell(_allCols[i].id))]);
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
                  _totalCount == 0
                      ? 'No entries'
                      : 'Showing $from–$to of $_totalCount entries',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                WahaPageSizeSelector(
                  value: _pageSize,
                  options: _pageSizeOptions,
                  onChanged: (v) { setState(() { _pageSize = v; _page = 0; }); _load(); },
                ),
                const SizedBox(width: 16),
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

  String _fmtNum(dynamic v) {
    if (v == null) return '0.00';
    return _numFmt.format((v as num).toDouble());
  }

  Widget _invoiceButtons(dynamic orderId) {
    Widget langBtn(String label, String? lang) {
      final url = orderId == null
          ? null
          : '${AppConfig.apiBaseUrl}/api/invoices/$orderId${lang != null ? '?lang=$lang' : ''}';
      return Tooltip(
        message: lang == null ? 'Open invoice (English)' : 'Open invoice (Arabic)',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: url == null ? null : () => html.window.open(url, '_blank'),
          child: Container(
            width: 28,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: url == null ? Colors.grey.shade300 : Colors.indigo.shade200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: url == null ? Colors.grey.shade400 : Colors.indigo.shade700)),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      langBtn('EN', null),
      const SizedBox(width: 4),
      langBtn('AR', 'ar'),
    ]);
  }

  Future<void> _showProductsDialog(String orderId) async {
    Map<String, dynamic>? order;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          if (order == null && error == null) {
            ApiClient().getOrder(orderId, token: context.read<AuthState>().token).then((o) {
              setSt(() => order = o);
            }).catchError((e) {
              // Close this dialog rather than show a misleading "no products"
              // state — the real error surfaces via the blocking dialog below.
              error = e.toString();
              if (ctx.mounted) Navigator.of(ctx).pop();
            });
          }
          final items = (order?['items'] as List? ?? []).cast<Map<String, dynamic>>();
          final taxRate = (order?['taxRate'] as num?)?.toDouble() ?? 0;
          // Shown prices carry VAT unless the organization turned that off: then
          // lineTotal - discountAmount no longer equals netAmount + taxAmount.
          final withVat = items.every((i) {
            final net = i['netAmount'], tax = i['taxAmount'];
            if (net == null || tax == null) return false;
            final shown = ((i['lineTotal'] as num?) ?? 0) - ((i['discountAmount'] as num?) ?? 0);
            return (shown - ((net as num) + (tax as num))).abs() < 0.01;
          });
          final vatNote = withVat ? 'incl. VAT' : 'excl. VAT';
          final currency = (order?['currency'] as String?)?.toUpperCase() ?? '';
          final dialogWidth = (MediaQuery.of(context).size.width * 0.7).clamp(500.0, 900.0);
          return AlertDialog(
            title: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Order Products${order?['displayId'] != null ? ' — #${order!['displayId']}' : ''}${order?['orderReference'] != null ? ' (${order!['orderReference']})' : ''}'),
                if (order?['offlinePushed'] == true)
                  _orderFlag('Taken offline', Colors.indigo,
                      'Created and paid on a kiosk without the server, then sent later.'),
                if (order?['priceDiffers'] == true)
                  _orderFlag('Price differs', Colors.orange,
                      'Prices or tax rate on the kiosk differed from the server when it was sent.'),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: order == null && error == null
                  ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                  : items.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('No products on this order.'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: dialogWidth),
                            child: DataTable(
                            columnSpacing: 16,
                            columns: [
                              DataColumn(label: Text('Description')),
                              DataColumn(label: Text('Barcode')),
                              DataColumn(numeric: true, label: Text('Qty')),
                              DataColumn(numeric: true, label: Text('Unit Price ($vatNote)')),
                              DataColumn(numeric: true, label: Text('Tax')),
                              DataColumn(numeric: true, label: Text('Total (incl. VAT)')),
                            ],
                            rows: items.map((item) {
                              final name = item['name'];
                              final label = name is Map
                                  ? ((name['en'] ?? name['ar'] ?? '') as String)
                                  : '${name ?? ''}';
                              // Tax and the final amount come from the server's per-line
                              // net and tax; only a backend without them is worked out here.
                              final net = (item['netAmount'] as num?)?.toDouble();
                              final serverTax = (item['taxAmount'] as num?)?.toDouble();
                              final lineTotal = (item['lineTotal'] as num?)?.toDouble() ?? 0;
                              final tax = serverTax ??
                                  double.parse((lineTotal * taxRate).toStringAsFixed(2));
                              final total = net != null && serverTax != null
                                  ? net + serverTax
                                  : lineTotal + tax;
                              return DataRow(cells: [
                                DataCell(SizedBox(width: 220, child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1))),
                                DataCell(SizedBox(width: 110, child: Text('${item['barcode'] ?? ''}', overflow: TextOverflow.ellipsis, maxLines: 1))),
                                DataCell(Text(fmtCount(item['quantity']))),
                                DataCell(Text('${fmtMoney(item['unitPrice'])} $currency')),
                                DataCell(Text('${fmtMoney(tax)} $currency')),
                                DataCell(Text('${fmtMoney(total)} $currency')),
                              ]);
                            }).toList(),
                            ),
                          ),
                        ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          );
        },
      ),
    );
    if (error != null && mounted) {
      showErrorDialogLater(context, error!);
    }
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String? status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final Color bg;
    switch (status) {
      case 'PAID':
        bg = const Color(0xFF2E7D32);
        break;
      case 'PENDING':
        bg = const Color(0xFFF57C00);
        break;
      case 'CANCELLED':
        bg = const Color(0xFFC62828);
        break;
      default:
        bg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        status?.toLowerCase() ?? '—',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: bg),
      ),
    );
  }
}

// ── Sync chip ─────────────────────────────────────────────────────────────────

class _SyncChip extends StatelessWidget {
  final bool synced;
  const _SyncChip(this.synced);

  @override
  Widget build(BuildContext context) {
    final color = synced ? const Color(0xFF2E7D32) : Colors.grey.shade500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        synced ? 'Yes' : 'No',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── Summary tile ──────────────────────────────────────────────────────────────

class _SumTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _SumTile(this.icon, this.value, this.label);

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

    final first = (page - 2).clamp(0, (total - 5).clamp(0, total - 1));
    final last  = (first + 5).clamp(0, total);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (page > 0) ...[
          _Btn(label: '«', onTap: () => onPage(0)),
          _Btn(label: '‹', onTap: () => onPage(page - 1)),
        ],
        if (first > 0) _Btn(label: '…', onTap: null),
        for (int i = first; i < last; i++)
          _Btn(label: '${i + 1}', selected: i == page,
              onTap: i == page ? null : () => onPage(i)),
        if (last < total) _Btn(label: '…', onTap: null),
        if (page < total - 1) ...[
          _Btn(label: '›', onTap: () => onPage(page + 1)),
          _Btn(label: '»', onTap: () => onPage(total - 1)),
        ],
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _Btn({required this.label, this.selected = false, this.onTap});

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

class _OrderCol {
  final String id;
  final String label;
  final String? key;
  final bool numeric;
  final bool fixed;
  final String? tip;
  const _OrderCol(this.id, this.label, this.key,
      {this.numeric = false, this.fixed = false, this.tip});
}
