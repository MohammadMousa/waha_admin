// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/resource_scope.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';

class LandingPagesScreen extends StatefulWidget {
  const LandingPagesScreen({super.key});

  @override
  State<LandingPagesScreen> createState() => _LandingPagesScreenState();
}

class _LandingPagesScreenState extends State<LandingPagesScreen> {
  List<Store>? _stores;
  Store? _selectedStore;
  Map<String, Map<String, dynamic>?> _pageStatus = {};
  bool _loadingStores = true;
  bool _loadingPages = false;
  // Custom labels (renamed pages — session-only)
  final Map<String, String> _customLabels = {};

  static const _pageKeys = [
    'KIOSK_LANDING',
    'SHOPPING_LANDING',
    'CLIENT_LANDING',
    'ADMIN_LANDING',
  ];

  static const _pageLabels = {
    'KIOSK_LANDING':    'Kiosk Landing',
    'SHOPPING_LANDING': 'Shopping Landing',
    'CLIENT_LANDING':   'Client Landing',
    'ADMIN_LANDING':    'Admin Landing',
  };

  static const _pageIcons = {
    'KIOSK_LANDING':    Icons.point_of_sale_outlined,
    'SHOPPING_LANDING': Icons.shopping_bag_outlined,
    'CLIENT_LANDING':   Icons.phone_android_outlined,
    'ADMIN_LANDING':    Icons.admin_panel_settings_outlined,
  };

  static const _pageColors = {
    'KIOSK_LANDING':    Color(0xFF5C6BC0),
    'SHOPPING_LANDING': Color(0xFF26A69A),
    'CLIENT_LANDING':   Color(0xFFEF7C4F),
    'ADMIN_LANDING':    Color(0xFF7E57C2),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initStores());
  }

  Future<void> _initStores() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _logout(); return; }
    try {
      final stores = await ApiClient().getAdminStores(token);
      if (!mounted) return;
      setState(() { _stores = stores; _loadingStores = false; });
      // Load pages for global scope by default (no branch selected)
      _loadPages();
    } on ApiException catch (e) {
      if (e.statusCode == 401) _logout();
      if (mounted) setState(() => _loadingStores = false);
    }
  }

  String? get _orgSlug => _stores?.firstOrNull?.orgSlug;

  // Public URL prefix — '{org}' for global (no branch selected), '{org}/{branch}' otherwise.
  String get _resourceBase =>
      _orgSlug == null ? '' : resourceBaseFor(_orgSlug!, _selectedStore?.name);

  void _selectStore(Store? store) {
    setState(() => _selectedStore = store);
    _loadPages();
  }

  Future<void> _loadPages() async {
    setState(() { _pageStatus = {}; _loadingPages = true; });
    final token = context.read<AuthState>().token!;
    // Pass the explicit store ID so the backend scope matches the dropdown
    // selection. null (no branch selected) means "global" — the backend
    // resolves the org straight from the caller's own session.
    final scopeStoreId = _selectedStore?.id;
    final results = await Future.wait(
      _pageKeys.map((key) => ApiClient()
          .getLandingPage(key, token, storeId: scopeStoreId)
          .then<MapEntry<String, Map<String, dynamic>?>>((r) => MapEntry(key, r))
          .catchError((_) => MapEntry(key, null))),
    );
    if (!mounted) return;
    setState(() {
      _pageStatus = Map.fromEntries(results);
      _loadingPages = false;
    });
  }

  void _previewPage(String key) {
    final url = '${AppConfig.apiBaseUrl}/resource/$_resourceBase/pages/$key.html';
    html.window.open(url, '_blank', 'width=450,height=800,resizable=yes');
  }

  Future<void> _renamePage(String key) async {
    final current = _customLabels[key] ?? _pageLabels[key]!;
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename page'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), labelText: 'Display name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _customLabels[key] = result);
    }
  }

  Future<void> _duplicatePage(String key) async {
    final org = _orgSlug;
    if (org == null) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final url = '${AppConfig.apiBaseUrl}/resource/$_resourceBase/pages/$key.html';
      final resp = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        showErrorDialog(context, 'No content to duplicate');
        return;
      }
      final copyKey = '${key}_COPY';
      final copyFilename = '$copyKey.html';
      final apiScope = apiScopeFor(org, _selectedStore?.name);
      // Heal any embedded /resource/... references saved under a stale
      // org/store identifier before propagating them into the copy.
      final healedHtml = utf8.decode(resp.bodyBytes).replaceAllMapped(
        RegExp(r'''((?:src|href)\s*=\s*["'])([^"']+)(["'])'''),
        (m) => '${m[1]}${healResourceUrl(m[2]!, _resourceBase)}${m[3]}',
      );
      await ApiClient().uploadAsset(
          apiScope, 'pages', utf8.encode(healedHtml), copyFilename, 'text/html', token,
          nameOverride: copyFilename);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicated as ${_customLabels[key] ?? _pageLabels[key]!} copy')));
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'Duplicate failed: $e');
      }
    }
  }

  void _logout() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.landingPages),
          Expanded(child: _buildContent(scheme)),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    if (_loadingStores) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(scheme),
        Expanded(child: _buildGrid(scheme)),
      ],
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Landing Pages',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_loadingPages)
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 14),
          if (_stores != null && _stores!.isNotEmpty)
            _BranchDropdown(
              stores: _stores!,
              selected: _selectedStore,
              onSelect: (s) => _selectStore(s),
            ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildGrid(ColorScheme scheme) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 260,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _pageKeys.length,
      itemBuilder: (_, i) {
        final key = _pageKeys[i];
        final info = _pageStatus[key];
        final isConfigured = info != null;
        final isLocal = info?['scope'] == 'local';

        return _LandingPageCard(
          label: _customLabels[key] ?? _pageLabels[key]!,
          icon: _pageIcons[key]!,
          color: _pageColors[key]!,
          configured: isConfigured,
          local: isLocal,
          loading: _loadingPages,
          storeName: _selectedStore?.label() ?? 'Global',
          onEdit: () {
            // Local page → edit on the selected branch. Global page (or no
            // branch selected) → edit at the organization level (store: null).
            final editorStore = isLocal ? _selectedStore : null;
            Navigator.of(context)
                .pushNamed(Routes.landingEditor, arguments: {
                  'store': editorStore,
                  'orgSlug': _orgSlug,
                  'pageKey': key,
                })
                .then((_) => _loadPages());
          },
          onPreview: () => _previewPage(key),
          onRename: () => _renamePage(key),
          onDuplicate: () => _duplicatePage(key),
        );
      },
    );
  }
}

class _BranchDropdown extends StatelessWidget {
  final List<Store> stores;
  final Store? selected;
  final ValueChanged<Store?> onSelect;
  const _BranchDropdown({required this.stores, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Store?>(
          value: selected,
          isDense: true,
          style: TextStyle(fontSize: 13, color: scheme.onSurface),
          items: [
            DropdownMenuItem<Store?>(
              value: null,
              child: Text('Select Branch',
                  style: TextStyle(fontSize: 13, color: scheme.outline)),
            ),
            ...stores.map((s) => DropdownMenuItem<Store?>(
              value: s,
              child: Text(s.label()),
            )),
          ],
          onChanged: onSelect,
        ),
      ),
    );
  }
}

class _LandingPageCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool configured;
  final bool local;
  final bool loading;
  final String storeName;
  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;

  const _LandingPageCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.configured,
    required this.local,
    required this.loading,
    required this.storeName,
    required this.onEdit,
    required this.onPreview,
    required this.onRename,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview area — browser mockup
          Expanded(
            child: Container(
              color: color.withValues(alpha: 0.08),
              child: Stack(
                children: [
                  // Subtle grid pattern
                  CustomPaint(painter: _GridPainter(color.withValues(alpha: 0.06))),
                  // Page icon centred
                  Center(
                    child: AnimatedOpacity(
                      opacity: loading ? 0.4 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 34, color: color),
                      ),
                    ),
                  ),
                  // Status badge
                  Positioned(
                    top: 10,
                    right: 10,
                    child: loading
                        ? const SizedBox.shrink()
                        : _StatusBadge(configured: configured, local: local),
                  ),
                ],
              ),
            ),
          ),
          // Info + action row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.store_outlined, size: 12,
                              color: scheme.outline),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(storeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: scheme.outline)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  onPressed: onEdit,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'preview',
                        child: ListTile(dense: true, leading: Icon(Icons.preview_outlined),
                            title: Text('Preview'))),
                    const PopupMenuItem(value: 'duplicate',
                        child: ListTile(dense: true, leading: Icon(Icons.copy_outlined),
                            title: Text('Duplicate'))),
                    const PopupMenuItem(value: 'rename',
                        child: ListTile(dense: true, leading: Icon(Icons.drive_file_rename_outline),
                            title: Text('Rename'))),
                  ],
                  onSelected: (v) {
                    if (v == 'preview')   onPreview();
                    if (v == 'duplicate') onDuplicate();
                    if (v == 'rename')    onRename();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool configured;
  final bool local;
  const _StatusBadge({required this.configured, required this.local});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!configured) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text('Default',
            style: TextStyle(fontSize: 10, color: scheme.outline,
                fontWeight: FontWeight.w600)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: local ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(local ? 'Custom' : 'Global',
          style: const TextStyle(fontSize: 10, color: Colors.white,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}
