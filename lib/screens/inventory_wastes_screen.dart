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
import '../utils/number_format.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/product_search_field.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';
import '../utils/localized_name.dart';
import 'waste_record_screen.dart';

/// Inventory wastes (api level 5): list with summary, filters, export, detail.
class InventoryWastesScreen extends StatefulWidget {
  const InventoryWastesScreen({super.key});

  @override
  State<InventoryWastesScreen> createState() => _InventoryWastesScreenState();
}

class _InventoryWastesScreenState extends State<InventoryWastesScreen> {
  static const _pageSize = 20;
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

  // Filters
  int? _branchId;
  String? _reason;
  int? _employeeId;
  int? _productId;
  DateTimeRange? _range;
  final _searchCtrl = TextEditingController();

  // Lookups
  List<Map<String, dynamic>> _reasons = [];
  List<Map<String, dynamic>> _branches = [];
  List<Employee> _employees = [];
  Map<int, Store> _storesById = {};

  // Data
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _summary = {};
  int _total = 0;
  int _page = 0;
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  // Local sort over the loaded page.
  int _sortCol = 1;
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthState>().token;

  Future<void> _init() async {
    final token = _token;
    if (token == null) return _redirectLogin();
    try {
      final r = await Future.wait([
        ApiClient().getWasteReasons(token),
        ApiClient().getReportStores(token),
        ApiClient().getEmployees(token),
        ApiClient().getStoresForPicker(token),
      ]);
      if (!mounted) return;
      setState(() {
        _reasons = r[0] as List<Map<String, dynamic>>;
        _branches = (r[1] as List).cast<Map<String, dynamic>>();
        _employees = (r[2] as List).cast<Employee>();
        _storesById = {for (final s in (r[3] as List<Store>)) s.id: s};
      });
      await _load();
    } on ApiException catch (e) {
      if (e.statusCode == 401) return _redirectLogin();
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  String? get _from => _range == null ? null : _dateFmt.format(_range!.start);
  String? get _to => _range == null ? null : _dateFmt.format(_range!.end);

  Future<void> _load() async {
    final token = _token;
    if (token == null) return _redirectLogin();
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ApiClient().getWastes(token,
          branchId: _branchId, reason: _reason, employeeId: _employeeId, productId: _productId,
          search: _searchCtrl.text.trim(), from: _from, to: _to, page: _page, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = (d['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _summary = (d['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        _total = (d['totalCount'] as num?)?.toInt() ?? 0;
        _applySort();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) return _redirectLogin();
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _refilter(VoidCallback change) {
    setState(() { change(); _page = 0; });
    _load();
  }

  // ---- labels ----
  String _reasonLabel(String? code) {
    for (final r in _reasons) {
      if (r['code'] == code) return (r['nameEn'] ?? code ?? '').toString();
    }
    return code ?? '—';
  }

  String _branchLabel(Map<String, dynamic> s) {
    final id = (s['id'] as num?)?.toInt();
    final dn = _storesById[id]?.displayName;
    return dn?['en'] ?? dn?['ar'] ?? s['name']?.toString() ?? '';
  }

  String _employeeLabel(Employee e) {
    final full = [e.firstName, e.lastName].where((s) => s != null && s.isNotEmpty).join(' ');
    return full.isEmpty ? e.username : full;
  }

  String _dateOf(dynamic v) {
    if (v == null) return '—';
    final d = DateTime.tryParse(v.toString());
    return d == null ? v.toString() : _dtFmt.format(d.toLocal());
  }

  // ---- sorting ----
  static const _sortKeys = [
    'id', 'occurredAt', 'branchName', 'reason', 'employeeName', 'createdByName', 'itemCount', 'quantity',
  ];

  void _applySort() {
    final key = _sortKeys[_sortCol];
    _items.sort((a, b) {
      final va = a[key], vb = b[key];
      final c = (va is num && vb is num) ? va.compareTo(vb) : '${va ?? ''}'.compareTo('${vb ?? ''}');
      return _sortAsc ? c : -c;
    });
  }

  void _sort(int col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = true;
      }
      _applySort();
    });
  }

  // ---- actions ----
  Future<void> _pickRange() async {
    final r = await showWahaDateRangePicker(context, initial: _range);
    if (r != null) _refilter(() => _range = r);
  }

  Future<void> _export(String format) async {
    final token = _token;
    if (token == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ApiClient().exportWastes(token, format,
          branchId: _branchId, reason: _reason, employeeId: _employeeId, productId: _productId,
          search: _searchCtrl.text.trim(), from: _from, to: _to);
      final mime = format == 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/csv;charset=utf-8';
      final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));
      html.AnchorElement(href: url)
        ..setAttribute('download', 'inventory_wastes.$format')
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

  Future<void> _record() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WasteRecordScreen(
        branches: [for (final s in _branches) WasteChoice((s['id'] as num).toInt(), _branchLabel(s))],
        reasons: [for (final r in _reasons) WasteChoice(r['code'].toString(), (r['nameEn'] ?? r['code']).toString())],
        employees: [for (final e in _employees) WasteChoice(e.id, _employeeLabel(e))],
      ),
    ));
    if (saved == true && mounted) {
      _page = 0;
      _load();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final token = _token;
    if (token == null) return;
    try {
      final d = await ApiClient().getWaste(token, (row['id'] as num).toInt());
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => _WasteDetailDialog(
        waste: d, reason: _reasonLabel(d['reason']?.toString()), dateText: _dateOf(d['occurredAt']),
        createdText: _dateOf(d['createdAt']),
      ));
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    }
  }

  bool _showFilters = false;

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSidebar(currentRoute: Routes.inventoryWastes),
          Expanded(
            child: _loading && _items.isEmpty && _error == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _items.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, style: TextStyle(color: scheme.error)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ]))
                    : LayoutBuilder(builder: (context, c) {
                        final narrow = MediaQuery.sizeOf(context).width < kNarrowWidth;
                        if (narrow) {
                          return ListView(children: [
                            _header(scheme, narrow: true),
                            _summaryCards(scheme),
                            _filterToggle(scheme),
                            if (_showFilters) _filters(scheme),
                            _cards(scheme),
                          ]);
                        }
                        final head = [_header(scheme), _summaryCards(scheme), _filters(scheme)];
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                ...head,
                                Expanded(child: _table(scheme)),
                              ]);
                      }),
          ),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme, {bool narrow = false}) {
    final auth = context.watch<AuthState>();
    final title = Text('Inventory Wastes',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700));
    final actions = <Widget>[
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        MenuAnchor(
          menuChildren: [
            MenuItemButton(onPressed: () => _export('csv'), child: const Text('CSV')),
            MenuItemButton(onPressed: () => _export('xlsx'), child: const Text('Excel (.xlsx)')),
          ],
          builder: (_, ctrl, __) => OutlinedButton.icon(
            icon: _exporting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 16),
            label: const Text('Export'),
            onPressed: _exporting ? null : () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
          ),
        ),
        const SizedBox(width: 8),
        if (auth.canCreateWastes) ...[
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Record waste'),
            onPressed: _record,
          ),
          const SizedBox(width: 8),
        ],
        IconButton(icon: const Icon(Icons.refresh_outlined), tooltip: 'Refresh', onPressed: _load),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(pagePad(context), 20, pagePad(context), 0),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              const SizedBox(height: 6),
              Row(children: actions),
            ])
          : Row(children: [title, const Spacer(), ...actions]),
    );
  }

  Widget _filterToggle(ColorScheme scheme) {
    final active = [_branchId, _reason, _employeeId, _range, _productId].where((e) => e != null).length +
        (_searchCtrl.text.trim().isEmpty ? 0 : 1);
    return Padding(
      padding: EdgeInsets.fromLTRB(pagePad(context), 12, pagePad(context), 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: Icon(_showFilters ? Icons.expand_less : Icons.filter_list, size: 16),
          label: Text(active > 0 ? 'Filters ($active)' : 'Filters'),
          onPressed: () => setState(() => _showFilters = !_showFilters),
        ),
      ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    final from = _page * _pageSize + 1;
    final to = ((_page + 1) * _pageSize).clamp(0, _total);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pagePad(context) - 4, vertical: 10),
      child: adaptiveRow(context, children: [
        Text(
          _total == 0 ? 'No entries' : 'Showing ${fmtCount(from)}–${fmtCount(to)} of ${fmtCount(_total)} entries',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        WahaPaginationBar(
          page: _page,
          totalCount: _total,
          pageSize: _pageSize,
          onPage: (p) { setState(() => _page = p); _load(); },
        ),
      ]),
    );
  }

  Widget _cards(ColorScheme scheme) {
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 78, child: Text(k, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(pagePad(context), 12, pagePad(context), 0),
      child: Column(children: [
        if (_loading) const LinearProgressIndicator(),
        if (_items.isEmpty && !_loading)
          const Padding(padding: EdgeInsets.all(32), child: Text('No wastes.')),
        for (final r in _items)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openDetail(r),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('#${r['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_dateOf(r['occurredAt']),
                        style: TextStyle(color: scheme.onSurfaceVariant))),
                    TextButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                      onPressed: () => _openDetail(r),
                    ),
                  ]),
                  kv('Branch', '${r['branchName'] ?? '—'}'),
                  kv('Reason', _reasonLabel(r['reason']?.toString())),
                  kv('Employee', '${r['employeeName'] ?? '—'}'),
                  kv('Lines', fmtCount(r['itemCount'])),
                  kv('Quantity', fmtCount(r['quantity'])),
                  const SizedBox(height: 4),
                ]),
              ),
            ),
          ),
        _footer(scheme),
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _summaryCards(ColorScheme scheme) {
    final byReason = ((_summary['byReason'] as List?) ?? []).cast<Map<String, dynamic>>();
    Widget card(String title, String value, {String? sub}) => Container(
          width: 170,
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(pagePad(context), 14, pagePad(context), 0),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        card('Total quantity', fmtCount(_summary['totalQuantity']), sub: 'All reasons'),
        for (final r in byReason)
          card(_reasonLabel(r['reason']?.toString()), fmtCount(r['quantity']),
              sub: '${fmtCount(r['wastes'])} ${((r['wastes'] as num?) ?? 0) == 1 ? 'waste' : 'wastes'}'),
      ]),
    );
  }

  Widget _filters(ColorScheme scheme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pagePad(context), 14, pagePad(context), 12),
      child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        WahaFilterDropdown<int?>(
          value: _branchId,
          hint: 'All branches',
          items: [
            const DropdownMenuItem(value: null, child: Text('All branches')),
            for (final s in _branches)
              DropdownMenuItem(value: (s['id'] as num).toInt(), child: Text(_branchLabel(s))),
          ],
          onChanged: (v) => _refilter(() => _branchId = v),
        ),
        WahaFilterDropdown<String?>(
          value: _reason,
          hint: 'All reasons',
          items: [
            const DropdownMenuItem(value: null, child: Text('All reasons')),
            for (final r in _reasons)
              DropdownMenuItem(value: r['code'].toString(), child: Text((r['nameEn'] ?? r['code']).toString())),
          ],
          onChanged: (v) => _refilter(() => _reason = v),
        ),
        WahaFilterDropdown<int?>(
          value: _employeeId,
          hint: 'All employees',
          items: [
            const DropdownMenuItem(value: null, child: Text('All employees')),
            for (final e in _employees) DropdownMenuItem(value: e.id, child: Text(_employeeLabel(e))),
          ],
          onChanged: (v) => _refilter(() => _employeeId = v),
        ),
        WahaFilterDateRange(
          range: _range,
          onTap: _pickRange,
          onClear: () => _refilter(() => _range = null),
        ),
        ProductSearchField(
          hintText: 'Search product…',
          onSearch: (q) async {
            final t = _token;
            return t == null ? [] : ApiClient().getAdminProducts(t, search: q);
          },
          labelBuilder: (p) => parseLocalizedName(p['name']),
          onSelected: (p) => _refilter(() => _productId = p == null ? null : (p['id'] as num).toInt()),
        ),
        WahaSearchField(
          controller: _searchCtrl,
          hintText: 'Waste no. or notes',
          width: 200,
          onSubmitted: () { _page = 0; _load(); },
          onClear: () { _page = 0; _load(); },
        ),
      ]),
    );
  }

  DataColumn _col(ColorScheme scheme, String label, int i) {
    final active = _sortCol == i;
    return DataColumn(
      headingRowAlignment: MainAxisAlignment.center,
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 3),
        Icon(active ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
            size: 13, color: active ? scheme.primary : scheme.outline.withValues(alpha: 0.5)),
      ]),
      onSort: (c, _) => _sort(c),
    );
  }

  Widget _table(ColorScheme scheme) {
    final from = _page * _pageSize + 1;
    final to = ((_page + 1) * _pageSize).clamp(0, _total);
    const labels = ['ID', 'Date', 'Branch', 'Reason', 'Employee', 'Created by', 'Lines', 'Quantity'];
    return Container(
      margin: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _items.isEmpty && !_loading
              ? const Center(child: Text('No wastes.'))
              : LayoutBuilder(
                  builder: (_, c) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: c.maxWidth),
                      child: SingleChildScrollView(
                        child: DataTable(
                          showCheckboxColumn: false,
                          columnSpacing: 18,
                          horizontalMargin: 20,
                          headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 48,
                          columns: [
                            for (var i = 0; i < labels.length; i++) _col(scheme, labels[i], i),
                            const DataColumn(label: Center(child: Text('')), headingRowAlignment: MainAxisAlignment.center),
                          ],
                          rows: [
                            for (final r in _items)
                              DataRow(onSelectChanged: (_) => _openDetail(r), cells: [
                                DataCell(Center(child: Text('#${r['id']}'))),
                                DataCell(Center(child: Text(_dateOf(r['occurredAt'])))),
                                DataCell(Center(child: Text('${r['branchName'] ?? '—'}'))),
                                DataCell(Center(child: Text(_reasonLabel(r['reason']?.toString())))),
                                DataCell(Center(child: Text('${r['employeeName'] ?? '—'}'))),
                                DataCell(Center(child: Text('${r['createdByName'] ?? '—'}'))),
                                DataCell(Center(child: Text(fmtCount(r['itemCount'])))),
                                DataCell(Center(child: Text(fmtCount(r['quantity'])))),
                                DataCell(TextButton.icon(
                                  icon: const Icon(Icons.visibility_outlined, size: 16),
                                  label: const Text('View'),
                                  onPressed: () => _openDetail(r),
                                )),
                              ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pagePad(context) - 4, vertical: 10),
          child: adaptiveRow(context, children: [
            Text(
              _total == 0 ? 'No entries' : 'Showing ${fmtCount(from)}–${fmtCount(to)} of ${fmtCount(_total)} entries',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            WahaPaginationBar(
              page: _page,
              totalCount: _total,
              pageSize: _pageSize,
              onPage: (p) { setState(() => _page = p); _load(); },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _WasteDetailDialog extends StatelessWidget {
  final Map<String, dynamic> waste;
  final String reason;
  final String dateText;
  final String createdText;
  const _WasteDetailDialog({
    required this.waste, required this.reason, required this.dateText, required this.createdText,
  });

  @override
  Widget build(BuildContext context) {
    final items = ((waste['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            Expanded(child: Text(v)),
          ]),
        );
    final notes = waste['notes']?.toString() ?? '';
    return AlertDialog(
      title: Text('Waste #${waste['id']}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            kv('Date', dateText),
            kv('Branch', '${waste['branchName'] ?? '—'}'),
            kv('Reason', reason),
            kv('Employee', '${waste['employeeName'] ?? '—'}'),
            kv('Created by', '${waste['createdByName'] ?? '—'}'),
            kv('Created at', createdText),
            if (notes.isNotEmpty) kv('Notes', notes),
            const SizedBox(height: 12),
            DataTable(
              columnSpacing: 16,
              horizontalMargin: 0,
              columns: const [
                DataColumn(label: Text('Barcode')),
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Qty'), numeric: true),
              ],
              rows: [
                for (final i in items)
                  DataRow(cells: [
                    DataCell(Text('${i['barcode'] ?? '—'}')),
                    DataCell(Text('${i['nameEn'] ?? i['nameAr'] ?? '—'}')),
                    DataCell(Text(fmtCount(i['quantity']))),
                  ]),
              ],
            ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
