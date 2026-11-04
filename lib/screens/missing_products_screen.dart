import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/localized_name.dart';
import '../utils/number_format.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';

/// Barcodes kiosks scanned that the catalog did not have, backed by
/// /api/admin/products/missing. VIEW_PRODUCTS may look; EDIT_PRODUCTS may also
/// clean up and remove records.
class MissingProductsScreen extends StatefulWidget {
  const MissingProductsScreen({super.key});

  @override
  State<MissingProductsScreen> createState() => _MissingProductsScreenState();
}

const _statusFilters = <String, String>{
  'open': 'Still missing',
  'created': 'Created since',
  'all': 'All',
};

class _MissingProductsScreenState extends State<MissingProductsScreen> {
  static const _pageSize = 50;
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _summary = {};
  List<Store> _stores = [];
  final Set<String> _selected = {}; // record ids, or barcodes in the company view
  String _groupBy = 'record'; // record = by branch, barcode = by company
  int _total = 0;
  int _page = 0;
  int? _storeId;
  String _status = 'open';
  String _sort = 'last';
  bool _asc = false;
  DateTimeRange? _range;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _barcodeCtrl = TextEditingController();
  final _kioskCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStores();
      _load();
    });
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _kioskCtrl.dispose();
    super.dispose();
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _loadStores() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final stores = await ApiClient().getAdminStores(token);
      if (mounted) setState(() => _stores = stores);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _selected.clear(); });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final data = await ApiClient().getMissingProducts(token,
          storeId: _storeId,
          q: _barcodeCtrl.text.trim(),
          username: _kioskCtrl.text.trim(),
          from: _range == null ? null : _dateFmt.format(_range!.start),
          to: _range == null ? null : _dateFmt.format(_range!.end),
          status: _status,
          sort: _sort,
          dir: _asc ? 'asc' : 'desc',
          groupBy: _groupBy,
          page: _page,
          size: _pageSize);
      if (!mounted) return;
      setState(() {
        _rows = (data['rows'] as List? ?? []).cast<Map<String, dynamic>>();
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
      setState(() { _error = 'Could not load missing products: $e'; _loading = false; });
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
      _page = 0;
    });
    _load();
  }

  String? get _orgSlug => _stores.firstOrNull?.orgSlug;

  void _createProduct(Map<String, dynamic> row) {
    final slug = _orgSlug;
    if (slug == null) {
      showErrorDialog(context, 'No organization found for this account');
      return;
    }
    Navigator.of(context).pushNamed(Routes.productEdit, arguments: {
      'productId': null,
      'storeSlug': slug,
      'initialBarcode': row['barcode']?.toString(),
    }).then((_) => _load());
  }

  Future<bool> _confirm(String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  /// Runs a write call under the busy flag; any failure is a blocking dialog.
  Future<void> _run(Future<void> Function(String token) call) async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    setState(() => _busy = true);
    try {
      await call(token);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) { _redirectLogin(); return; }
      showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Request failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _load();
      }
    }
  }

  Future<void> _clean() async {
    final ok = await _confirm('Clean created',
        'Remove every record whose product has since been created${_storeId == null ? '' : ' for this branch'}?',
        'Clean');
    if (!ok || !mounted) return;
    await _run((token) async {
      final res = await ApiClient().cleanMissingProducts(token, storeId: _storeId);
      if (!mounted) return;
      final n = (res['removed'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(n == 0 ? 'Nothing to clean.' : 'Removed ${fmtCount(n)} records.')));
    });
  }

  Future<void> _removeSelected() async {
    final ok = await _confirm('Remove records',
        _groupBy == 'barcode'
            ? 'Remove ${fmtCount(_selected.length)} selected barcodes from every branch? They reappear if scanned again.'
            : 'Remove ${fmtCount(_selected.length)} selected records? They reappear if the barcode is scanned again.',
        'Remove');
    if (!ok || !mounted) return;
    final byBarcode = _groupBy == 'barcode';
    final keys = _selected.toList();
    await _run((token) async {
      final n = await ApiClient().removeMissingProducts(
          ids: byBarcode ? null : keys.map(int.parse).toList(),
          barcodes: byBarcode ? keys : null,
          token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed ${fmtCount(n)} records.')));
    });
  }

  Future<void> _pickRange() async {
    final r = await showWahaDateRangePicker(context, initial: _range);
    if (r != null) {
      setState(() { _range = r; _page = 0; });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    final canEdit = context.watch<AuthState>().hasPermission('EDIT_PRODUCTS');
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.missingProducts),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Missing Products',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 24),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'record', label: Text('By branch')),
                          ButtonSegment(value: 'barcode', label: Text('By company')),
                        ],
                        selected: {_groupBy},
                        onSelectionChanged: (v) {
                          setState(() { _groupBy = v.first; _sort = 'last'; _asc = false; _page = 0; });
                          _load();
                        },
                      ),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
                      if (canEdit) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _clean,
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: const Text('Clean created'),
                        ),
                        if (_selected.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _busy ? null : _removeSelected,
                            icon: const Icon(Icons.delete_outline),
                            label: Text('Remove (${fmtCount(_selected.length)})'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                _cards(scheme),
                _filters(scheme),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _table(scheme, canEdit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cards(ColorScheme scheme) {
    Widget card(String label, dynamic value, IconData icon) => Expanded(
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
                    Text(fmtCount(value),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
          card('Missing products', _summary['missingProducts'], Icons.search_off_outlined),
          const SizedBox(width: 12),
          card('Scans missed', _summary['scansMissed'], Icons.qr_code_scanner),
          const SizedBox(width: 12),
          card('Missed in last 7 days', _summary['missedLast7Days'], Icons.schedule),
          const SizedBox(width: 12),
          card('Created since', _summary['created'], Icons.check_circle_outline),
        ],
      ),
    );
  }

  Widget _filters(ColorScheme scheme) {
    Widget field(TextEditingController c, String hint) => WahaSearchField(
          controller: c,
          hintText: hint,
          width: 200,
          onSubmitted: () { _page = 0; _load(); },
          onClear: () { _page = 0; _load(); },
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
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
              for (final s in _stores) DropdownMenuItem(value: s.id, child: Text(s.label())),
            ],
            onChanged: (v) { setState(() { _storeId = v; _page = 0; }); _load(); },
          ),
          WahaFilterDropdown<String?>(
            value: _status,
            hint: 'Select Status',
            items: [
              for (final e in _statusFilters.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) { setState(() { _status = v ?? 'open'; _page = 0; }); _load(); },
          ),
          field(_barcodeCtrl, 'Search barcode'),
          field(_kioskCtrl, 'Search kiosk username'),
          WahaFilterDateRange(
            range: _range,
            onTap: _pickRange,
            onClear: () { setState(() { _range = null; _page = 0; }); _load(); },
          ),
        ],
      ),
    );
  }

  Widget _table(ColorScheme scheme, bool canEdit) {
    const head = TextStyle(fontWeight: FontWeight.w600);
    final company = _groupBy == 'barcode';
    DataColumn col(String text, String key, {bool numeric = false}) => DataColumn(
          label: wahaSortableLabel(context, text,
              active: _sort == key, asc: _asc),
          numeric: numeric,
          onSort: (_, __) => _sortBy(key),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _rows.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Nothing to show.')))
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
                            showCheckboxColumn: canEdit,
                                                                                    columnSpacing: 20,
                            horizontalMargin: 20,
                            headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                            columns: [
                              if (company) ...[
                                col('Barcode', 'barcode'),
                                col('Branches', 'branches', numeric: true),
                              ] else ...[
                                col('Branch', 'store'),
                                col('Barcode', 'barcode'),
                              ],
                              col('Kiosk', 'user'),
                              col('Scans', 'count', numeric: true),
                              col('First seen', 'first'),
                              col('Last seen', 'last'),
                              col('Status', 'status'),
                              const DataColumn(label: Text('Actions', style: head)),
                            ],
                            rows: [for (final r in _rows) _row(r, canEdit)],
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
                      Text('${fmtCount(_total)} ${_groupBy == 'barcode' ? 'barcodes' : 'records'}',
                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                      const Spacer(),
                      WahaPaginationBar(
                        page: _page,
                        totalCount: _total,
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

  String _time(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '');
    return d == null ? '—' : _dtFmt.format(d.toLocal());
  }

  DataRow _row(Map<String, dynamic> r, bool canEdit) {
    final company = _groupBy == 'barcode';
    final key = company ? (r['barcode']?.toString() ?? '') : (r['id'] as num).toInt().toString();
    final product = (r['product'] as Map?)?.cast<String, dynamic>();
    return DataRow(
      selected: _selected.contains(key),
      onSelectChanged: canEdit
          ? (on) => setState(() => on == true ? _selected.add(key) : _selected.remove(key))
          : null,
      cells: [
        if (company) ...[
          DataCell(SelectableText(r['barcode']?.toString() ?? '')),
          DataCell(Tooltip(
            message: ((r['storeNames'] as List?) ?? []).join(', '),
            child: Text(fmtCount(r['branches'])),
          )),
        ] else ...[
          DataCell(Text(r['storeName']?.toString() ?? '—')),
          DataCell(SelectableText(r['barcode']?.toString() ?? '')),
        ],
        DataCell(Text(r['lastUsername']?.toString() ?? '—')),
        DataCell(Text(fmtCount(company ? r['scans'] : r['missCount']))),
        DataCell(Text(_time(r['firstMissedAt']))),
        DataCell(Text(_time(r['lastMissedAt']))),
        DataCell(product == null
            ? const Text('Missing')
            : Text('Created: ${parseLocalizedName(product['name'])}',
                style: const TextStyle(color: Color(0xFF2E7D32)))),
        DataCell(product == null && canEdit
            ? TextButton.icon(
                onPressed: () => _createProduct(r),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create product'),
              )
            : const SizedBox.shrink()),
      ],
    );
  }
}
