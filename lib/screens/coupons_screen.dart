import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/number_format.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';

/// Standalone discount coupons. VIEW_COUPONS may look; MANAGE_COUPONS may also
/// create (single or batch), edit, enable/disable and delete. Add and edit open
/// the full-screen form.
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

const _statusFilters = <String?, String>{
  null: 'All',
  'ACTIVE': 'Active',
  'DISABLED': 'Disabled',
  'EXPIRED': 'Expired',
  'SCHEDULED': 'Scheduled',
  'EXHAUSTED': 'Exhausted',
};

final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

String _fmtLocal(dynamic v) {
  final d = DateTime.tryParse(v?.toString() ?? '');
  return d == null ? '—' : _dtFmt.format(d);
}

class _CouponsScreenState extends State<CouponsScreen> {
  static const _pageSize = 20;

  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 0;
  String? _status;
  int? _employeeId;
  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFilters();
      _load();
    });
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

  /// Employee dropdown source; a failure only leaves the filter empty.
  Future<void> _loadFilters() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final emps = await ApiClient().getEmployees(token);
      if (mounted) setState(() => _employees = emps);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final data = await ApiClient().getCoupons(token,
          q: _searchCtrl.text.trim(),
          status: _status,
          employeeId: _employeeId,
          page: _page,
          size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) { _redirectLogin(); return; }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Could not load coupons: $e'; _loading = false; });
    }
  }

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

  Future<void> _openForm({int? id, bool batch = false}) async {
    final saved = await Navigator.pushNamed(context, Routes.couponEdit,
        arguments: {'couponId': id, 'batch': batch});
    if (saved == true && mounted) _load();
  }

  void _openRedemptions(Map<String, dynamic> coupon) {
    showDialog<void>(
      context: context,
      builder: (_) => _RedemptionsDialog(
        couponId: (coupon['id'] as num).toInt(),
        code: coupon['code']?.toString() ?? '',
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> coupon) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete coupon'),
        content: Text('Delete "${coupon['code']}"? Past orders keep their discount, '
            'and the code can be used again for a new coupon.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    final id = (coupon['id'] as num).toInt();
    try {
      await ApiClient().deleteCoupon(id, token: token);
      if (mounted) _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (e.statusCode == 409) {
        // Used by orders: it cannot be deleted, so offer to disable it instead.
        final disable = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.error_outline, color: Theme.of(ctx).colorScheme.error, size: 32),
            title: const Text('Cannot delete coupon'),
            content: SelectableText(e.message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disable instead')),
            ],
          ),
        );
        if (disable == true && mounted) {
          _act((t) => ApiClient().setCouponEnabled(id, false, token: t));
        }
        return;
      }
      showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Request failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    final canManage = context.watch<AuthState>().hasPermission('MANAGE_COUPONS');
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.coupons),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Coupons',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
                      if (canManage) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openForm(batch: true),
                          icon: const Icon(Icons.library_add_outlined),
                          label: const Text('Batch create'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _openForm,
                          icon: const Icon(Icons.add),
                          label: const Text('Add coupon'),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      WahaFilterDropdown<String?>(
                        value: _status,
                        hint: 'Select Status',
                        items: [
                          for (final e in _statusFilters.entries)
                            DropdownMenuItem(
                                value: e.key, child: Text(e.key == null ? 'Select Status' : e.value)),
                        ],
                        onChanged: (v) { setState(() { _status = v; _page = 0; }); _load(); },
                      ),
                      WahaFilterDropdown<int?>(
                        value: _employeeId,
                        hint: 'Select Employee',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Select Employee')),
                          for (final e in _employees)
                            DropdownMenuItem(value: e.id, child: Text(e.displayName)),
                        ],
                        onChanged: (v) { setState(() { _employeeId = v; _page = 0; }); _load(); },
                      ),
                      WahaSearchField(
                        controller: _searchCtrl,
                        hintText: 'Search by code or name',
                        width: 260,
                        onSubmitted: () { _page = 0; _load(); },
                        onClear: () { _page = 0; _load(); },
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
    const head = TextStyle(fontWeight: FontWeight.w600);
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _items.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No coupons found.')))
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
                              DataColumn(label: Text('#ID', style: head)),
                              DataColumn(label: Text('Code', style: head)),
                              DataColumn(label: Text('Name', style: head)),
                              DataColumn(label: Text('Applies to', style: head)),
                              DataColumn(label: Text('Discount', style: head)),
                              DataColumn(label: Text('Branches', style: head)),
                              DataColumn(label: Text('Used', style: head), numeric: true),
                              DataColumn(label: Text('Discount given', style: head), numeric: true),
                              DataColumn(label: Text('Employee', style: head)),
                              DataColumn(label: Text('Expires', style: head)),
                              DataColumn(label: Text('Status', style: head)),
                              DataColumn(label: Text('Actions', style: head)),
                            ],
                            rows: [for (final c in _items) _row(c, canManage)],
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
                      Text('${fmtCount(_total)} coupons',
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

  DataRow _row(Map<String, dynamic> c, bool canManage) {
    final enabled = c['enabled'] == true;
    final maxInvoices = (c['maxInvoices'] as num?)?.toInt();
    final used = (c['usageCount'] as num?)?.toInt() ?? 0;
    final discount = c['discountSummary']?.toString() ??
        (c['discountMode'] == 'PERCENTAGE' ? '${fmtAvg(c['discountValue'])}%' : fmtMoney(c['discountValue']));
    return DataRow(cells: [
      DataCell(Text('#${c['id']}')),
      DataCell(SelectableText(c['code']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600))),
      DataCell(ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Tooltip(
              message: c['name']?.toString() ?? '',
              child: Text(c['name']?.toString() ?? '—', overflow: TextOverflow.ellipsis)))),
      DataCell(Text(c['type'] == 'PRODUCT' ? 'Products' : 'Whole order')),
      DataCell(Text(discount)),
      DataCell(Text(c['storeScope'] == 'SOME' ? 'Selected' : 'All')),
      DataCell(Text(maxInvoices == null ? fmtCount(used) : '${fmtCount(used)} / ${fmtCount(maxInvoices)}')),
      DataCell(Text(fmtMoney(c['usedAmount']))),
      DataCell(Text(c['employeeName']?.toString() ?? '—')),
      DataCell(Text(c['expiresAt'] == null ? '—' : _fmtLocal(c['expiresAt']))),
      DataCell(_StatusBadge(c['status']?.toString() ?? (enabled ? 'ACTIVE' : 'DISABLED'))),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined, size: 20),
            tooltip: 'Redemptions',
            onPressed: () => _openRedemptions(c),
          ),
          if (canManage) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit',
              onPressed: () => _openForm(id: (c['id'] as num).toInt()),
            ),
            Switch(
              value: enabled,
              onChanged: (v) => _act((t) =>
                  ApiClient().setCouponEnabled((c['id'] as num).toInt(), v, token: t)),
            ),
            // Used coupons cannot be deleted (409), so offer Delete only before first use.
            // The server has the last word, as unpaid orders can also hold a coupon.
            if (used == 0)
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(c),
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
      'ACTIVE' => ('Active', const Color(0xFF2E7D32)),
      'DISABLED' => ('Disabled', Colors.grey),
      'SCHEDULED' => ('Scheduled', const Color(0xFFF57C00)),
      'EXPIRED' => ('Expired', const Color(0xFFC62828)),
      'EXHAUSTED' => ('Exhausted', const Color(0xFFC62828)),
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

// ── Redemptions ──────────────────────────────────────────────────────────────

class _RedemptionsDialog extends StatefulWidget {
  final int couponId;
  final String code;
  const _RedemptionsDialog({required this.couponId, required this.code});

  @override
  State<_RedemptionsDialog> createState() => _RedemptionsDialogState();
}

class _RedemptionsDialogState extends State<_RedemptionsDialog> {
  static const _pageSize = 10;
  List<Map<String, dynamic>>? _items;
  int _total = 0;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final data = await ApiClient()
          .getCouponRedemptions(widget.couponId, token, page: _page, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _total = (data['total'] as num?)?.toInt() ?? 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showErrorDialog(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    const head = TextStyle(fontWeight: FontWeight.w600);
    return AlertDialog(
      title: Text('Redemptions of ${widget.code}'),
      content: SizedBox(
        width: 760,
        child: items == null
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : items.isEmpty
                ? const SizedBox(height: 60, child: Center(child: Text('Not used on any order yet.')))
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('Order', style: head)),
                              DataColumn(label: Text('Date', style: head)),
                              DataColumn(label: Text('Branch', style: head)),
                              DataColumn(label: Text('Cashier', style: head)),
                              DataColumn(label: Text('Status', style: head)),
                              DataColumn(label: Text('Total', style: head), numeric: true),
                              DataColumn(label: Text('Discount', style: head), numeric: true),
                            ],
                            rows: [
                              for (final r in items)
                                DataRow(cells: [
                                  DataCell(Text('#${r['displayId'] == null ? r['orderId'] : r['displayId']}')),
                                  DataCell(Text(r['createdAt'] == null
                                      ? '—'
                                      : _dtFmt.format(DateTime.parse(r['createdAt'].toString()).toLocal()))),
                                  DataCell(Text(r['storeName']?.toString() ?? '—')),
                                  DataCell(Text(r['username']?.toString() ?? '—')),
                                  DataCell(Text(r['orderStatus']?.toString() ?? '—')),
                                  DataCell(Text(fmtMoney(r['orderTotal']))),
                                  DataCell(Text(fmtMoney(r['discountAmount']))),
                                ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: WahaPaginationBar(
                            page: _page,
                            totalCount: _total,
                            pageSize: _pageSize,
                            onPage: (p) { setState(() => _page = p); _load(); },
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
