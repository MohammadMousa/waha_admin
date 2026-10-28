import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_state.dart';
import 'error_dialog.dart';

/// Lists the live login sessions of one account (an employee, or the signed-in
/// user's own) and lets the admin end them. Rows come from the backend with a
/// `ref` (never the token), `info` (os / model / browser), `storeName`,
/// `appVersion`, `createdAt`, `lastSeenAt`, `latest`, and `current` on own lists.
///
/// [deleteMany] null hides the checkboxes (the own-sessions API has no bulk
/// delete). [signOutAll] is the bulk "end everything" action; for the own list
/// it keeps the current session.
class AccountSessionsDialog extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function(String token) load;
  final Future<void> Function(String ref, String token) deleteOne;
  final Future<int> Function(List<String> refs, String token)? deleteMany;
  final Future<int> Function(String token) signOutAll;
  final String signOutLabel;
  final String signOutQuestion;
  final String disconnectNote;

  const AccountSessionsDialog({
    super.key,
    required this.title,
    required this.load,
    required this.deleteOne,
    this.deleteMany,
    required this.signOutAll,
    this.signOutLabel = 'Sign Out All',
    required this.signOutQuestion,
    this.disconnectNote = 'That session will be signed out and need to log in again.',
  });

  @override
  State<AccountSessionsDialog> createState() => _AccountSessionsDialogState();
}

class _AccountSessionsDialogState extends State<AccountSessionsDialog> {
  List<Map<String, dynamic>>? _sessions;
  bool _busy = false;
  final Set<String> _selected = {};

  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final items = await widget.load(token);
      // This session first, then the live one, then most recently active.
      int rank(Map<String, dynamic> s) =>
          s['current'] == true ? 0 : (s['latest'] == true ? 1 : 2);
      items.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final aLs = a['lastSeenAt']?.toString();
        final bLs = b['lastSeenAt']?.toString();
        if (aLs == null && bLs == null) return 0;
        if (aLs == null) return 1;
        if (bLs == null) return -1;
        return bLs.compareTo(aLs);
      });
      if (mounted) {
        setState(() {
          _sessions = items;
          _selected.retainWhere((ref) => items.any((s) => s['ref'].toString() == ref));
        });
      }
    } on ApiException catch (e) {
      if (mounted) { Navigator.of(context).pop(); showErrorDialogLater(context, e.message); }
    } catch (e) {
      if (mounted) { Navigator.of(context).pop(); showErrorDialogLater(context, e.toString()); }
    }
  }

  Future<bool> _confirm(String title, String text, String action, {bool danger = true}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// Runs one write call with the busy flag, then reloads the list.
  Future<void> _run(Future<void> Function(String token) call) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await call(token);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _disconnect(String ref) async {
    if (!await _confirm('Disconnect session?', widget.disconnectNote, 'Disconnect')) return;
    await _run((t) => widget.deleteOne(ref, t));
  }

  Future<void> _disconnectSelected() async {
    final refs = _selected.toList();
    if (!await _confirm('Disconnect selected sessions?',
        'Disconnect ${refs.length} session(s)? ${widget.disconnectNote}', 'Disconnect')) {
      return;
    }
    await _run((t) async {
      final n = await widget.deleteMany!(refs, t);
      if (mounted) _toast('Disconnected $n session(s).');
      _selected.clear();
    });
  }

  Future<void> _signOutAll() async {
    if (!await _confirm(widget.signOutLabel, widget.signOutQuestion, widget.signOutLabel,
        danger: false)) {
      return;
    }
    await _run((t) async {
      final n = await widget.signOutAll(t);
      if (mounted) _toast(n > 0 ? 'Signed out $n session(s).' : 'No other active sessions.');
    });
  }

  /// "Windows 11 · Chrome", "Pixel 7 · Android 14"; null info shows a dash.
  static String _infoText(dynamic info) {
    if (info is! Map) return '—';
    String f(String k) => (info[k] ?? '').toString().trim();
    final os = [f('os'), f('osVersion')].where((p) => p.isNotEmpty).join(' ');
    final parts = [f('model'), os, f('browser')].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.7).clamp(500.0, 900.0);
    final dialogHeight = (MediaQuery.of(context).size.height * 0.6).clamp(260.0, 520.0);
    final bulk = widget.deleteMany != null;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        child: _sessions == null
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : _sessions!.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('No active sessions.'))
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: dialogHeight),
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: dialogWidth),
                          child: DataTable(
                            columnSpacing: 16,
                            columns: [
                              if (bulk)
                                DataColumn(
                                  label: Checkbox(
                                    value: _selected.isNotEmpty &&
                                        _selected.length == _sessions!.length,
                                    tristate: true,
                                    onChanged: _busy
                                        ? null
                                        : (_) => setState(() {
                                              if (_selected.length == _sessions!.length) {
                                                _selected.clear();
                                              } else {
                                                _selected
                                                  ..clear()
                                                  ..addAll(_sessions!.map((s) => s['ref'].toString()));
                                              }
                                            }),
                                  ),
                                ),
                              const DataColumn(label: Text('')),
                              const DataColumn(label: Text('Device')),
                              const DataColumn(label: Text('Store')),
                              const DataColumn(label: Text('App Version')),
                              const DataColumn(label: Text('Created')),
                              const DataColumn(label: Text('Last Seen')),
                              const DataColumn(label: Text('')),
                            ],
                            rows: _sessions!.map((s) {
                              final ref = s['ref'].toString();
                              final isCurrent = s['current'] == true;
                              final created = s['createdAt'] != null
                                  ? _dtFmt.format(DateTime.parse(s['createdAt'].toString()).toLocal())
                                  : '—';
                              final lastSeen = s['lastSeenAt'] != null
                                  ? _dtFmt.format(DateTime.parse(s['lastSeenAt'].toString()).toLocal())
                                  : 'Never used';
                              return DataRow(cells: [
                                if (bulk)
                                  DataCell(Checkbox(
                                    value: _selected.contains(ref),
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(() {
                                              if (v == true) {
                                                _selected.add(ref);
                                              } else {
                                                _selected.remove(ref);
                                              }
                                            }),
                                  )),
                                DataCell(isCurrent
                                    ? const _Badge('This session', Colors.green)
                                    : s['latest'] == true
                                        ? const _Badge('Latest', Colors.blue)
                                        : const SizedBox.shrink()),
                                DataCell(Text(_infoText(s['info']))),
                                DataCell(Text(s['storeName']?.toString() ?? '—')),
                                DataCell(Text(s['appVersion']?.toString() ?? '—')),
                                DataCell(Text(created)),
                                DataCell(Text(lastSeen)),
                                // Ending the session you are using is what Sign Out is for.
                                DataCell(isCurrent
                                    ? const SizedBox.shrink()
                                    : IconButton(
                                        icon: Icon(Icons.link_off, size: 18, color: scheme.error),
                                        tooltip: 'Disconnect',
                                        onPressed: _busy ? null : () => _disconnect(ref),
                                      )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
      actions: [
        if (bulk)
          TextButton.icon(
            onPressed: _busy || _selected.isEmpty ? null : _disconnectSelected,
            icon: const Icon(Icons.link_off, size: 16),
            label: Text('Disconnect Selected${_selected.isEmpty ? '' : ' (${_selected.length})'}'),
          ),
        TextButton.icon(
          onPressed: _busy || (_sessions?.isEmpty ?? true) ? null : _signOutAll,
          icon: const Icon(Icons.logout, size: 16),
          label: Text(widget.signOutLabel),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}
