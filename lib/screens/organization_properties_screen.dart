import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/framed_card.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/waha_pagination_bar.dart';

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

class _OrganizationPropertiesScreenState extends State<OrganizationPropertiesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _group;
  int _sortCol = 0;
  bool _sortAsc = true;
  int _page = 0;
  int _pageSize = 25;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _knownKeys = [];
  Map<String, dynamic>? _orgInfo;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
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
        ApiClient().getOrganizationInfo(token),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<Map<String, dynamic>>;
        _knownKeys = _withLocalKeys(results[1] as List<Map<String, dynamic>>);
        _orgInfo = results[2] as Map<String, dynamic>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Keys the kiosk reads but the backend does not list yet, so the editor still
  /// offers them as proper controls instead of free text.
  static List<Map<String, dynamic>> _withLocalKeys(List<Map<String, dynamic>> keys) => [
        ...keys,
        if (keys.every((k) => k['key'] != 'Log_Level'))
          {
            'key': 'Log_Level',
            'type': 'string',
            'description': 'How much the kiosk app logs.',
            'constraints': 'Info, Warn or Error. Default: Warn.',
          },
      ];

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

  Future<void> _editOrgField(String field) async {
    final token = _token;
    if (token == null || _orgInfo == null) return;
    final result = await showOrgFieldEditorDialog(context, field: field, info: _orgInfo!);
    if (result == null || !mounted) return;
    try {
      final updated = await ApiClient().patchOrganizationInfo(token, {field: result});
      if (mounted) setState(() => _orgInfo = updated);
    } on ApiException catch (e) {
      if (mounted) await showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) await showErrorDialog(context, 'Save failed: $e');
    }
  }

  List<Widget> _orgInfoRows(ColorScheme scheme) {
    final info = _orgInfo!;
    final vat = info['vatRate'];
    final vatLabel = vat == null ? 'Not set' : '${((vat as num) * 100).toStringAsFixed(2)}%';
    Widget row(String label, String value, String field) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FramedCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                      const SizedBox(height: 2),
                      Text(value,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit',
                  onPressed: () => _editOrgField(field),
                ),
              ],
            ),
          ),
        );
    return [
      row('Name', '${info['name'] ?? '—'}', 'name'),
      row('Slug', '${info['slug'] ?? '—'}', 'slug'),
      row('Currency', '${info['currency'] ?? '—'}', 'currency'),
      row('VAT Rate', vatLabel, 'vatRate'),
    ];
  }

  static const _groups = ['Offline & sync', 'Custom'];

  bool _inGroup(String key, bool known, String group) {
    if (group == 'Custom') return !known;
    return key.startsWith('offline_') ||
        key.startsWith('sync_') ||
        key.startsWith('scan_') ||
        key.startsWith('resource_cache_') ||
        key == 'push_paid_orders_only';
  }

  /// One row per property with the strings the grid shows and searches.
  List<Map<String, dynamic>> _rows() {
    final rows = _items.map((item) {
      final key = item['key'].toString();
      final known = _knownFor(key);
      final desc = (item['description'] ?? known?['description'])?.toString() ?? '';
      final def = known?['default'];
      return <String, dynamic>{
        'item': item,
        'key': key,
        'known': known != null,
        'value': '${item['value'] ?? ''}',
        'desc': desc,
        'default': def == null ? '' : '$def',
      };
    }).where((r) {
      if (_group != null && !_inGroup(r['key'] as String, r['known'] as bool, _group!)) return false;
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (r['key'] as String).toLowerCase().contains(q) ||
          (r['value'] as String).toLowerCase().contains(q) ||
          (r['desc'] as String).toLowerCase().contains(q);
    }).toList();
    const keys = ['key', 'value', 'desc', 'default'];
    final k = keys[_sortCol];
    rows.sort((a, b) {
      final c = (a[k] as String).toLowerCase().compareTo((b[k] as String).toLowerCase());
      return _sortAsc ? c : -c;
    });
    return rows;
  }

  DataColumn _col(String label, int i) => DataColumn(
        label: wahaSortableLabel(context, label, active: _sortCol == i, asc: _sortAsc),
        onSort: (c, a) => setState(() {
          if (_sortCol == c) {
            _sortAsc = !_sortAsc;
          } else {
            _sortCol = c;
            _sortAsc = true;
          }
        }),
      );

  Widget _cell(String text, double width, {TextStyle? style}) => SizedBox(
        width: width,
        child: Tooltip(
          message: text,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(text.isEmpty ? '—' : text,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
        ),
      );

  Widget _propertiesTab(ColorScheme scheme) {
    final all = _rows();
    final lastPage = all.isEmpty ? 0 : (all.length - 1) ~/ _pageSize;
    final page = _page > lastPage ? lastPage : _page;
    final rows = all.skip(page * _pageSize).take(_pageSize).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WahaSearchField(
                controller: _searchCtrl,
                hintText: 'Search properties',
                width: 260,
                onSubmitted: () => setState(() { _search = _searchCtrl.text; _page = 0; }),
                onClear: () => setState(() { _search = ''; _page = 0; }),
                onChanged: (v) => setState(() { _search = v; _page = 0; }),
              ),
              WahaFilterDropdown<String?>(
                value: _group,
                hint: 'All properties',
                items: [
                  const DropdownMenuItem(value: null, child: Text('All properties')),
                  ..._groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                ],
                onChanged: (v) => setState(() { _group = v; _page = 0; }),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Property'),
                onPressed: () => _addOrEdit(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                              _items.isEmpty
                                  ? 'No organization properties set'
                                  : 'No properties match',
                              style: TextStyle(color: scheme.outline)))
                      : LayoutBuilder(
                          builder: (_, c) {
                            final w = c.maxWidth;
                            final valueW = (w * 0.2).clamp(120.0, 320.0);
                            final descW = (w * 0.33).clamp(180.0, 520.0);
                            final defW = (w * 0.1).clamp(70.0, 160.0);
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: w),
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    columnSpacing: 24,
                                    horizontalMargin: 20,
                                    headingRowColor:
                                        WidgetStatePropertyAll(scheme.surfaceContainerHighest),
                                    dataRowMinHeight: 44,
                                    dataRowMaxHeight: 60,
                                    columns: [
                                      _col('Name', 0),
                                      _col('Value', 1),
                                      _col('Description', 2),
                                      _col('Default', 3),
                                      const DataColumn(
                                          label: Text('', style: TextStyle(fontWeight: FontWeight.w600))),
                                    ],
                                    rows: rows.map((r) {
                                      final key = r['key'] as String;
                                      return DataRow(cells: [
                                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                          Text(key,
                                              style: const TextStyle(fontWeight: FontWeight.w600)),
                                          if (r['known'] == false) ...[
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
                                        ])),
                                        DataCell(_cell(r['value'] as String, valueW,
                                            style: TextStyle(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w600))),
                                        DataCell(_cell(r['desc'] as String, descW,
                                            style: TextStyle(
                                                fontSize: 12, color: scheme.onSurfaceVariant))),
                                        DataCell(_cell(r['default'] as String, defW,
                                            style: TextStyle(
                                                fontSize: 12, color: scheme.onSurfaceVariant))),
                                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 20),
                                            tooltip: 'Edit',
                                            onPressed: () =>
                                                _addOrEdit(existing: r['item'] as Map<String, dynamic>),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete_outline,
                                                size: 20, color: scheme.error),
                                            tooltip: 'Delete',
                                            onPressed: () => _delete(key),
                                          ),
                                        ])),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        all.isEmpty
                            ? 'No entries'
                            : 'Showing ${page * _pageSize + 1}–${page * _pageSize + rows.length} of ${all.length} entries',
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      WahaPageSizeSelector(
                        value: _pageSize,
                        options: const [10, 25, 50, 100],
                        onChanged: (v) => setState(() { _pageSize = v; _page = 0; }),
                      ),
                      const SizedBox(width: 16),
                      WahaPaginationBar(
                        page: page,
                        totalCount: all.length,
                        pageSize: _pageSize,
                        onPage: (p) => setState(() => _page = p),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Text('Organization Settings',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: const [
                        Tab(text: 'Organization'),
                        Tab(text: 'Server Properties'),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            RefreshIndicator(
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
                                children: [if (_orgInfo != null) ..._orgInfoRows(scheme)],
                              ),
                            ),
                            _propertiesTab(scheme),
                          ],
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

// ── Organization field editor (name / slug / vatRate) ─────────────────────────

const Map<String, String> _orgFieldLabels = {
  'name': 'Organization Name',
  'slug': 'Organization Slug',
  'currency': 'Currency (ISO code)',
  'vatRate': 'VAT Rate (%)',
};

const Map<String, String> _orgFieldWarnings = {
  'slug': 'Changing the slug may break existing resource URLs and pages that '
      'use this organization\'s path.',
  'currency': 'Changing currency affects all stores and future orders.',
  'vatRate': 'Changing tax rate affects all stores and future Odoo pushes.',
};

/// Returns the new value to PATCH (a String for name/slug, a 0-1 decimal
/// fraction as a String for vatRate), or null if cancelled.
Future<dynamic> showOrgFieldEditorDialog(
  BuildContext context, {
  required String field,
  required Map<String, dynamic> info,
}) {
  final isVat = field == 'vatRate';
  final isCurrency = field == 'currency';
  final current = info[field];
  final ctrl = TextEditingController(
    text: isVat
        ? (current == null ? '' : ((current as num) * 100).toStringAsFixed(2))
        : (current?.toString() ?? ''),
  );
  String? error;
  return showDialog<dynamic>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        return AlertDialog(
          title: Text('Edit ${_orgFieldLabels[field] ?? field}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_orgFieldWarnings[field] != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: Theme.of(ctx).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_orgFieldWarnings[field]!,
                              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.error)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: isVat
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  textCapitalization:
                      isCurrency ? TextCapitalization.characters : TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: _orgFieldLabels[field] ?? field,
                    suffixText: isVat ? '%' : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final text = ctrl.text.trim();
                if (text.isEmpty) {
                  setSt(() => error = 'Required.');
                  return;
                }
                if (isVat) {
                  final pct = double.tryParse(text);
                  if (pct == null || pct < 0 || pct > 100) {
                    setSt(() => error = 'Enter a percent between 0 and 100.');
                    return;
                  }
                  Navigator.pop(ctx, pct / 100);
                } else if (isCurrency) {
                  Navigator.pop(ctx, text.toUpperCase());
                } else {
                  Navigator.pop(ctx, text);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
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
  // Keys with a true/false dropdown control.
  static const _boolKeys = {
    'auto_log_upload_enabled',
    'enable_logging',
    'device_auto_restart_enabled',
    'prices_exclude_vat',
  };
  // Keys with a numeric TextField + hint (integer).
  static const _intHints = {
    'check_landing_page_interval_minutes': '1–1440',
    'max_log_uploads_per_hour': 'e.g. 3',
    'log_harvest_seconds': 'e.g. 30',
    'heartbeat_minutes': '0–1440 (0 = device monitoring off)',
    'late_approval_expiration_minutes': '1–60',
    'device_auto_restart_wait_minutes': '1–60',
    'terminal_timeout_seconds': '10–80',
  };
  // Keys with a numeric TextField + hint (decimal).
  static const _decimalHints = {
    'device_auto_restart_hours': '0.25–168',
  };

  String? _selectedKnownKey; // null = "Custom key…" chosen (only when creating)
  bool _customKey = false;
  final _customKeyCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final Map<String, String> _dropdownValues = {
    'default_language': 'ar',
    'Log_Level': 'Warn',
    'offline_mode': 'off',
    for (final k in _boolKeys) k: 'false',
  };
  String? _error;
  final _keySearchCtrl = TextEditingController();
  String _keySearch = '';

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
        _dropdownValues['default_language'] = value.toLowerCase();
      } else if (key == 'offline_mode') {
        // Older values were true/false; "full" is the old true.
        final v = value.toLowerCase();
        _dropdownValues[key] = v == 'caching' ? 'caching' : (v == 'full' || v == 'true') ? 'full' : 'off';
      } else if (key == 'Log_Level') {
        // The kiosk accepts any case; show the stored value as one of the three.
        _dropdownValues[key] = const ['Info', 'Warn', 'Error']
                .where((l) => l.toLowerCase() == value.toLowerCase())
                .firstOrNull ??
            'Warn';
      } else if (_isBoolKey(key)) {
        _dropdownValues[key] = value.toLowerCase() == 'true' ? 'true' : 'false';
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
    _keySearchCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  /// Search box with a short scrollable list of the keys that are not set yet.
  Widget _keyPicker(List<Map<String, dynamic>> available, ColorScheme scheme) {
    final q = _keySearch.trim().toLowerCase();
    final matches = available.where((k) {
      if (q.isEmpty) return true;
      return k['key'].toString().toLowerCase().contains(q) ||
          (k['description']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _keySearchCtrl,
          autofocus: true,
          onChanged: (v) => setState(() {
            _keySearch = v;
            final q = v.trim().toLowerCase();
            final hits = available.where((k) =>
                q.isEmpty ||
                k['key'].toString().toLowerCase().contains(q) ||
                (k['description']?.toString().toLowerCase().contains(q) ?? false));
            // Keep the selection on something visible.
            if (!hits.any((k) => k['key'] == _selectedKnownKey)) {
              _selectedKnownKey = hits.isEmpty ? null : hits.first['key'].toString();
            }
          }),
          decoration: const InputDecoration(
            labelText: 'Key',
            hintText: 'Search keys, e.g. sync or offline',
            prefixIcon: Icon(Icons.search, size: 18),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 190,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: matches.isEmpty
              ? Center(
                  child: Text('No matching keys',
                      style: TextStyle(fontSize: 12, color: scheme.outline)))
              : ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (_, i) {
                    final k = matches[i]['key'].toString();
                    final selected = k == _selectedKnownKey;
                    return InkWell(
                      onTap: () => setState(() => _selectedKnownKey = k),
                      child: Container(
                        color: selected ? scheme.primaryContainer : null,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(k,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                                color: selected ? scheme.onPrimaryContainer : null)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Keys the server describes as true/false or whole numbers get the matching
  /// control even when this screen has no hard-coded entry for them.
  bool _isBoolKey(String key) =>
      _boolKeys.contains(key) ||
      widget.knownKeys.any((k) => k['key'] == key && k['type'] == 'boolean');
  bool _isIntKey(String key) =>
      _intHints.containsKey(key) ||
      widget.knownKeys.any((k) => k['key'] == key && (k['type'] == 'integer' || k['type'] == 'int'));

  String get _effectiveKey => _customKey ? _customKeyCtrl.text.trim() : (_selectedKnownKey ?? '');

  Widget _valueField() {
    final known = _known;
    final key = _customKey ? null : (known?['key'] as String?);
    if (key == 'default_language') {
      return DropdownButtonFormField<String>(
        value: _dropdownValues['default_language'],
        decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder(), isDense: true),
        items: const [
          DropdownMenuItem(value: 'ar', child: Text('ar — Arabic')),
          DropdownMenuItem(value: 'en', child: Text('en — English')),
        ],
        onChanged: (v) => setState(() => _dropdownValues['default_language'] = v ?? 'ar'),
      );
    }
    if (key == 'offline_mode') {
      return DropdownButtonFormField<String>(
        value: _dropdownValues['offline_mode'],
        decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder(), isDense: true),
        items: const [
          DropdownMenuItem(value: 'off', child: Text('off — online only (default)')),
          DropdownMenuItem(value: 'caching', child: Text('caching')),
          DropdownMenuItem(value: 'full', child: Text('full — sell offline and send orders later')),
        ],
        onChanged: (v) => setState(() => _dropdownValues['offline_mode'] = v ?? 'off'),
      );
    }
    if (key == 'Log_Level') {
      return DropdownButtonFormField<String>(
        value: _dropdownValues['Log_Level'],
        decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder(), isDense: true),
        items: const [
          DropdownMenuItem(value: 'Info', child: Text('Info — everything')),
          DropdownMenuItem(value: 'Warn', child: Text('Warn — warnings and errors (default)')),
          DropdownMenuItem(value: 'Error', child: Text('Error — errors only')),
        ],
        onChanged: (v) => setState(() => _dropdownValues['Log_Level'] = v ?? 'Warn'),
      );
    }
    if (key != null && _isBoolKey(key)) {
      return DropdownButtonFormField<String>(
        value: _dropdownValues[key] ?? 'false',
        decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder(), isDense: true),
        items: const [
          DropdownMenuItem(value: 'true', child: Text('true — Enabled')),
          DropdownMenuItem(value: 'false', child: Text('false — Disabled')),
        ],
        onChanged: (v) => setState(() => _dropdownValues[key] = v ?? 'false'),
      );
    }
    if (key != null && _isIntKey(key)) {
      return TextField(
        controller: _valueCtrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Value',
          hintText: _intHints[key],
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
    }
    if (key != null && _decimalHints.containsKey(key)) {
      return TextField(
        controller: _valueCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Value',
          hintText: _decimalHints[key],
          border: const OutlineInputBorder(),
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
    final knownKey = (!_customKey) ? (known?['key'] as String?) : null;
    final String value;
    if (knownKey == 'default_language') {
      value = _dropdownValues['default_language'] ?? 'ar';
    } else if (knownKey == 'Log_Level') {
      value = _dropdownValues['Log_Level'] ?? 'Warn';
    } else if (knownKey == 'offline_mode') {
      value = _dropdownValues['offline_mode'] ?? 'off';
    } else if (knownKey != null && _isBoolKey(knownKey)) {
      value = _dropdownValues[knownKey] ?? 'false';
    } else {
      value = _valueCtrl.text.trim();
    }
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
        width: 460,
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
                _keyPicker(availableKnown, scheme)
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
            ] else if (_known != null) ...[
              const SizedBox(height: 8),
              if (_known!['description'] != null)
                Text('${_known!['description']}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              if (_known!['constraints'] != null)
                Text('${_known!['constraints']}', style: TextStyle(fontSize: 12, color: scheme.outline)),
              if (_known!['default'] != null)
                Text('Default: ${_known!['default']}',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
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
