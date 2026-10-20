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
import '../widgets/product_search_field.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_pagination_bar.dart';

/// Auto-applied promotions, backed by /api/admin/offers (backend api level 2).
/// VIEW_OFFERS may look; MANAGE_OFFERS may also create, edit, enable/disable
/// and delete. Validation errors come back per field and are shown together in
/// one blocking dialog.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

const _statusFilters = <String?, String>{
  null: 'All',
  'ENABLED': 'Enabled',
  'DISABLED': 'Disabled',
  'SCHEDULED': 'Scheduled',
  'EXPIRED': 'Expired',
};

String _discountLabel(Map<String, dynamic> o) {
  final value = o['discountValue'];
  return o['discountMode'] == 'PERCENTAGE' ? '${fmtAvg(value)}%' : fmtMoney(value);
}

class _OffersScreenState extends State<OffersScreen> {
  static const _pageSize = 20;

  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 0;
  String? _status;
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final data = await ApiClient().getOffers(token,
          status: _status, search: _searchCtrl.text.trim(), page: _page, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _total = (data['totalCount'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) { _redirectLogin(); return; }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Could not load offers: $e'; _loading = false; });
    }
  }

  /// Runs a write call, then reloads; any failure is shown as a blocking dialog.
  Future<void> _act(Future<void> Function(String token) call) async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      await call(token);
      if (mounted) _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) { _redirectLogin(); return; }
      showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Request failed: $e');
    }
  }

  Future<void> _openForm([Map<String, dynamic>? offer]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OfferFormDialog(offerId: (offer?['id'] as num?)?.toInt()),
    );
    if (saved == true && mounted) _load();
  }

  void _openDetail(Map<String, dynamic> offer) {
    showDialog<void>(
      context: context,
      builder: (_) => _OfferDetailDialog(offerId: (offer['id'] as num).toInt()),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> offer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete offer'),
        content: Text('Delete "${offer['name']}"? Past orders keep their discount.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      _act((t) => ApiClient().deleteOffer((offer['id'] as num).toInt(), token: t));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    final canManage = context.watch<AuthState>().hasPermission('MANAGE_OFFERS');
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.offers),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Offers',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
                      if (canManage) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _openForm(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add offer'),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(
                    children: [
                      Text('Status:', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      DropdownButton<String?>(
                        value: _status,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final e in _statusFilters.entries)
                            DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) { setState(() { _status = v; _page = 0; }); _load(); },
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Search by name',
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 18),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) { _page = 0; _load(); },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildTable(scheme, canManage),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(ColorScheme scheme, bool canManage) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _items.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No offers found.')))
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
                            columns: const [
                              DataColumn(label: Text('#ID', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Discount', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Start date', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('End date', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600))),
                              DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600))),
                            ],
                            rows: [for (final o in _items) _row(o, canManage)],
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
                      Text('${fmtCount(_total)} offers',
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

  DataRow _row(Map<String, dynamic> o, bool canManage) {
    final enabled = o['enabled'] == true;
    return DataRow(cells: [
      DataCell(Text('#${o['id']}')),
      DataCell(SizedBox(width: 220, child: Text(o['name']?.toString() ?? '', overflow: TextOverflow.ellipsis))),
      DataCell(Text(o['type'] == 'PRODUCT' ? 'Product' : 'Global')),
      DataCell(Text(_discountLabel(o))),
      DataCell(Text(o['startDate']?.toString() ?? '—')),
      DataCell(Text(o['endDate']?.toString() ?? '—')),
      DataCell(_StatusBadge(o['status']?.toString() ?? (enabled ? 'ENABLED' : 'DISABLED'))),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined, size: 20),
            tooltip: 'Details',
            onPressed: () => _openDetail(o),
          ),
          if (canManage) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit',
              onPressed: () => _openForm(o),
            ),
            Switch(
              value: enabled,
              onChanged: (v) => _act((t) =>
                  ApiClient().setOfferEnabled((o['id'] as num).toInt(), v, token: t)),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(o),
            ),
          ],
        ],
      )),
    ]);
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ENABLED' => ('Enabled', const Color(0xFF2E7D32)),
      'DISABLED' => ('Disabled', Colors.grey),
      'SCHEDULED' => ('Scheduled', const Color(0xFFF57C00)),
      'EXPIRED' => ('Expired', const Color(0xFFC62828)),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Detail ──────────────────────────────────────────────────────────────────

class _OfferDetailDialog extends StatefulWidget {
  final int offerId;
  const _OfferDetailDialog({required this.offerId});

  @override
  State<_OfferDetailDialog> createState() => _OfferDetailDialogState();
}

class _OfferDetailDialogState extends State<_OfferDetailDialog> {
  Map<String, dynamic>? _offer;
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final o = await ApiClient().getOffer(widget.offerId, token);
      if (mounted) setState(() => _offer = o);
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showErrorDialog(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _offer;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(o?['name']?.toString() ?? 'Offer'),
      content: SizedBox(
        width: 520,
        child: o == null
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('Type', o['type'] == 'PRODUCT' ? 'Product' : 'Global'),
                    _kv('Discount', _discountLabel(o)),
                    _kv('Dates', '${o['startDate']}  –  ${o['endDate']}'),
                    _kv('Status', o['status']?.toString() ?? (o['enabled'] == true ? 'ENABLED' : 'DISABLED')),
                    _kv('Total discount given', fmtMoney(o['totalDiscountGiven'])),
                    const SizedBox(height: 12),
                    Text('Branches', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(o['storeScope'] == 'ALL'
                        ? 'All branches'
                        : ((o['stores'] as List?) ?? []).map((s) => s['name']).join(', ')),
                    if (o['type'] == 'PRODUCT') ...[
                      const SizedBox(height: 12),
                      const Text('Products', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(((o['products'] as List?) ?? [])
                          .map((p) => parseLocalizedName(p['name']))
                          .join(', ')),
                    ],
                    const SizedBox(height: 12),
                    const Text('Recent applications', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    if (((o['recentApplications'] as List?) ?? []).isEmpty)
                      Text('Not applied to any order yet.', style: TextStyle(color: scheme.outline))
                    else
                      for (final a in (o['recentApplications'] as List))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                              '${_dtFmt.format(DateTime.parse(a['createdAt'].toString()).toLocal())}   '
                              'order ${a['orderId']}   −${fmtMoney(a['discountAmount'])}',
                              style: const TextStyle(fontSize: 13)),
                        ),
                  ],
                ),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}

// ── Add / edit form ─────────────────────────────────────────────────────────

class _OfferFormDialog extends StatefulWidget {
  /// null = create.
  final int? offerId;
  const _OfferFormDialog({this.offerId});

  @override
  State<_OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<_OfferFormDialog> {
  final _nameCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  String _type = 'GLOBAL';
  String _mode = 'AMOUNT';
  bool _enabled = true;
  DateTime? _start;
  DateTime? _end;
  String _storeScope = 'ALL';
  final Set<int> _storeIds = {};
  final Map<int, String> _products = {}; // id -> display name
  int _productFieldKey = 0;
  List<Store> _stores = [];
  num? _maxDiscount; // kept as loaded so editing never clears it
  bool _loading = true;
  bool _saving = false;

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  bool get _isEdit => widget.offerId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      _stores = await ApiClient().getAdminStores(token);
      if (_isEdit) {
        final o = await ApiClient().getOffer(widget.offerId!, token);
        _nameCtrl.text = o['name']?.toString() ?? '';
        _type = o['type']?.toString() ?? 'GLOBAL';
        _mode = o['discountMode']?.toString() ?? 'AMOUNT';
        _valueCtrl.text = (o['discountValue'] as num?)?.toString() ?? '';
        _maxDiscount = o['maxDiscountAmount'] as num?;
        _enabled = o['enabled'] == true;
        _start = DateTime.tryParse(o['startDate']?.toString() ?? '');
        _end = DateTime.tryParse(o['endDate']?.toString() ?? '');
        _storeScope = o['storeScope']?.toString() ?? 'ALL';
        for (final s in (o['stores'] as List? ?? [])) {
          _storeIds.add((s['id'] as num).toInt());
        }
        for (final p in (o['products'] as List? ?? [])) {
          _products[(p['id'] as num).toInt()] = parseLocalizedName(p['name']);
        }
      }
      if (mounted) setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context, false);
      showErrorDialog(context, e.message);
    }
  }

  Future<void> _pickDate(bool start) async {
    final d = await showWahaDatePicker(context, initial: start ? _start : _end, allowFuture: true);
    if (d != null) setState(() => start ? _start = d : _end = d);
  }

  Future<void> _save() async {
    if (_start == null || _end == null) {
      showErrorDialog(context, 'Start date and end date are required.');
      return;
    }
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final body = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      if (!_isEdit) 'type': _type,
      'discountMode': _mode,
      'discountValue': num.tryParse(_valueCtrl.text.trim()),
      if (_maxDiscount != null) 'maxDiscountAmount': _maxDiscount,
      'startDate': _dateFmt.format(_start!),
      'endDate': _dateFmt.format(_end!),
      'enabled': _enabled,
      'storeScope': _storeScope,
      'storeIds': _storeScope == 'SOME' ? _storeIds.toList() : <int>[],
      'productIds': _type == 'PRODUCT' ? _products.keys.toList() : <int>[],
    };
    setState(() => _saving = true);
    try {
      await ApiClient().saveOffer(body, id: widget.offerId, token: token);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorDialog(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorDialog(context, 'Request failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit offer' : 'Add offer'),
      content: SizedBox(
        width: 640,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(child: _form()),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Close')),
        FilledButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit')),
      ],
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        _row([
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          // The type is fixed once the offer exists.
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'GLOBAL', child: Text('Global')),
              DropdownMenuItem(value: 'PRODUCT', child: Text('Product')),
            ],
            onChanged: _isEdit ? null : (v) => setState(() => _type = v ?? 'GLOBAL'),
          ),
        ]),
        const SizedBox(height: 16),
        _row([
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'Amount / Percentage', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'AMOUNT', child: Text('Amount')),
              DropdownMenuItem(value: 'PERCENTAGE', child: Text('Percentage')),
            ],
            onChanged: (v) => setState(() => _mode = v ?? 'AMOUNT'),
          ),
          TextField(
            controller: _valueCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _mode == 'PERCENTAGE' ? 'Percentage' : 'Amount',
              border: const OutlineInputBorder(),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _row([
          _dateField('Start date', _start, () => _pickDate(true)),
          _dateField('End date', _end, () => _pickDate(false)),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        if (_type == 'PRODUCT') ...[
          const SizedBox(height: 8),
          const Text('Products', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _products.entries)
                InputChip(
                  label: Text(e.value),
                  onDeleted: () => setState(() => _products.remove(e.key)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ProductSearchField(
            key: ValueKey(_productFieldKey),
            width: 300,
            hintText: 'Search product to add…',
            onSearch: (query) async {
              final token = context.read<AuthState>().token;
              if (token == null) return [];
              return ApiClient().getAdminProducts(token, search: query);
            },
            labelBuilder: (p) => parseLocalizedName(p['name']),
            onSelected: (p) {
              if (p == null) return;
              setState(() {
                _products[(p['id'] as num).toInt()] = parseLocalizedName(p['name']);
                _productFieldKey++; // fresh, empty search box
              });
            },
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: 300,
          child: DropdownButtonFormField<String>(
            initialValue: _storeScope,
            decoration: const InputDecoration(labelText: 'All / some branches', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('All branches')),
              DropdownMenuItem(value: 'SOME', child: Text('Some branches')),
            ],
            onChanged: (v) => setState(() => _storeScope = v ?? 'ALL'),
          ),
        ),
        if (_storeScope == 'SOME') ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _stores)
                FilterChip(
                  label: Text(s.label()),
                  selected: _storeIds.contains(s.id),
                  onSelected: (on) => setState(() => on ? _storeIds.add(s.id) : _storeIds.remove(s.id)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(List<Widget> children) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: children[i]),
          ],
        ],
      );

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(value == null ? '' : _dateFmt.format(value)),
        ),
      );
}
