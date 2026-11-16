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

/// Super-admin system settings (global, organization 0), cache actions and the
/// login-lockout reset. Backed by /api/admin/system/* (api level 3, MANAGE_SYSTEM).
class SystemConfigScreen extends StatefulWidget {
  const SystemConfigScreen({super.key});

  @override
  State<SystemConfigScreen> createState() => _SystemConfigScreenState();
}

class _SystemConfigScreenState extends State<SystemConfigScreen> {
  List<Map<String, dynamic>> _settings = [];
  List<Map<String, dynamic>> _others = [];
  List<Map<String, dynamic>> _caches = [];
  List<Map<String, dynamic>> _cleanup = [];
  final Map<String, TextEditingController> _cleanupCtrls = {};
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String> _saved = {}; // value last loaded from the server
  bool _loading = true;
  bool _busy = false;
  String? _error;

  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final c in _cleanupCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _token => context.read<AuthState>().token;

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  /// Value shown for a setting: the stored one, else its default.
  static String _shown(Map<String, dynamic> s) =>
      (s['value'] ?? s['default'] ?? '').toString();

  void _applySettings(Map<String, dynamic> data) {
    _settings = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
    _others = (data['others'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final s in _settings) {
      final key = s['key'].toString();
      _saved[key] = _shown(s);
      (_ctrls[key] ??= TextEditingController()).text = _shown(s);
    }
  }

  void _applyCleanup(Map<String, dynamic> data) {
    _cleanup = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final t in _cleanup) {
      (_cleanupCtrls[t['key'].toString()] ??= TextEditingController()).text =
          (t['days'] ?? 0).toString();
    }
  }

  Future<void> _reloadCleanup(String token) async {
    final data = await ApiClient().getSystemCleanup(token);
    if (mounted) setState(() => _applyCleanup(data));
  }

  Future<void> _saveCleanupDays(Map<String, dynamic> t) async {
    final text = _cleanupCtrls[t['key'].toString()]!.text.trim();
    if (int.tryParse(text) == null) {
      showErrorDialog(context, 'Days must be a whole number (0 turns the task off).');
      return;
    }
    await _run((tok) async {
      await ApiClient().putSystemProperties(tok, {t['setting'].toString(): text});
      await _reloadCleanup(tok);
      if (mounted) _toast('${t['label']} saved.');
    });
  }

  Future<void> _runCleanup({Map<String, dynamic>? task}) async {
    final what = task == null ? 'every task that is on' : '"${task['label']}"';
    if (!await _confirm('Run cleanup now?',
        'Removes old rows for $what. This cannot be undone and is recorded in the system audit.',
        'Run now')) {
      return;
    }
    await _run((tok) async {
      final r = await ApiClient().runSystemCleanup(tok, table: task?['key']?.toString());
      await _reloadCleanup(tok);
      if (!mounted) return;
      final failed = (r['items'] as List? ?? [])
          .whereType<Map>()
          .where((i) => (i['error'] ?? '').toString().isNotEmpty)
          .length;
      _toast('Removed ${fmtCount(r['removed'] ?? 0)} row(s)'
          '${failed > 0 ? ', $failed task(s) failed' : ''}.');
    });
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) { _redirectLogin(); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final level = context.read<AuthState>().apiLevel;
      final settings = await ApiClient().getSystemProperties(token);
      final caches = await ApiClient().getSystemCaches(token);
      final cleanup = level >= 5
          ? await ApiClient().getSystemCleanup(token)
          : null;
      if (!mounted) return;
      setState(() {
        _applySettings(settings);
        if (cleanup != null) _applyCleanup(cleanup);
        _caches = (caches['items'] as List? ?? []).cast<Map<String, dynamic>>();
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

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
    return ok == true && mounted;
  }

  /// Runs a write call with the busy flag; any failure is a blocking dialog.
  Future<void> _run(Future<void> Function(String token) call) async {
    final token = _token;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSetting(Map<String, dynamic> s, String value) async {
    final key = s['key'].toString();
    if (key == 'publicBaseUrl' &&
        !await _confirm('Change public base URL?',
            'Invoice links and QR codes will use "$value" from now on.', 'Save')) {
      return;
    }
    await _run((t) async {
      final data = await ApiClient().putSystemProperties(t, {key: value});
      if (!mounted) return;
      setState(() => _applySettings(data));
      _toast('$key saved.');
    });
  }

  Future<void> _cacheAction(String action, {String? name, String? done}) => _run((t) async {
        final r = await ApiClient().systemCacheAction(t, action, name: name);
        final caches = await ApiClient().getSystemCaches(t);
        if (!mounted) return;
        setState(() => _caches = (caches['items'] as List? ?? []).cast<Map<String, dynamic>>());
        final n = r['cleared'] ?? r['saved'];
        _toast(done ?? (n is num ? 'Done ($n).' : 'Done.'));
      });

  Future<void> _flushAll() async {
    if (await _confirm('Flush cache?',
        'Clears every cache that can be cleared. Data is read again from the database on next use.',
        'Flush cache')) {
      await _cacheAction('clear-all', done: 'Caches flushed.');
    }
  }

  Future<void> _saveAll() async {
    if (await _confirm('Save cache?',
        'Writes pending last-seen data to the database now instead of at the next scheduled flush.',
        'Save cache')) {
      await _cacheAction('save-all', done: 'Pending data saved.');
    }
  }

  Future<void> _clearLockouts() async {
    if (!await _confirm('Clear login lockouts?',
        'Lifts every lockout: users, employees, devices, unknown names and addresses. '
        'This is recorded in the system audit.', 'Clear lockouts')) {
      return;
    }
    await _run((t) async {
      final n = await ApiClient().clearLockouts(t);
      if (mounted) _toast('Cleared $n lockout(s).');
    });
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
          const AdminSidebar(currentRoute: Routes.systemConfig),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pagePad(context), 24, pagePad(context), 8),
                  child: adaptiveRow(context,
                    children: [
                      Text('System Configuration',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 24),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 980),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _card('System settings', scheme, [
                                  Text(
                                    'Global values for the whole system. Changes take effect at once. '
                                    'All of them are visible in the public config, so never store secrets here.',
                                    style: TextStyle(fontSize: 12, color: scheme.outline),
                                  ),
                                  const SizedBox(height: 8),
                                  for (final s in _settings)
                                    if (_cleanup.isEmpty || !s['key'].toString().startsWith('Cleanup_'))
                                      _settingRow(s, scheme),
                                  if (_others.isNotEmpty)
                                    ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      title: const Text('Other global settings (read-only)',
                                          style: TextStyle(fontSize: 14)),
                                      children: [
                                        for (final o in _others)
                                          ListTile(
                                            dense: true,
                                            title: Text(o['key'].toString()),
                                            trailing: Text(o['value']?.toString() ?? ''),
                                          ),
                                      ],
                                    ),
                                ]),
                                const SizedBox(height: 16),
                                _card('Caches and memory', scheme, [
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    FilledButton.icon(
                                      onPressed: _busy ? null : _flushAll,
                                      icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                                      label: const Text('Flush cache'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _busy ? null : _saveAll,
                                      icon: const Icon(Icons.save_outlined, size: 18),
                                      label: const Text('Save cache'),
                                    ),
                                  ]),
                                  const SizedBox(height: 8),
                                  for (final c in _caches) _cacheRow(c, scheme),
                                ]),
                                if (_cleanup.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  _cleanupCard(scheme),
                                ],
                                const SizedBox(height: 16),
                                _card('Login lockouts', scheme, [
                                  Text('Lifts every lockout. Not part of "Flush cache".',
                                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                                    onPressed: _busy ? null : _clearLockouts,
                                    icon: const Icon(Icons.lock_open_outlined, size: 18),
                                    label: const Text('Clear login lockouts'),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, ColorScheme scheme, List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  /// Counts and sizes get thousands separators in hints; other types show as is.
  static String _hint(Map<String, dynamic> s, dynamic v) {
    if (v == null || v.toString().isEmpty) return '';
    return s['type'] == 'integer' ? fmtCount(num.tryParse(v.toString()) ?? 0) : v.toString();
  }

  Widget _settingRow(Map<String, dynamic> s, ColorScheme scheme) {
    final key = s['key'].toString();
    final type = s['type']?.toString();
    final ctrl = _ctrls[key]!;
    final changed = ctrl.text.trim() != _saved[key];
    final def = s['default']?.toString() ?? '';
    final isBool = type == 'boolean';
    final field = isBool
        ? DropdownButtonFormField<String>(
            initialValue: ctrl.text.toLowerCase() == 'false' ? 'false' : 'true',
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 'true', child: Text('true — Enabled')),
              DropdownMenuItem(value: 'false', child: Text('false — Disabled')),
            ],
            onChanged: (v) => setState(() => ctrl.text = v ?? 'true'),
          )
        : TextField(
            controller: ctrl,
            keyboardType: type == 'integer' ? TextInputType.number : TextInputType.text,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
        if ((s['description'] ?? '').toString().isNotEmpty)
          Text(s['description'].toString(), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        Text(
          [
            if ((s['constraints'] ?? '').toString().isNotEmpty) s['constraints'].toString(),
            'Default: ${def.isEmpty ? '(none)' : _hint(s, def)}',
          ].join('  ·  '),
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
      ],
    );
    final saveBtn = FilledButton(
      onPressed: _busy || !changed ? null : () => _saveSetting(s, ctrl.text.trim()),
      child: const Text('Save'),
    );
    final resetBtn = TextButton(
      // Reset = send the default.
      onPressed: _busy || ctrl.text.trim() == def ? null : () => _saveSetting(s, def),
      child: const Text('Reset'),
    );
    if (MediaQuery.sizeOf(context).width < kNarrowWidth) {
      // Phones: description on top, then the field with its buttons below.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            info,
            const SizedBox(height: 8),
            field,
            const SizedBox(height: 8),
            Row(children: [saveBtn, const SizedBox(width: 8), resetBtn]),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: info),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: field),
          const SizedBox(width: 8),
          saveBtn,
          const SizedBox(width: 4),
          resetBtn,
        ],
      ),
    );
  }

  Widget _cleanupCard(ColorScheme scheme) => _card('Data cleanup', scheme, [
        Text(
          'Old log and history rows are removed by themselves every night at 03:30. '
          'Failed or pending sync rows are never touched, and orders and payments are never removed. '
          'Days: 0 turns a task off; otherwise it must be at least the minimum shown.',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : () => _runCleanup(),
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Run all'),
        ),
        const SizedBox(height: 4),
        for (final t in _cleanup) _cleanupRow(t, scheme),
      ]);

  Widget _cleanupRow(Map<String, dynamic> t, ColorScheme scheme) {
    final key = t['key'].toString();
    final ctrl = _cleanupCtrls[key]!;
    final enabled = t['enabled'] == true;
    final changed = ctrl.text.trim() != (t['days'] ?? 0).toString();
    final lastAt = t['lastRunAt'] != null
        ? _dtFmt.format(DateTime.parse(t['lastRunAt'].toString()).toLocal())
        : 'never';
    final src = (t['lastSource'] ?? '').toString();
    final err = (t['lastError'] ?? '').toString();
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(t['description']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        Text(
          '${fmtCount(t['rows'] ?? 0)} rows  ·  ${fmtCount(t['eligible'] ?? 0)} ready to remove  ·  '
          'last run: $lastAt${t['lastRunAt'] != null ? ' (${fmtCount(t['lastRemoved'] ?? 0)} removed'
              '${src.isEmpty ? '' : ', ${src.toLowerCase()}'})' : ''}',
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
        if (err.isNotEmpty)
          Text(err, style: TextStyle(fontSize: 12, color: scheme.error)),
      ],
    );
    final field = SizedBox(
      width: 150,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          isDense: true,
          labelText: 'Days (min ${t['minDays']})',
          helperText: enabled ? null : 'Off',
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
    final saveBtn = FilledButton(
      onPressed: _busy || !changed ? null : () => _saveCleanupDays(t),
      child: const Text('Save'),
    );
    final runBtn = OutlinedButton(
      onPressed: _busy || !enabled || changed ? null : () => _runCleanup(task: t),
      child: const Text('Run now'),
    );
    if (MediaQuery.sizeOf(context).width < kNarrowWidth) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            info,
            const SizedBox(height: 8),
            field,
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [saveBtn, runBtn]),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: info),
          const SizedBox(width: 16),
          field,
          const SizedBox(width: 8),
          saveBtn,
          const SizedBox(width: 4),
          runBtn,
        ],
      ),
    );
  }

  Widget _cacheRow(Map<String, dynamic> c, ColorScheme scheme) {
    final name = c['name'].toString();
    final loaded = c['loadedAt'] != null
        ? _dtFmt.format(DateTime.parse(c['loadedAt'].toString()).toLocal())
        : 'not loaded';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(c['description']?.toString() ?? '',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                Text('${fmtCount(c['entries'])} entries  ·  loaded: $loaded',
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy || c['canClear'] != true
                ? null
                : () => _cacheAction('clear', name: name, done: '$name cleared.'),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: _busy || c['canSave'] != true
                ? null
                : () => _cacheAction('save', name: name, done: '$name saved.'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
