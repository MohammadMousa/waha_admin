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
  DateTimeRange? _dateRange;

  // Sort
  int  _sortCol = 0;
  bool _sortAsc = false;

  // Lookups
  List<Map<String, dynamic>> _stores        = [];
  List<String>               _kiosks        = [];
  List<String>               _paymentMethods = [];

  // Data
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _items = [];
  int _totalCount = 0;
  int _page       = 0;
  static const _pageSize = 10;

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
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final results = await Future.wait([
        ApiClient().getReportStores(token),
        ApiClient().getReportKiosks(token),
        ApiClient().getReportPaymentMethods(token),
      ]);
      if (!mounted) return;
      setState(() {
        _stores         = (results[0] as List).cast<Map<String, dynamic>>();
        _kiosks         = (results[1] as List).map((e) => e['username']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        _paymentMethods = (results[2] as List).map((e) => e['provider']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
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
        if (_dateRange    != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange    != null) 'to':   _dateFmt.format(_dateRange!.end),
        'page': '$_page',
        'size': '$_pageSize',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/orders')
          .replace(queryParameters: params);
      final resp = await http.get(uri,
          headers: {'Authorization': 'Bearer $token'});
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
        if (_storeId     != null) 'storeId':    '$_storeId',
        if (_status      != null) 'status':      _status!,
        if (_kiosk       != null) 'kiosk':       _kiosk!,
        if (_paymentType != null) 'paymentType': _paymentType!,
        if (_synced      != null) 'synced':      '$_synced',
        if (_dateRange   != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange   != null) 'to':   _dateFmt.format(_dateRange!.end),
        'page': '0', 'size': '10000',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/orders')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200 && mounted) {
        final data  = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final rows  = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        final lines = [
          '#ID,Branch,Kiosk,Ref,Date,Sub-Total,VAT,Total,Currency,Payment Type,Status,Synced',
          ...rows.map((r) => [
            r['display_id'] ?? '',
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
        if (_dateRange   != null) 'from': _dateFmt.format(_dateRange!.start),
        if (_dateRange   != null) 'to':   _dateFmt.format(_dateRange!.end),
        'page': '0', 'size': '10000',
      };
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/admin/reports/orders')
          .replace(queryParameters: params);
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode != 200 || !mounted) return;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rows = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      final headers = ['#ID', 'Branch', 'Kiosk', 'Ref', 'Date', 'Sub-Total', 'VAT', 'Total', 'Payment', 'Status', 'Synced'];
      final rowsHtml = rows.map((r) {
        final dt = r['created_at'] != null
            ? _dtFmt.format(DateTime.parse(r['created_at'].toString()).toLocal()) : '—';
        return '<tr>'
            '<td>${r['display_id'] ?? ''}</td>'
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

  static const _sortKeys = [
    'display_id', 'branch_name', 'kiosk', 'ref',
    'created_at', 'subtotal_amount', 'tax_amount', 'total_amount',
    'payment_type', 'status', 'synced',
  ];

  void _applySortToList(List<Map<String, dynamic>> list) {
    final key = _sortCol < _sortKeys.length ? _sortKeys[_sortCol] : 'display_id';
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

  DataColumn _dataColumn(ColorScheme scheme, String label, int i, {bool numeric = false}) {
    final isActive = _sortCol == i;
    return DataColumn(
      numeric: numeric,
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
    final to   = ((_page + 1) * _pageSize).clamp(0, _totalCount);

    final cols = ['#ID', 'Branch', 'Kiosk', 'Ref', 'Date', 'Sub-Total', 'VAT', 'Total', 'Payment Type', 'Status', 'Synced'];

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
                  columns: List.generate(cols.length, (i) =>
                    _dataColumn(scheme, cols[i], i, numeric: i >= 5 && i <= 7)),
                  rows: _items.map((row) {
                    final dt = row['created_at'] != null
                        ? _dtFmt.format(DateTime.parse(row['created_at'].toString()).toLocal())
                        : '—';
                    final synced = row['synced'] == true || row['synced'] == 1;
                    return DataRow(cells: [
                      DataCell(Text('#${row['display_id'] ?? ''}')),
                      DataCell(SizedBox(width: 140, child: Text(_parseBranchName(row), overflow: TextOverflow.ellipsis))),
                      DataCell(SizedBox(width: 100, child: Text('${row['kiosk'] ?? ''}',       overflow: TextOverflow.ellipsis))),
                      DataCell(SizedBox(width: 130, child: Text('${row['ref'] ?? '—'}',         overflow: TextOverflow.ellipsis))),
                      DataCell(Text(dt)),
                      DataCell(Text(_fmtNum(row['subtotal_amount']), textAlign: TextAlign.right)),
                      DataCell(Text(_fmtNum(row['tax_amount']),      textAlign: TextAlign.right)),
                      DataCell(Text(_fmtNum(row['total_amount']),    textAlign: TextAlign.right)),
                      DataCell(Text('${row['payment_type'] ?? '—'}')),
                      DataCell(_StatusChip(row['status']?.toString())),
                      DataCell(_SyncChip(synced)),
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

  String _fmtNum(dynamic v) {
    if (v == null) return '0.00';
    return _numFmt.format((v as num).toDouble());
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

