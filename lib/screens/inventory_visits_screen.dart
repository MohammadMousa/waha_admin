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
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';
import '../utils/number_format.dart';

class InventoryVisitsScreen extends StatefulWidget {
  const InventoryVisitsScreen({super.key});

  @override
  State<InventoryVisitsScreen> createState() => _InventoryVisitsScreenState();
}

class _InventoryVisitsScreenState extends State<InventoryVisitsScreen> {
  // Server-side filters
  int? _branchId;
  int? _employeeId;
  DateTimeRange? _dateRange;

  // Client-side filter — the API doesn't support a `status` query param
  // (confirmed: passing one has no effect), so this filters the fetched
  // batch locally. Logged as OPEN in to_Backend_AI_On_Inventory_Reports_Task.
  String? _status;

  // Sort
  int _sortCol = 3;
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

  // Data — `_rawVisits` holds the latest server fetch (up to the API's max
  // page size) for the current branch/employee/date filters; `_items` is the
  // status-filtered, sorted, locally-paginated slice actually shown.
  List<Map<String, dynamic>> _rawVisits = [];
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

  static const _statuses = [null, 'ACTIVE', 'COMPLETED', 'CANCELLED'];
  static const _statusLabels = {
    null: 'Select Status',
    'ACTIVE': 'Active',
    'COMPLETED': 'Completed',
    'CANCELLED': 'Cancelled',
  };

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
      final data = await ApiClient().getInventoryVisits(
        token,
        branchId: _branchId,
        employeeId: _employeeId,
        from: _dateRange != null ? _dateFmt.format(_dateRange!.start) : null,
        to: _dateRange != null ? _dateFmt.format(_dateRange!.end) : null,
        page: 0,
        size: kMaxApiPageSize,
      );
      if (!mounted) return;
      _rawVisits = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() { _loading = false; });
      _recompute();
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Applies the client-side status filter + sort + local pagination to
  /// `_rawVisits` — no network call, safe to call on every filter/sort/page
  /// change.
  void _recompute() {
    final filtered = _status == null
        ? List<Map<String, dynamic>>.from(_rawVisits)
        : _rawVisits.where((r) => r['status'] == _status).toList();
    _applySortToList(filtered);
    setState(() {
      _totalCount = filtered.length;
      _items = filtered.skip(_page * _pageSize).take(_pageSize).toList();
    });
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
    return full.trim().isEmpty ? e.username : full;
  }

  /// Visit rows only carry `branch_name` (short code) — no
  /// `branch_display_name` field like Transfers/Returns/Stock. Parses it
  /// defensively so this starts working for free if backend adds it later
  /// (logged as OPEN in the coordination channel); falls back to the code.
  String _rowBranchName(Map<String, dynamic> row) =>
      parseLocalizedName(row['branch_display_name'], fallback: row['branch_name']?.toString() ?? '—');

  /// `employee_name` on some rows is blank or whitespace-only (a backend
  /// first-name+last-name concat bug when both are unset) — fall back to the
  /// employee's username via the already-loaded employees lookup rather than
  /// showing an empty cell.
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

  Duration? _duration(Map<String, dynamic> row) {
    final start = row['start_time'];
    final end = row['end_time'];
    if (start == null || end == null) return null;
    try {
      return DateTime.parse(end.toString()).difference(DateTime.parse(start.toString()));
    } catch (_) {
      return null;
    }
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static const _sortKeys = [
    'employee_name', 'branch_name', 'status', 'start_time', 'end_time',
  ];

  void _applySortToList(List<Map<String, dynamic>> list) {
    final key = _sortCol < _sortKeys.length ? _sortKeys[_sortCol] : 'start_time';
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
    });
    _recompute();
  }

  /// Fetches every visit matching the current branch/employee/date filters
  /// by paging through the API at its max page size — `size: 10000` (the
  /// old approach) is silently clamped by the backend down to the default
  /// of 20, which made exports incomplete.
  Future<List<Map<String, dynamic>>> _fetchAllForExport(String token) async {
    final all = <Map<String, dynamic>>[];
    var page = 0;
    while (true) {
      final data = await ApiClient().getInventoryVisits(
        token,
        branchId: _branchId,
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
    return _status == null ? all : all.where((r) => r['status'] == _status).toList();
  }

  Future<void> _exportCsv() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _exporting = true);
    try {
      final rows = await _fetchAllForExport(token);
      if (!mounted) return;
      final lines = [
        'Employee,Branch,Status,Start Time,End Time,Duration',
        ...rows.map((r) => [
              '"${_rowEmployeeName(r)}"',
              '"${_rowBranchName(r)}"',
              r['status'] ?? '',
              r['start_time'] ?? '',
              r['end_time'] ?? '',
              _fmtDuration(_duration(r)),
            ].join(',')),
      ];
      _downloadCsv('inventory_visits.csv', lines.join('\n'));
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
          const AdminSidebar(currentRoute: Routes.inventoryVisits),
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
            Text('Inventory Visits',
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
          WahaFilterDropdown<String?>(
            value: _status,
            hint: 'Select Status',
            items: _statuses.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(_statusLabels[s] ?? s ?? 'Select Status'),
                )).toList(),
            onChanged: (v) { setState(() { _status = v; _page = 0; }); _recompute(); },
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
        ],
      ),
    );
  }

  DataColumn _dataColumn(ColorScheme scheme, String label, int i) {
    final isActive = _sortCol == i;
    return DataColumn(
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
    final from = _totalCount == 0 ? 0 : _page * _pageSize + 1;
    final to = ((_page + 1) * _pageSize).clamp(0, _totalCount);
    final cols = ['Employee', 'Branch', 'Status', 'Start Time', 'End Time', 'Duration'];

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
                      columns: List.generate(cols.length, (i) => _dataColumn(scheme, cols[i], i)),
                      rows: _items.map((row) {
                        final start = row['start_time'] != null
                            ? _dtFmt.format(DateTime.parse(row['start_time'].toString()).toLocal())
                            : '—';
                        final end = row['end_time'] != null
                            ? _dtFmt.format(DateTime.parse(row['end_time'].toString()).toLocal())
                            : '—';
                        return DataRow(cells: [
                          DataCell(Text(_rowEmployeeName(row))),
                          DataCell(Text(_rowBranchName(row))),
                          DataCell(_StatusChip(row['status']?.toString())),
                          DataCell(Text(start)),
                          DataCell(Text(end)),
                          DataCell(Text(_fmtDuration(_duration(row)))),
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
                  onPage: (p) { setState(() => _page = p); _recompute(); },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String? status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final Color bg;
    switch (status) {
      case 'COMPLETED':
        bg = const Color(0xFF2E7D32);
        break;
      case 'ACTIVE':
        bg = const Color(0xFF1565C0);
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
