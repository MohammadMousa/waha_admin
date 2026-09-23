import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/reset_pin_dialog.dart';

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
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
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 100),
                                    itemCount: _devices!.length,
                                    itemBuilder: (_, i) => _DeviceCard(
                                      device: _devices![i],
                                      onEdit: () => Navigator.of(context)
                                          .pushNamed(Routes.deviceEdit, arguments: _devices![i])
                                          .then((_) => _load()),
                                      onToggle: () => _toggleEnabled(_devices![i]),
                                      onResetPin: () => _resetPin(_devices![i]),
                                      onDelete: () => _delete(_devices![i]),
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
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onResetPin;
  final VoidCallback onDelete;

  const _DeviceCard({
    required this.device,
    required this.onEdit,
    required this.onToggle,
    required this.onResetPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = device;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                  Row(children: [
                    Text(d.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(width: 8),
                    _Badge(d.deviceType, Colors.deepPurple),
                    if (!d.enabled) ...[
                      const SizedBox(width: 6),
                      _Badge('Disabled', Colors.grey),
                    ],
                    if (d.isLocked) ...[
                      const SizedBox(width: 6),
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
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'toggle', child: Text(d.enabled ? 'Disable' : 'Enable')),
                const PopupMenuItem(value: 'resetPin', child: Text('Reset PIN')),
                const PopupMenuItem(value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
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
