import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/reset_pin_dialog.dart';
import '../widgets/error_dialog.dart';
import '../widgets/framed_card.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Device>? _devices;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _redirectLogin(); return; }
    try {
      final list = await ApiClient().getDevices(token);
      if (!mounted) return;
      setState(() { _devices = list; _loading = false; });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _toggleEnabled(Device d) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      await ApiClient().patchDevice(d.id, {'enabled': !d.enabled}, token: token);
      _load();
    } on ApiException catch (err) {
      if (mounted) showErrorDialog(context, err.message);
    }
  }

  Future<void> _resetPin(Device d) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final newPin = await showResetPinDialog(context, name: d.displayName);
    if (newPin == null || !mounted) return;
    try {
      await ApiClient().patchDevice(d.id, {'pinCode': newPin}, token: token);
      _load();
    } on ApiException catch (err) {
      if (mounted) showErrorDialog(context, err.message);
    }
  }

  Future<void> _signOut(Device d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out device?'),
        content: Text('Sign out "${d.displayName}"? It will need to log in again on its next action.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final n = await ApiClient().signOutDevice(d.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(n > 0 ? 'Device signed out.' : 'Device had no active session.')),
        );
      }
    } on ApiException catch (err) {
      if (mounted) showErrorDialog(context, err.message);
    }
  }

  Future<void> _showSessions(Device d) async {
    await showDialog<void>(context: context, builder: (_) => _DeviceSessionsDialog(device: d));
  }

  Future<void> _delete(Device d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete device?'),
        content: Text('Delete "${d.displayName}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      await ApiClient().deleteDevice(d.id, token: token);
      _load();
    } on ApiException catch (err) {
      if (mounted) showErrorDialog(context, err.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.devices),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Devices',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.add_to_queue_outlined, size: 18),
                        label: const Text('New Device'),
                        onPressed: () => Navigator.of(context)
                            .pushNamed(Routes.deviceEdit, arguments: null)
                            .then((_) => _load()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_error!, style: TextStyle(color: scheme.error)),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _load, child: const Text('Retry')),
                            ]))
                          : _devices == null || _devices!.isEmpty
                              ? const Center(child: Text('No devices found.'))
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: CardGrid(
                                    itemCount: _devices!.length,
                                    itemBuilder: (_, i) => _DeviceCard(
                                      device: _devices![i],
                                      onEdit: () => Navigator.of(context)
                                          .pushNamed(Routes.deviceEdit, arguments: _devices![i])
                                          .then((_) => _load()),
                                      onToggle: () => _toggleEnabled(_devices![i]),
                                      onResetPin: () => _resetPin(_devices![i]),
                                      onSessions: () => _showSessions(_devices![i]),
                                      onSignOut: () => _signOut(_devices![i]),
                                      onDelete: () => _delete(_devices![i]),
                                      )
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
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onResetPin;
  final VoidCallback onSessions;
  final VoidCallback onSignOut;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    required this.onEdit,
    required this.onToggle,
    required this.onResetPin,
    required this.onSessions,
    required this.onSignOut,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = device;
    return FramedCard(
      child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
              child: const Icon(Icons.tv_outlined, color: Colors.deepPurple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(d.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    _Badge(d.deviceType, Colors.deepPurple),
                    if (!d.enabled) ...[
                        _Badge('Disabled', Colors.grey),
                    ],
                    if (d.isLocked) ...[
                        _Badge(
                          'Locked until ${DateFormat('h:mm a').format(d.lockedUntil!.toLocal())}',
                          Colors.red),
                    ],
                  ]),
                  if (d.displayName != d.username) ...[
                    const SizedBox(height: 2),
                    Text('@${d.username}', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, children: [
                    if (d.storeName != null)
                      Text(d.storeName!, style: TextStyle(fontSize: 12, color: scheme.outline)),
                    if (d.deviceKey != null)
                      Text('Key: ${d.deviceKey}', style: TextStyle(fontSize: 11, color: scheme.outline)),
                  ]),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'toggle') onToggle();
                if (v == 'resetPin') onResetPin();
                if (v == 'sessions') onSessions();
                if (v == 'signOut') onSignOut();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'toggle', child: Text(d.enabled ? 'Disable' : 'Enable')),
                const PopupMenuItem(value: 'resetPin', child: Text('Reset PIN')),
                const PopupMenuItem(value: 'sessions', child: Text('Sessions')),
                const PopupMenuItem(value: 'signOut', child: Text('Sign Out')),
                const PopupMenuItem(value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );
}

// ── Sessions popup ───────────────────────────────────────────────────────────

class _DeviceSessionsDialog extends StatefulWidget {
  final Device device;
  const _DeviceSessionsDialog({required this.device});

  @override
  State<_DeviceSessionsDialog> createState() => _DeviceSessionsDialogState();
}

class _DeviceSessionsDialogState extends State<_DeviceSessionsDialog> {
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
      final items = await ApiClient().getDeviceSessions(widget.device.id, token: token);
      // Live session first, then most recently active; never-used sessions last.
      items.sort((a, b) {
        final aLatest = a['latest'] == true;
        final bLatest = b['latest'] == true;
        if (aLatest != bLatest) return aLatest ? -1 : 1;
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

  Future<void> _disconnect(String ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect session?'),
        content: const Text('That kiosk will get signed out and need to log in again on its next action.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await ApiClient().deleteDeviceSession(widget.device.id, ref, token: token);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectSelected() async {
    final refs = _selected.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect selected sessions?'),
        content: Text('Disconnect ${refs.length} session(s)? Those kiosks will get signed out and need to log in again on their next action.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final n = await ApiClient().deleteDeviceSessions(widget.device.id, refs, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disconnected $n session(s).')),
        );
      }
      _selected.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out all sessions?'),
        content: Text('Sign out "${widget.device.displayName}" everywhere? It will need to log in again on its next action.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out All')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final n = await ApiClient().signOutDevice(widget.device.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(n > 0 ? 'Signed out $n session(s).' : 'No active session.')),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.7).clamp(500.0, 820.0);
    final dialogHeight = (MediaQuery.of(context).size.height * 0.6).clamp(260.0, 520.0);
    return AlertDialog(
      title: Text('Sessions — ${widget.device.displayName}'),
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
                              DataColumn(
                                label: Checkbox(
                                  value: _selected.isNotEmpty && _selected.length == _sessions!.length,
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
                              const DataColumn(label: Text('Store')),
                              const DataColumn(label: Text('App Version')),
                              const DataColumn(label: Text('Created')),
                              const DataColumn(label: Text('Last Seen')),
                              const DataColumn(label: Text('')),
                            ],
                            rows: _sessions!.map((s) {
                              final isLatest = s['latest'] == true;
                              final created = s['createdAt'] != null
                                  ? _dtFmt.format(DateTime.parse(s['createdAt'].toString()).toLocal())
                                  : '—';
                              final lastSeen = s['lastSeenAt'] != null
                                  ? _dtFmt.format(DateTime.parse(s['lastSeenAt'].toString()).toLocal())
                                  : 'Never used';
                              final ref = s['ref'].toString();
                              return DataRow(cells: [
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
                                DataCell(isLatest ? const _Badge('Current', Colors.green) : const SizedBox.shrink()),
                                DataCell(Text(s['storeName']?.toString() ?? '—')),
                                DataCell(Text(s['appVersion']?.toString() ?? '—')),
                                DataCell(Text(created)),
                                DataCell(Text(lastSeen)),
                                DataCell(IconButton(
                                  icon: const Icon(Icons.link_off, size: 18),
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
        TextButton.icon(
          onPressed: _busy || _selected.isEmpty ? null : _disconnectSelected,
          icon: const Icon(Icons.link_off, size: 16),
          label: Text('Disconnect Selected${_selected.isEmpty ? '' : ' (${_selected.length})'}'),
        ),
        TextButton.icon(
          onPressed: _busy || (_sessions?.isEmpty ?? true) ? null : _signOutAll,
          icon: const Icon(Icons.logout, size: 16),
          label: const Text('Sign Out All'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
