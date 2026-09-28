import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../utils/number_format.dart';
import '../widgets/error_dialog.dart';

class OdooAdminScreen extends StatefulWidget {
  const OdooAdminScreen({super.key});

  @override
  State<OdooAdminScreen> createState() => _OdooAdminScreenState();
}

class _OdooAdminScreenState extends State<OdooAdminScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _urlCtrl      = TextEditingController();
  final _keyCtrl      = TextEditingController();
  final _userCtrl     = TextEditingController();
  final _overrideCtrl = TextEditingController();

  bool _loading       = false;
  bool _configured    = false;
  bool _inherited     = false;
  int? _ownerStoreId;
  String? _baseUrl;
  String? _username;
  String? _customerOverride;
  String? _lastCatSync;
  String? _lastProdSync;
  Map<String, dynamic>? _queue;
  List<Map<String, dynamic>> _history = [];
  String? _error;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try { await _loadStatus(); }
      catch (e) { if (mounted) setState(() => _error = e.toString()); }
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _userCtrl.dispose();
    _overrideCtrl.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthState>().token;

  Future<void> _loadStatus() async {
    final token = _token;
    if (token == null) return;
    setState(() => _loading = true);
    try {
      final status = await ApiClient().odooStatus(token, storeId: 1);
      setState(() {
        _configured       = status['configured']    as bool?   ?? false;
        _inherited        = status['inherited']     as bool?   ?? false;
        _ownerStoreId     = status['ownerStoreId']  as int?;
        _baseUrl          = status['baseUrl']           as String?;
        _username         = status['username']          as String?;
        _customerOverride = status['customerOverride']  as String?;
        _lastCatSync      = status['lastCategorySyncAt'] as String?;
        _lastProdSync     = status['lastProductSyncAt']  as String?;
        _queue            = status['queue']  as Map<String, dynamic>?;
        if (_baseUrl          != null && _baseUrl!.isNotEmpty)          _urlCtrl.text      = _baseUrl!;
        if (_username         != null && _username!.isNotEmpty)         _userCtrl.text     = _username!;
        if (_customerOverride != null && _customerOverride!.isNotEmpty) _overrideCtrl.text = _customerOverride!;
      });
      final logs = await ApiClient().getIntegrationLogs(
          token, entityType: 'CATALOG_PULL', page: 0, size: 20);
      if (mounted) {
        setState(() => _history =
            (logs['items'] as List? ?? []).cast<Map<String, dynamic>>().map(_toHistory).toList());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      await ApiClient().oodooConfigure(
        token,
        _urlCtrl.text.trim(),
        _keyCtrl.text.trim(),
        _userCtrl.text.trim(),
        customerOverride: _overrideCtrl.text.trim(),
        storeId: 1,
      );
      _keyCtrl.clear();
      _userCtrl.clear();
      await _loadStatus();
      setState(() => _successMsg = 'Connection saved.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pullCategories() async {
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final count = await ApiClient().oodooPullCategories(token, storeId: 1);
      await _loadStatus();
      setState(() => _successMsg = count > 0
          ? 'Pulled $count categories from Odoo.'
          : 'Categories already up to date.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pullProducts() async {
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final (pulled, visible) = await ApiClient().oodooPullProducts(token, storeId: 1);
      await _loadStatus();
      if (pulled > 0) {
        setState(() => _successMsg = 'Pulled $pulled products from Odoo.');
      } else if (visible > 0) {
        setState(() => _successMsg = 'Already up to date. $visible products available.');
      } else {
        setState(() => _successMsg = 'Already up to date. No products in scope.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forcePullProducts() async {
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final result = await ApiClient().oodooForceFullPullProducts(token);
      await _loadStatus();
      final added = result['added'] ?? 0;
      final updated = result['updated'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      setState(() => _successMsg = '${fmtCount(added)} added, ${fmtCount(updated)} updated, ${fmtCount(skipped)} skipped.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pushOrders() async {
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final count = await ApiClient().oodooPushOrders(token, storeId: 1);
      await _loadStatus();
      setState(() => _successMsg = count > 0
          ? 'Pushed $count order(s) to Odoo.'
          : 'No pending orders to push.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    if (_successMsg != null) {
      final msg = _successMsg!;
      _successMsg = null;
      // A toast anchored to the Scaffold, not a banner buried wherever this
      // section happens to scroll to — was appearing off-screen from the
      // button (e.g. Push Now, far down the page) that triggered it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      });
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.odooAdmin),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    children: [
                      Text('Odoo Integration',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_outlined),
                        tooltip: 'Refresh',
                        onPressed: _loading ? null : _loadStatus,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading && !_configured
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _loadStatus,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            children: [
                  _StatusCard(
                    configured: _configured,
                    inherited: _inherited,
                    ownerStoreId: _ownerStoreId,
                    baseUrl: _baseUrl,
                  ),
                  const SizedBox(height: 20),



                  if (!_inherited) ...[
                    Text('Connection', style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _urlCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Odoo Base URL',
                              hintText: 'https://mycompany.odoo.com',
                              prefixIcon: Icon(Icons.link),
                            ),
                            keyboardType: TextInputType.url,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _userCtrl,
                            decoration: InputDecoration(
                              labelText: _configured
                                  ? 'Odoo Username (leave blank to keep current)'
                                  : 'Odoo Username',
                              hintText: 'admin@mycompany.com',
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (!_configured && (v == null || v.trim().isEmpty)) return 'Required';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _keyCtrl,
                            decoration: InputDecoration(
                              labelText: _configured
                                  ? 'API Key (leave blank to keep current)'
                                  : 'API Key',
                              prefixIcon: const Icon(Icons.key),
                            ),
                            obscureText: true,
                            validator: (v) {
                              if (!_configured && (v == null || v.trim().isEmpty)) return 'Required';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _overrideCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Customer Name (Override, optional)',
                              hintText: 'e.g. oasis.kiosks',
                              prefixIcon: Icon(Icons.person_pin_outlined),
                              helperText: 'All orders use this Odoo customer instead of device/user identity.',
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: _loading
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save_outlined),
                              label: const Text('Save Connection'),
                              onPressed: _loading ? null : _save,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text('Catalog Sync', style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Pulls data from Odoo into Waha. Incremental after first run.',
                        style: TextStyle(color: scheme.outline, fontSize: 13)),
                    const SizedBox(height: 12),
                    _SyncRow(
                      label: 'Categories',
                      icon: Icons.category_outlined,
                      lastSync: _lastCatSync,
                      enabled: _configured && !_loading,
                      onPull: _pullCategories,
                    ),
                    const SizedBox(height: 10),
                    _SyncRow(
                      label: 'Products',
                      icon: Icons.inventory_2_outlined,
                      lastSync: _lastProdSync,
                      enabled: _configured && !_loading,
                      onPull: _pullProducts,
                      onForcePull: _forcePullProducts,
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    _SyncHistorySection(history: _history),
                  ],

                  if (_queue != null) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Order Sync Queue',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        FilledButton.icon(
                          icon: _loading
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.upload_outlined, size: 18),
                          label: const Text('Push Now'),
                          onPressed: _configured && !_loading && (_queue?['ready'] ?? 0) > 0
                              ? _pushOrders : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _QueueStats(queue: _queue!),
                  ],
                  const SizedBox(height: 32),
                ],
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool configured;
  final bool inherited;
  final int? ownerStoreId;
  final String? baseUrl;
  const _StatusCard({required this.configured, required this.inherited,
                     this.ownerStoreId, this.baseUrl});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bgColor = !configured
        ? scheme.surfaceContainerHighest
        : inherited ? Colors.blue.shade50 : Colors.green.shade50;
    final Color iconColor = !configured
        ? scheme.outline
        : inherited ? Colors.blue.shade700 : Colors.green.shade700;
    final String title = !configured
        ? 'Not configured'
        : inherited ? 'Inherited from store $ownerStoreId' : 'Connected';
    final String? subtitle = inherited
        ? 'Push orders only. Switch to the owner store to configure or pull catalog.'
        : (baseUrl != null && baseUrl!.isNotEmpty ? baseUrl : null);
    final IconData icon = !configured
        ? Icons.radio_button_unchecked
        : inherited ? Icons.link_outlined : Icons.check_circle_outline;

    return Card(
      elevation: 0,
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: iconColor)),
                  if (subtitle != null)
                    Text(subtitle, style: TextStyle(fontSize: 12, color: scheme.outline)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? lastSync;
  final bool enabled;
  final VoidCallback onPull;
  final VoidCallback? onForcePull;
  const _SyncRow({required this.label, required this.icon, this.lastSync,
                   required this.enabled, required this.onPull, this.onForcePull});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    lastSync != null ? 'Last sync: ${_fmtTs(lastSync!)}' : 'Never synced',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ),
            ),
            if (onForcePull != null) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepOrange,
                  side: const BorderSide(color: Colors.deepOrange),
                ),
                onPressed: enabled ? onForcePull : null,
                child: const Text('Force Full Pull'),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton(
              onPressed: enabled ? onPull : null,
              child: const Text('Pull'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTs(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) { return iso; }
  }
  String _p(int n) => n.toString().padLeft(2, '0');
}

class _QueueStats extends StatelessWidget {
  final Map<String, dynamic> queue;
  const _QueueStats({required this.queue});
  @override
  Widget build(BuildContext context) {
    final pending = (queue['pending'] as num?)?.toInt() ?? 0;
    final ready = (queue['ready'] as num?)?.toInt() ?? 0;
    // "Pending" alone was confusing next to Push Now finding nothing to do —
    // a PENDING row can still be inside its retry backoff window. Show both.
    return Row(
      children: [
        _Chip(
          label: pending > 0 ? 'Pending (${fmtCount(ready)} ready)' : 'Pending',
          value: fmtCount(pending),
          color: Colors.orange,
        ),
        const SizedBox(width: 8),
        _Chip(label: 'Failed', value: fmtCount(queue['failed'] ?? 0), color: Colors.red),
        const SizedBox(width: 8),
        _Chip(label: 'Done', value: fmtCount(queue['done'] ?? 0), color: Colors.green),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Chip({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ]),
    ),
  );
}

// ── Automatic pull + history ──────────────────────────────────────────────────

String _fmtLocal(dynamic iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso.toString()).toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  } catch (_) {
    return iso.toString();
  }
}

// A CATALOG_PULL row of GET /api/admin/integrations/logs -> the fields the
// history UI shows. payload = {triggeredBy, categoriesPulled, productsPulled};
// created_at has no zone (server time is UTC).
Map<String, dynamic> _toHistory(Map<String, dynamic> r) {
  var payload = r['payload'];
  if (payload is String) {
    try { payload = jsonDecode(payload); } catch (_) { payload = null; }
  }
  final p = payload is Map ? payload : const {};
  String? utc(dynamic v) {
    if (v == null) return null;
    final t = v.toString();
    return RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(t) ? t : '${t}Z';
  }
  return {
    'triggeredBy': p['triggeredBy'],
    'startedAt': utc(r['created_at']),
    'categoriesPulled': p['categoriesPulled'] ?? 0,
    'productsPulled': p['productsPulled'] ?? 0,
    'status': r['status'],
    'errorMessage': r['last_error'],
  };
}

class _SyncHistorySection extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _SyncHistorySection({required this.history});

  Color _statusColor(String? s) => switch (s) {
        'DONE' => Colors.green.shade700,
        'FAILED' => Colors.red.shade700,
        _ => Colors.orange.shade700,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = history.isEmpty ? null : history.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Automatic pull', style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
            'Categories and products are pulled automatically every day at 06:00 KSA.',
            style: TextStyle(color: scheme.outline, fontSize: 13)),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: last == null
                ? Text('No sync requests yet.', style: TextStyle(color: scheme.outline))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last sync request: ${_fmtLocal(last['startedAt'])} '
                          '(${last['triggeredBy'] == 'SCHEDULED' ? 'scheduled' : 'manual'}, '
                          '${(last['status'] ?? '').toString().toLowerCase()})',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Pulled: ${fmtCount(last['categoriesPulled'])} categories, '
                          '${fmtCount(last['productsPulled'])} products',
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                      if ((last['errorMessage'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${last['errorMessage']}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: last['status'] == 'FAILED'
                                      ? scheme.error
                                      : scheme.onSurfaceVariant)),
                        ),
                    ],
                  ),
          ),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Sync history', style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                columns: const [
                  DataColumn(label: Text('Started', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Trigger', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(numeric: true, label: Text('Categories', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(numeric: true, label: Text('Products', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600))),
                  DataColumn(label: Text('Details', style: TextStyle(fontWeight: FontWeight.w600))),
                ],
                rows: history.map((r) => DataRow(cells: [
                      DataCell(Text(_fmtLocal(r['startedAt']))),
                      DataCell(Text(r['triggeredBy'] == 'SCHEDULED' ? 'Scheduled' : 'Manual')),
                      DataCell(Text(fmtCount(r['categoriesPulled']))),
                      DataCell(Text(fmtCount(r['productsPulled']))),
                      DataCell(Text('${r['status'] ?? ''}',
                          style: TextStyle(
                              color: _statusColor(r['status']?.toString()),
                              fontWeight: FontWeight.w600))),
                      DataCell(SizedBox(
                        width: 260,
                        child: Tooltip(
                          message: '${r['errorMessage'] ?? ''}',
                          child: Text('${r['errorMessage'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: r['status'] == 'FAILED'
                                      ? scheme.error
                                      : scheme.onSurfaceVariant)),
                        ),
                      )),
                    ])).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
