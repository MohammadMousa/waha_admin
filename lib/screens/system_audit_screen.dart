import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/number_format.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/waha_date_picker.dart';
import '../widgets/waha_pagination_bar.dart';

/// Super-admin audit of critical system actions (setting changes, cache clears
/// and saves, cleared lockouts, audit deletions). Backed by /api/admin/system/audit.
class SystemAuditScreen extends StatefulWidget {
  const SystemAuditScreen({super.key});

  @override
  State<SystemAuditScreen> createState() => _SystemAuditScreenState();
}

const _actions = <String, String>{
  '': 'All actions',
  'SETTING_CHANGED': 'Setting changed',
  'CACHE_CLEARED': 'Cache cleared',
  'CACHE_SAVED': 'Cache saved',
  'LOCKOUTS_CLEARED': 'Lockouts cleared',
  'AUDIT_ROW_DELETED': 'Audit row deleted',
  'AUDIT_CLEARED': 'Audit cleared',
};

class _SystemAuditScreenState extends State<SystemAuditScreen> {
  static const _pageSize = 50;
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 0;
  String _action = '';
  DateTime? _from;
  DateTime? _to;
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

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiClient().getSystemAudit(token,
          page: _page,
          size: _pageSize,
          action: _action,
          actor: _actorCtrl.text.trim(),
          from: _from == null ? null : _dateFmt.format(_from!),
          to: _to == null ? null : _dateFmt.format(_to!));
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
    await _write((t) => ApiClient().deleteSystemAuditRow(t, (row['id'] as num).toInt()));
  }

  Future<void> _clearAudit() async {
    // First choose how much to clear, then confirm.
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Clear audit'),
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
      final n = await ApiClient().clearSystemAudit(t, before: before);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Deleted ${fmtCount(n)} entries.')));
      }
      _page = 0;
    });
  }

  Future<void> _pickDate(bool from) async {
    final d = await showWahaDatePicker(context, initial: from ? _from : _to);
    if (d == null) return;
    setState(() { from ? _from = d : _to = d; _page = 0; });
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
        children: [
          const AdminSidebar(currentRoute: Routes.systemAudit),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('System Audit',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                        onPressed: _clearAudit,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Clear audit'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<String>(
                        value: _action,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final e in _actions.entries)
                            DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) { setState(() { _action = v ?? ''; _page = 0; }); _load(); },
                      ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _actorCtrl,
                          decoration: const InputDecoration(
                              hintText: 'Actor', isDense: true, border: OutlineInputBorder()),
                          onSubmitted: (_) { _page = 0; _load(); },
                        ),
                      ),
                      _dateButton('From', _from, () => _pickDate(true), () {
                        setState(() { _from = null; _page = 0; });
                        _load();
                      }),
                      _dateButton('To', _to, () => _pickDate(false), () {
                        setState(() { _to = null; _page = 0; });
                        _load();
                      }),
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

  Widget _dateButton(String label, DateTime? value, VoidCallback onTap, VoidCallback onClear) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(value == null ? label : '$label: ${_dateFmt.format(value)}'),
        ),
        if (value != null)
          IconButton(icon: const Icon(Icons.close, size: 16), tooltip: 'Clear', onPressed: onClear),
      ]);

  Widget _table(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                            columns: const [
                              DataColumn(label: Text('Time')),
                              DataColumn(label: Text('Actor')),
                              DataColumn(label: Text('Action')),
                              DataColumn(label: Text('Target')),
                              DataColumn(label: Text('Old value')),
                              DataColumn(label: Text('New value')),
                              DataColumn(label: Text('Details')),
                              DataColumn(label: Text('IP')),
                              DataColumn(label: Text('')),
                            ],
                            rows: [
                              for (final r in _items)
                                DataRow(cells: [
                                  DataCell(Text(r['createdAt'] != null
                                      ? _dtFmt.format(DateTime.parse(r['createdAt'].toString()).toLocal())
                                      : '—')),
                                  DataCell(Text(r['actorName']?.toString() ?? '—')),
                                  DataCell(Text(_actions[r['action']] ?? r['action']?.toString() ?? '—')),
                                  DataCell(Text(r['target']?.toString() ?? '—')),
                                  DataCell(_clip(r['oldValue'])),
                                  DataCell(_clip(r['newValue'])),
                                  DataCell(_clip(r['details'])),
                                  DataCell(Text(r['ip']?.toString() ?? '—')),
                                  DataCell(IconButton(
                                    icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteRow(r),
                                  )),
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
