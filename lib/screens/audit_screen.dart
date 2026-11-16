import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/number_format.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';

/// Shared audit history: system actions, offers, coupons and roles.
/// Backed by /api/admin/audit (api level 6); older servers fall back to
/// /api/admin/system/audit (system rows only, super admin).
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

const _actions = <String, String>{
  '': 'All actions',
  'SETTING_CHANGED': 'Setting changed',
  'CACHE_CLEARED': 'Cache cleared',
  'CACHE_SAVED': 'Cache saved',
  'LOCKOUTS_CLEARED': 'Lockouts cleared',
  'AUDIT_ROW_DELETED': 'Audit row deleted',
  'AUDIT_CLEARED': 'Audit cleared',
  'AUDIT_ROWS_DELETED': 'Audit rows deleted',
  'CREATE': 'Created',
  'UPDATE': 'Updated',
  'ENABLE': 'Enabled',
  'DISABLE': 'Disabled',
  'DELETE': 'Deleted',
  'ROLE_CREATED': 'Role created',
  'ROLE_UPDATED': 'Role updated',
  'ROLE_DELETED': 'Role deleted',
  'ROLE_ASSIGNED': 'Role assigned',
  'ROLE_UNASSIGNED': 'Role unassigned',
};

const _systemOnlyActions = {
  'SETTING_CHANGED',
  'CACHE_CLEARED',
  'CACHE_SAVED',
  'LOCKOUTS_CLEARED',
  'AUDIT_ROW_DELETED',
  'AUDIT_CLEARED',
  'AUDIT_ROWS_DELETED',
};

const _defaultTypes = ['SYSTEM', 'OFFER', 'COUPON', 'ROLE'];
const _typeLabels = {
  'SYSTEM': 'System',
  'OFFER': 'Offers',
  'COUPON': 'Coupons',
  'ROLE': 'Roles',
};

class _AuditScreenState extends State<AuditScreen> {
  static const _pageSize = 50;
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 0;
  String? _action;
  String _scope = 'ALL';
  String? _type;
  int? _orgId;
  List<String> _types = _defaultTypes;
  final Set<int> _selected = {};
  // Local sort of the loaded page; the server already sends newest first.
  String _sortKey = 'createdAt';
  bool _sortAsc = false;
  DateTimeRange? _range;
  final _actorCtrl = TextEditingController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _actorCtrl.dispose();
    super.dispose();
  }

  bool get _shared => context.read<AuthState>().apiLevel >= 6;
  bool get _isSuper => context.read<AuthState>().isSuperAdmin;

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final from = _range == null ? null : _dateFmt.format(_range!.start);
      final to = _range == null ? null : _dateFmt.format(_range!.end);
      final data = _shared
          ? await ApiClient().getAudit(token,
              page: _page,
              size: _pageSize,
              scope: _isSuper ? _scope : null,
              type: _type,
              action: _action,
              actor: _actorCtrl.text.trim(),
              organizationId: _isSuper && _scope != 'SYSTEM' ? _orgId : null,
              from: from,
              to: to)
          : await ApiClient().getSystemAudit(token,
              page: _page,
              size: _pageSize,
              action: _action,
              actor: _actorCtrl.text.trim(),
              from: from,
              to: to);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        final t = (data['types'] as List?)?.map((e) => e.toString()).toList();
        if (t != null && t.isNotEmpty) _types = t;
        _items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) { _redirectLogin(); return; }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load: $e'; _loading = false; });
    }
  }

  Future<void> _write(Future<void> Function(String token) call) async {
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

  Future<bool> _confirm(String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    if (!await _confirm('Delete audit row?',
        'Delete row #${row['id']} (${row['action']})? This is recorded in the audit.', 'Delete')) {
      return;
    }
    final id = (row['id'] as num).toInt();
    await _write((t) => _shared
        ? ApiClient().deleteAuditRows(t, [id]).then((_) {})
        : ApiClient().deleteSystemAuditRow(t, id));
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (!await _confirm('Delete audit rows?',
        'Delete ${ids.length} selected row(s)? This is recorded in the audit.', 'Delete')) {
      return;
    }
    await _write((t) async {
      for (var i = 0; i < ids.length; i += 500) {
        await ApiClient().deleteAuditRows(t, ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500));
      }
    });
  }

  void _showRow(Map<String, dynamic> r) {
    String pretty(dynamic v) {
      final text = v?.toString() ?? '';
      if (text.isEmpty) return '—';
      try {
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      } catch (_) {
        return text;
      }
    }

    Widget block(String title, dynamic v) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            SelectableText(pretty(v), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_actions[r['action']] ?? r['action']?.toString() ?? 'Audit entry'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['actorName'] ?? '—'}  ·  ${r['target'] ?? '—'}  ·  ${r['ip'] ?? '—'}'),
                block('Old value', r['oldValue']),
                block('New value', r['newValue']),
                block('Details', r['details']),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _clearAudit() async {
    // First choose how much to clear, then confirm.
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_shared ? 'Clear audit (${_scopeLabel(_scope)})' : 'Clear audit'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'all'), child: const Text('Clear everything')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'before'),
              child: const Text('Clear entries before a date…')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    String? before;
    if (choice == 'before') {
      final d = await showWahaDatePicker(context);
      if (d == null || !mounted) return;
      before = _dateFmt.format(d);
    }
    if (!await _confirm(
        'Clear audit?',
        before == null
            ? 'Delete ALL audit entries? One entry is kept saying who cleared it.'
            : 'Delete all audit entries before $before? One entry is kept saying who cleared it.',
        'Clear audit')) {
      return;
    }
    await _write((t) async {
      final n = _shared
          ? await ApiClient().clearAudit(t, before: before, scope: _scope)
          : await ApiClient().clearSystemAudit(t, before: before);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Deleted ${fmtCount(n)} entries.')));
      }
      _page = 0;
    });
  }

  static String _scopeLabel(String s) => switch (s) {
        'SYSTEM' => 'system',
        'ORGANIZATION' => 'organizations',
        _ => 'all',
      };

  void _sort(String key) => setState(() {
        if (_sortKey == key) {
          _sortAsc = !_sortAsc;
        } else {
          _sortKey = key;
          _sortAsc = key != 'createdAt';
        }
      });

  List<Map<String, dynamic>> get _sortedItems {
    final list = [..._items];
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      final va = (a[_sortKey] ?? '').toString().toLowerCase();
      final vb = (b[_sortKey] ?? '').toString().toLowerCase();
      return va.compareTo(vb);
    }

    list.sort((a, b) => _sortAsc ? cmp(a, b) : cmp(b, a));
    return list;
  }

  DataColumn _col(String label, String key) => DataColumn(
        label: wahaSortableLabel(context, label, active: _sortKey == key, asc: _sortAsc),
        onSort: (_, __) => _sort(key),
      );

  Future<void> _pickRange() async {
    final r = await showWahaDateRangePicker(context, initial: _range);
    if (r == null) return;
    setState(() { _range = r; _page = 0; });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSidebar(currentRoute: Routes.systemAudit),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pagePad(context), 24, pagePad(context), 8),
                  child: adaptiveRow(context,
                    children: [
                      Text('Audit',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
                      const SizedBox(width: 8),
                      if (_isSuper && _selected.isNotEmpty) ...[
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: scheme.error),
                          onPressed: _deleteSelected,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: Text('Delete selected (${_selected.length})'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_isSuper) OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                        onPressed: _clearAudit,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Clear audit'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_shared && _isSuper)
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            minimumSize: const WidgetStatePropertyAll(Size(0, kWahaFilterControlHeight)),
                            maximumSize: const WidgetStatePropertyAll(Size(double.infinity, kWahaFilterControlHeight)),
                            padding: const WidgetStatePropertyAll(kWahaFilterControlPadding),
                            textStyle: const WidgetStatePropertyAll(
                                TextStyle(fontSize: kWahaFilterControlFontSize)),
                            shape: WidgetStatePropertyAll(
                                RoundedRectangleBorder(borderRadius: kWahaFilterControlRadius)),
                          ),
                          segments: const [
                            ButtonSegment(value: 'ALL', label: Text('All')),
                            ButtonSegment(value: 'SYSTEM', label: Text('System')),
                            ButtonSegment(value: 'ORGANIZATION', label: Text('Organization')),
                          ],
                          selected: {_scope},
                          onSelectionChanged: (v) {
                            setState(() { _scope = v.first; _page = 0; });
                            _load();
                          },
                        ),
                      if (_shared && _isSuper && _scope != 'SYSTEM' &&
                          context.read<AuthState>().organizations.length > 1)
                        WahaFilterDropdown<int?>(
                          value: _orgId,
                          hint: 'All organizations',
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All organizations')),
                            for (final o in context.read<AuthState>().organizations)
                              DropdownMenuItem(value: o.id, child: Text(o.name)),
                          ],
                          onChanged: (v) { setState(() { _orgId = v; _page = 0; }); _load(); },
                        ),
                      if (_shared)
                        WahaFilterDropdown<String?>(
                          value: _type,
                          hint: 'All types',
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All types')),
                            // System entries are for super admins only.
                            for (final t in _types)
                              if (_isSuper || t != 'SYSTEM')
                                DropdownMenuItem(value: t, child: Text(_typeLabels[t] ?? t)),
                          ],
                          onChanged: (v) { setState(() { _type = v; _page = 0; }); _load(); },
                        ),
                      WahaFilterDropdown<String?>(
                        value: _action,
                        hint: 'All actions',
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All actions')),
                          for (final e in _actions.entries)
                            if (e.key.isNotEmpty && (_isSuper || !_systemOnlyActions.contains(e.key)))
                              DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) { setState(() { _action = v; _page = 0; }); _load(); },
                      ),
                      WahaSearchField(
                        controller: _actorCtrl,
                        hintText: 'Actor',
                        width: 180,
                        onSubmitted: () { _page = 0; _load(); },
                        onClear: () { _page = 0; _load(); },
                      ),
                      WahaFilterDateRange(
                        range: _range,
                        onTap: _pickRange,
                        onClear: () { setState(() { _range = null; _page = 0; }); _load(); },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _table(scheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(ColorScheme scheme) {
    return Container(
      margin: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _items.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No audit entries.')))
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
                            showCheckboxColumn: _isSuper && _shared,
                            columns: [
                              _col('Time', 'createdAt'),
                              if (_shared) _col('Type', 'entityType'),
                              _col('Actor', 'actorName'),
                              _col('Action', 'action'),
                              _col('Target', 'target'),
                              const DataColumn(label: Text('Old value')),
                              const DataColumn(label: Text('New value')),
                              const DataColumn(label: Text('Details')),
                              const DataColumn(label: Text('IP')),
                              const DataColumn(label: Text('')),
                            ],
                            rows: [
                              for (final r in _sortedItems)
                                DataRow(
                                  selected: _selected.contains((r['id'] as num).toInt()),
                                  onSelectChanged: _isSuper && _shared
                                      ? (v) => setState(() {
                                            final id = (r['id'] as num).toInt();
                                            v == true ? _selected.add(id) : _selected.remove(id);
                                          })
                                      : null,
                                  cells: [
                                  DataCell(Text(r['createdAt'] != null
                                      ? _dtFmt.format(DateTime.parse(r['createdAt'].toString()).toLocal())
                                      : '—')),
                                  if (_shared)
                                    DataCell(Text(_typeLabels[r['entityType']] ?? r['entityType']?.toString() ?? '—')),
                                  DataCell(Text(r['actorName']?.toString() ?? '—')),
                                  DataCell(Text(_actions[r['action']] ?? r['action']?.toString() ?? '—')),
                                  DataCell(Text(r['target']?.toString() ?? '—')),
                                  DataCell(_clip(r['oldValue'])),
                                  DataCell(_clip(r['newValue'])),
                                  DataCell(_clip(r['details'])),
                                  DataCell(Text(r['ip']?.toString() ?? '—')),
                                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                      icon: const Icon(Icons.visibility_outlined, size: 18),
                                      tooltip: 'View',
                                      onPressed: () => _showRow(r),
                                    ),
                                    if (_isSuper)
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                                        tooltip: 'Delete',
                                        onPressed: () => _deleteRow(r),
                                      ),
                                  ])),
                                ]),
                            ],
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
                      Text('${fmtCount(_total)} entries',
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

  Widget _clip(dynamic v) {
    final text = v?.toString();
    if (text == null || text.isEmpty) return const Text('—');
    return SizedBox(
      width: 180,
      child: Tooltip(message: text, child: Text(text, overflow: TextOverflow.ellipsis)),
    );
  }
}
