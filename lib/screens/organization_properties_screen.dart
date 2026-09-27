import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/framed_card.dart';

/// Lets an org owner view/create/edit/delete their own organization's
/// system_properties rows (e.g. default_language, check_landing_page_
/// interval_minutes). Known keys get a validated control; anything else is a
/// free-form key/value the admin is responsible for — backend applies no
/// validation to those.
class OrganizationPropertiesScreen extends StatefulWidget {
  const OrganizationPropertiesScreen({super.key});

  @override
  State<OrganizationPropertiesScreen> createState() => _OrganizationPropertiesScreenState();
}

class _OrganizationPropertiesScreenState extends State<OrganizationPropertiesScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _knownKeys = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _token => context.read<AuthState>().token;

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) { _redirectLogin(); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiClient().getOrganizationProperties(token),
        ApiClient().getOrganizationPropertyKeys(token),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0];
        _knownKeys = results[1];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Map<String, dynamic>? _knownFor(String key) =>
      _knownKeys.where((k) => k['key'] == key).firstOrNull;

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final token = _token;
    if (token == null) return;
    final result = await showPropertyEditorDialog(
      context,
      knownKeys: _knownKeys,
      existingKeys: _items.map((i) => i['key'].toString()).toSet(),
      editing: existing,
    );
    if (result == null || !mounted) return;
    try {
      await ApiClient().putOrganizationProperties(token, {result.$1: result.$2});
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) await showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) await showErrorDialog(context, 'Save failed: $e');
    }
  }

  Future<void> _delete(String key) async {
    final token = _token;
    if (token == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$key"?'),
        content: const Text('This removes the property for your organization. It cannot be undone.'),
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
    if (ok != true || !mounted) return;
    try {
      await ApiClient().deleteOrganizationProperty(token, key);
      if (mounted) _load();
    } on ApiException catch (e) {
      if (mounted) await showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) await showErrorDialog(context, 'Delete failed: $e');
    }
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
          const AdminSidebar(currentRoute: Routes.organizationProperties),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Organization Settings',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Property'),
                        onPressed: () => _addOrEdit(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? Center(child: Text('No organization properties set',
                              style: TextStyle(color: scheme.outline)))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(24, 4, 24, 100),
                                itemCount: _items.length,
                                itemBuilder: (_, i) {
                                  final item = _items[i];
                                  final key = item['key'].toString();
                                  final known = _knownFor(key);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: FramedCard(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(children: [
                                                  Text(key,
                                                      style: const TextStyle(
                                                          fontWeight: FontWeight.w600, fontSize: 14)),
                                                  if (known == null) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 6, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: scheme.tertiaryContainer,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text('custom',
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              color: scheme.onTertiaryContainer)),
                                                    ),
                                                  ],
                                                ]),
                                                const SizedBox(height: 2),
                                                Text('${item['value']}',
                                                    style: TextStyle(
                                                        fontSize: 13, color: scheme.primary,
                                                        fontWeight: FontWeight.w600)),
                                                if ((item['description'] ?? known?['description']) != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Text(
                                                        '${item['description'] ?? known?['description']}',
                                                        style: TextStyle(
                                                            fontSize: 12, color: scheme.outline)),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 20),
                                            tooltip: 'Edit',
                                            onPressed: () => _addOrEdit(existing: item),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                                            tooltip: 'Delete',
                                            onPressed: () => _delete(key),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
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

// ── Add/Edit dialog ──────────────────────────────────────────────────────────

/// Returns (key, value) to save, or null if cancelled.
Future<(String, String)?> showPropertyEditorDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> knownKeys,
  required Set<String> existingKeys,
  Map<String, dynamic>? editing,
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (_) => _PropertyEditorDialog(
      knownKeys: knownKeys,
      existingKeys: existingKeys,
      editing: editing,
    ),
  );
}

class _PropertyEditorDialog extends StatefulWidget {
  final List<Map<String, dynamic>> knownKeys;
  final Set<String> existingKeys;
  final Map<String, dynamic>? editing;
  const _PropertyEditorDialog(
      {required this.knownKeys, required this.existingKeys, this.editing});

  @override
  State<_PropertyEditorDialog> createState() => _PropertyEditorDialogState();
}

class _PropertyEditorDialogState extends State<_PropertyEditorDialog> {
  String? _selectedKnownKey; // null = "Custom key…" chosen (only when creating)
  bool _customKey = false;
  final _customKeyCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  String _language = 'ar';
  String? _error;

  bool get _isEditing => widget.editing != null;

  Map<String, dynamic>? get _known {
    final key = _isEditing ? widget.editing!['key'].toString() : _selectedKnownKey;
    if (key == null) return null;
    return widget.knownKeys.where((k) => k['key'] == key).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final key = widget.editing!['key'].toString();
      final value = widget.editing!['value']?.toString() ?? '';
      _customKey = widget.knownKeys.every((k) => k['key'] != key);
      _selectedKnownKey = _customKey ? null : key;
      _customKeyCtrl.text = key;
      _valueCtrl.text = value;
      if (key == 'default_language' && (value.toLowerCase() == 'ar' || value.toLowerCase() == 'en')) {
        _language = value.toLowerCase();
      }
    } else {
      // Default to the first not-yet-set known key, if any; otherwise custom.
      final available = widget.knownKeys
          .where((k) => !widget.existingKeys.contains(k['key']))
          .toList();
      if (available.isNotEmpty) {
        _selectedKnownKey = available.first['key'].toString();
      } else {
        _customKey = true;
      }
    }
  }

  @override
  void dispose() {
    _customKeyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  String get _effectiveKey => _customKey ? _customKeyCtrl.text.trim() : (_selectedKnownKey ?? '');

  Widget _valueField() {
    final known = _known;
    if (!_customKey && known?['key'] == 'default_language') {
      return DropdownButtonFormField<String>(
        value: _language,
        decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder(), isDense: true),
        items: const [
          DropdownMenuItem(value: 'ar', child: Text('ar — Arabic')),
          DropdownMenuItem(value: 'en', child: Text('en — English')),
        ],
        onChanged: (v) => setState(() => _language = v ?? 'ar'),
      );
    }
    if (!_customKey && known?['key'] == 'check_landing_page_interval_minutes') {
      return TextField(
        controller: _valueCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Value (minutes)',
          hintText: '1–1440',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );
    }
    return TextField(
      controller: _valueCtrl,
      decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder(), isDense: true),
    );
  }

  void _save() {
    final key = _effectiveKey;
    if (key.isEmpty) {
      setState(() => _error = 'Key is required.');
      return;
    }
    final known = _known;
    final value = (!_customKey && known?['key'] == 'default_language')
        ? _language
        : _valueCtrl.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Value is required.');
      return;
    }
    Navigator.pop(context, (key, value));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final availableKnown =
        widget.knownKeys.where((k) => !widget.existingKeys.contains(k['key'])).toList();
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Property' : 'Add Property'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isEditing)
              InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Key', border: OutlineInputBorder(), isDense: true, filled: true),
                child: Text(widget.editing!['key'].toString()),
              )
            else ...[
              if (availableKnown.isNotEmpty && !_customKey)
                DropdownButtonFormField<String>(
                  value: _selectedKnownKey,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Key', border: OutlineInputBorder(), isDense: true),
                  items: availableKnown
                      .map((k) => DropdownMenuItem(
                          value: k['key'].toString(), child: Text(k['key'].toString())))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedKnownKey = v),
                )
              else
                TextField(
                  controller: _customKeyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Key', border: OutlineInputBorder(), isDense: true),
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _customKey = !_customKey),
                  icon: Icon(_customKey ? Icons.list : Icons.edit_outlined, size: 16),
                  label: Text(_customKey ? 'Choose a known key' : 'Custom key…'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _valueField(),
            if (_customKey) ...[
              const SizedBox(height: 8),
              Text(
                'Custom properties are not validated by the server — you are responsible for the key and value being correct.',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ] else if (_known?['constraints'] != null) ...[
              const SizedBox(height: 8),
              Text('${_known!['constraints']}', style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
