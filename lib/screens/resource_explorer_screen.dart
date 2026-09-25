// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/resource.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/resource_scope.dart';
import '../widgets/admin_sidebar.dart';
import 'package:provider/provider.dart';
import '../widgets/error_dialog.dart';

enum _AssetLayout { list, listThumb, grid }
enum _PreviewLayout { fullscreen, fitHeight, fitWidth }

class ResourceExplorerScreen extends StatefulWidget {
  /// null = organization-level (global) scope.
  final Store? store;
  const ResourceExplorerScreen({super.key, this.store});

  @override
  State<ResourceExplorerScreen> createState() => _ResourceExplorerScreenState();
}

class _ResourceExplorerScreenState extends State<ResourceExplorerScreen> {
  List<ResourceDirectory> _dirs = [];
  ResourceDirectory? _selectedDir;
  List<ResourceAsset> _assets = [];
  bool _loadingDirs = false;
  bool _loadingAssets = false;
  String? _error;

  final Map<int, _AssetLayout> _layoutPrefs = {};
  _AssetLayout get _layout => _layoutPrefs[_selectedDir?.id] ?? _AssetLayout.list;

  // Last directory + scroll position, per scope — so reopening Files Manager
  // lands back where the user left it instead of resetting every time
  // (human lead, 2026-09-17).
  final ScrollController _scrollController = ScrollController();

  // Only needed when widget.store == null (global scope) — a real store
  // already carries its own orgSlug.
  String? _fetchedOrgSlug;
  String get _orgSlug => widget.store?.orgSlug ?? _fetchedOrgSlug ?? '';

  String get _storeSlug => apiScopeFor(_orgSlug, widget.store?.name);
  String get _resourceBase => resourceBaseFor(_orgSlug, widget.store?.name);

  @override
  void initState() {
    super.initState();
    if (widget.store == null) {
      _loadOrgSlugThenDirs();
    } else {
      _loadDirs();
    }
  }

  @override
  void dispose() {
    _saveScrollOffset();
    _scrollController.dispose();
    super.dispose();
  }

  String get _token => context.read<AuthState>().token ?? '';

  Future<String?> _getLastDir() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('filesManager.lastDir.$_storeSlug');
  }

  Future<void> _setLastDir(String dirName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('filesManager.lastDir.$_storeSlug', dirName);
  }

  String _scrollKey(int dirId) => 'filesManager.scrollOffset.$_storeSlug.$dirId.${_layout.name}';

  void _saveScrollOffset() {
    final dir = _selectedDir;
    if (dir == null || !_scrollController.hasClients) return;
    SharedPreferences.getInstance()
        .then((p) => p.setDouble(_scrollKey(dir.id), _scrollController.offset));
  }

  Future<void> _restoreScrollOffset(int dirId) async {
    final prefs = await SharedPreferences.getInstance();
    final offset = prefs.getDouble(_scrollKey(dirId));
    if (offset == null || offset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController
            .jumpTo(offset.clamp(0, _scrollController.position.maxScrollExtent));
      }
    });
  }

  Future<void> _loadOrgSlugThenDirs() async {
    try {
      final stores = await ApiClient().getAdminStores(_token);
      _fetchedOrgSlug = stores.firstOrNull?.orgSlug;
    } catch (_) { /* falls through to _loadDirs, which will surface the error */ }
    if (mounted) await _loadDirs();
  }

  Future<void> _loadDirs() async {
    setState(() { _loadingDirs = true; _error = null; });
    try {
      final dirs = await ApiClient().getDirectories(_storeSlug, _token);
      if (!mounted) return;
      setState(() { _dirs = dirs; _loadingDirs = false; });
      if (_selectedDir != null) {
        final still = dirs.where((d) => d.id == _selectedDir!.id);
        if (still.isNotEmpty) {
          _selectedDir = still.first;
        } else {
          _selectedDir = null;
          _assets = [];
        }
      } else {
        // First load — jump straight back to wherever the user left off,
        // instead of leaving nothing selected.
        final lastDirName = await _getLastDir();
        if (!mounted || lastDirName == null) return;
        final match = dirs.where((d) => d.name == lastDirName);
        if (match.isNotEmpty) await _selectDir(match.first);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingDirs = false; });
    }
  }

  Future<void> _selectDir(ResourceDirectory dir) async {
    _saveScrollOffset();
    setState(() { _selectedDir = dir; _loadingAssets = true; _assets = []; });
    _setLastDir(dir.name);
    try {
      final assets = await ApiClient().getAssets(_storeSlug, dir.name, _token);
      if (!mounted) return;
      setState(() { _assets = assets; _loadingAssets = false; });
      await _restoreScrollOffset(dir.id);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingAssets = false; });
    }
  }

  Future<void> _createDir() async {
    final name = await _showNameDialog(context, title: 'New Directory',
        hint: 'e.g. landing, products');
    if (name == null || name.isEmpty) return;
    try {
      await ApiClient().createDirectory(_storeSlug, name, _token);
      await _loadDirs();
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'Failed: $e');
      }
    }
  }

  Future<void> _upload() async {
    final dir = _selectedDir;
    if (dir == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final mimeType = _guessMime(file.name);
    setState(() => _loadingAssets = true);
    try {
      await ApiClient().uploadAsset(
          _storeSlug, dir.name, file.bytes!, file.name, mimeType, _token);
      if (mounted) await _selectDir(dir);
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAssets = false);
        showErrorDialog(context, 'Upload failed: $e');
      }
    }
  }

  Future<void> _uploadMultiple() async {
    final dir = _selectedDir;
    if (dir == null) return;
    final result = await FilePicker.platform.pickFiles(
        allowMultiple: true, withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _loadingAssets = true);
    final api = ApiClient();
    int uploaded = 0;
    for (final file in result.files) {
      if (file.bytes == null) continue;
      try {
        await api.uploadAsset(
            _storeSlug, dir.name, file.bytes!, file.name, _guessMime(file.name), _token);
        uploaded++;
      } catch (_) {}
    }
    if (mounted) {
      await _selectDir(dir);
      if (uploaded < result.files.length) {
        showErrorDialog(context, 'Uploaded $uploaded/${result.files.length} files - some uploads failed.');
      }
    }
  }

  Future<void> _rename(ResourceAsset asset) async {
    final dir = _selectedDir;
    if (dir == null) return;
    final newName = await _showNameDialog(context, title: 'Rename', hint: asset.name);
    if (newName == null || newName.isEmpty || newName == asset.name) return;
    try {
      await ApiClient().renameAsset(_storeSlug, dir.name, asset.name, newName, _token);
      if (mounted) await _selectDir(dir);
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Rename failed: $e');
    }
  }

  Future<void> _move(ResourceAsset asset) async {
    final dir = _selectedDir;
    if (dir == null) return;
    if (_dirs.length < 2) {
      showErrorDialog(context, 'No other directories to move to');
      return;
    }
    final targets = _dirs.where((d) => d.id != dir.id).toList();
    final picked = await showDialog<ResourceDirectory>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Move to directory'),
        children: [
          for (final d in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, d),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(d.name), dense: true),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient().moveAsset(_storeSlug, dir.name, asset.name, picked.name, _token);
      if (mounted) {
        await _selectDir(dir);
        messenger.showSnackBar(
          SnackBar(content: Text('Moved "${asset.name}" to ${picked.name}')));
      }
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Move failed: $e');
    }
  }

  Future<void> _delete(ResourceAsset asset) async {
    final dir = _selectedDir;
    if (dir == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete asset?'),
        content: Text('Delete "${asset.name}" from ${dir.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient().deleteAsset(_storeSlug, dir.name, asset.name, _token);
      if (mounted) await _selectDir(dir);
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'Delete failed: $e');
      }
    }
  }

  void _previewKiosk(ResourceAsset asset) {
    final dir = _selectedDir;
    if (dir == null) return;
    final url = '${AppConfig.apiBaseUrl}${asset.publicUrl(_resourceBase, dir.name)}';
    html.window.open(url, '_blank', 'width=450,height=800,resizable=yes');
  }

  Future<void> _duplicateAsset(ResourceAsset asset) async {
    final dir = _selectedDir;
    if (dir == null) return;
    final url = '${AppConfig.apiBaseUrl}${asset.publicUrl(_resourceBase, dir.name)}';
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resp = await http.get(Uri.parse(url)); // public resource
      if (resp.statusCode != 200) {
        showErrorDialog(context, 'Could not fetch file to duplicate');
        return;
      }
      final parts = asset.name.split('.');
      final ext  = parts.length > 1 ? '.${parts.last}' : '';
      final base = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : asset.name;
      final copyName = '${base}_COPY$ext';
      await ApiClient().uploadAsset(_storeSlug, dir.name, resp.bodyBytes, copyName, asset.mimeType, _token);
      if (mounted) {
        await _selectDir(dir);
        messenger.showSnackBar(SnackBar(content: Text('Duplicated as $copyName')));
      }
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Duplicate failed: $e');
    }
  }

  void _copyUrl(ResourceAsset asset) {
    final dir = _selectedDir;
    if (dir == null) return;
    final url = asset.publicUrl(_resourceBase, dir.name);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $url')));
  }

  void _setLayout(_AssetLayout layout) {
    final dir = _selectedDir;
    if (dir == null) return;
    setState(() => _layoutPrefs[dir.id] = layout);
  }

  // Determine which sidebar route to highlight
  String get _currentRoute => widget.store == null
      ? Routes.resourceExplorerGlobal
      : Routes.resourceExplorer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final body = _error != null && _dirs.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadDirs, child: const Text('Retry')),
          ]))
        : Row(children: [
            SizedBox(width: 220, child: _DirectoryPanel(
              dirs: _dirs, selected: _selectedDir,
              loading: _loadingDirs, onSelect: _selectDir, onNew: _createDir,
            )),
            const VerticalDivider(width: 1),
            Expanded(child: _AssetPanel(
              dir: _selectedDir, assets: _assets, loading: _loadingAssets,
              onUpload: _upload, onUploadMultiple: _uploadMultiple,
              onDelete: _delete, onCopyUrl: _copyUrl, onMove: _move, onRename: _rename,
              onPreviewKiosk: _previewKiosk, onDuplicate: _duplicateAsset,
              resourceBase: _resourceBase, layout: _layout, onLayoutChange: _setLayout,
              scrollController: _scrollController, onScrollEnd: _saveScrollOffset,
            )),
          ]);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          AdminSidebar(currentRoute: _currentRoute),
          Expanded(
            child: Column(
              children: [
                // Header bar
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Files Manager',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(widget.store?.label() ?? 'Global',
                                style: TextStyle(fontSize: 13, color: scheme.outline)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_outlined),
                        tooltip: 'Refresh',
                        onPressed: () async {
                          await _loadDirs();
                          if (_selectedDir != null) await _selectDir(_selectedDir!);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Directory panel ────────────────────────────────────────────────────────────

class _DirectoryPanel extends StatelessWidget {
  final List<ResourceDirectory> dirs;
  final ResourceDirectory? selected;
  final bool loading;
  final ValueChanged<ResourceDirectory> onSelect;
  final VoidCallback onNew;

  const _DirectoryPanel({
    required this.dirs, required this.selected, required this.loading,
    required this.onSelect, required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : dirs.isEmpty
                  ? Center(child: Text('No directories yet',
                      style: TextStyle(color: scheme.outline)))
                  : ListView.builder(
                      itemCount: dirs.length,
                      itemBuilder: (_, i) {
                        final d = dirs[i];
                        final isSelected = selected?.id == d.id;
                        return ListTile(
                          leading: Icon(Icons.folder_outlined,
                              color: isSelected ? scheme.primary : scheme.outline),
                          title: Text(d.name),
                          selected: isSelected,
                          selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.3),
                          onTap: () => onSelect(d),
                        );
                      },
                    ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.create_new_folder_outlined, color: scheme.primary),
          title: const Text('New Directory'),
          onTap: onNew,
        ),
      ],
    );
  }
}

// ── Asset panel ────────────────────────────────────────────────────────────────

class _AssetPanel extends StatelessWidget {
  final ResourceDirectory? dir;
  final List<ResourceAsset> assets;
  final bool loading;
  final VoidCallback onUpload;
  final VoidCallback onUploadMultiple;
  final ValueChanged<ResourceAsset> onDelete;
  final ValueChanged<ResourceAsset> onCopyUrl;
  final ValueChanged<ResourceAsset> onMove;
  final ValueChanged<ResourceAsset> onRename;
  final ValueChanged<ResourceAsset> onPreviewKiosk;
  final ValueChanged<ResourceAsset> onDuplicate;
  final String resourceBase;
  final _AssetLayout layout;
  final ValueChanged<_AssetLayout> onLayoutChange;
  final ScrollController scrollController;
  final VoidCallback onScrollEnd;

  const _AssetPanel({
    required this.dir, required this.assets, required this.loading,
    required this.onUpload, required this.onUploadMultiple,
    required this.onDelete, required this.onCopyUrl, required this.onMove,
    required this.onRename, required this.onPreviewKiosk, required this.onDuplicate,
    required this.resourceBase, required this.layout, required this.onLayoutChange,
    required this.scrollController, required this.onScrollEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (dir == null) {
      return Center(child: Text('Select a directory',
          style: TextStyle(color: scheme.outline)));
    }

    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(
            children: [
              _LayoutToggle(current: layout, onChange: onLayoutChange),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.upload_file_outlined, size: 20),
                tooltip: 'Upload file',
                visualDensity: VisualDensity.compact,
                color: scheme.primary,
                onPressed: onUpload,
              ),
              IconButton(
                icon: const Icon(Icons.drive_folder_upload_outlined, size: 20),
                tooltip: 'Upload multiple files',
                visualDensity: VisualDensity.compact,
                color: scheme.primary,
                onPressed: onUploadMultiple,
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : assets.isEmpty
                  ? Center(child: Text('No files in ${dir!.name}',
                      style: TextStyle(color: scheme.outline)))
                  : NotificationListener<ScrollEndNotification>(
                      onNotification: (_) {
                        onScrollEnd();
                        return false;
                      },
                      child: switch (layout) {
                        _AssetLayout.list      => _buildList(context),
                        _AssetLayout.listThumb => _buildListThumb(context),
                        _AssetLayout.grid      => _buildGrid(context),
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) => ListView.builder(
    controller: scrollController,
    itemCount: assets.length,
    itemBuilder: (_, i) => _AssetRow(
      asset: assets[i], dir: dir!, resourceBase: resourceBase, showThumb: false,
      onDelete: () => onDelete(assets[i]),
      onCopyUrl: () => onCopyUrl(assets[i]),
      onMove: () => onMove(assets[i]),
      onRename: () => onRename(assets[i]),
      onPreviewKiosk: () => onPreviewKiosk(assets[i]),
      onDuplicate: () => onDuplicate(assets[i]),
    ),
  );

  Widget _buildListThumb(BuildContext context) => ListView.builder(
    controller: scrollController,
    itemCount: assets.length,
    itemBuilder: (_, i) => _AssetRow(
      asset: assets[i], dir: dir!, resourceBase: resourceBase, showThumb: true,
      onDelete: () => onDelete(assets[i]),
      onCopyUrl: () => onCopyUrl(assets[i]),
      onMove: () => onMove(assets[i]),
      onRename: () => onRename(assets[i]),
      onPreviewKiosk: () => onPreviewKiosk(assets[i]),
      onDuplicate: () => onDuplicate(assets[i]),
    ),
  );

  Widget _buildGrid(BuildContext context) => GridView.builder(
    controller: scrollController,
    padding: const EdgeInsets.all(12),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 160,
      mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82,
    ),
    itemCount: assets.length,
    itemBuilder: (_, i) => _AssetCard(
      asset: assets[i], dir: dir!, resourceBase: resourceBase,
      onDelete: () => onDelete(assets[i]),
      onCopyUrl: () => onCopyUrl(assets[i]),
      onMove: () => onMove(assets[i]),
      onRename: () => onRename(assets[i]),
      onPreviewKiosk: () => onPreviewKiosk(assets[i]),
      onDuplicate: () => onDuplicate(assets[i]),
    ),
  );
}

class _LayoutToggle extends StatelessWidget {
  final _AssetLayout current;
  final ValueChanged<_AssetLayout> onChange;
  const _LayoutToggle({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) => SegmentedButton<_AssetLayout>(
    style: SegmentedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero, iconSize: 16,
    ),
    segments: const [
      ButtonSegment(value: _AssetLayout.list,      icon: Icon(Icons.view_list_outlined)),
      ButtonSegment(value: _AssetLayout.listThumb, icon: Icon(Icons.view_agenda_outlined)),
      ButtonSegment(value: _AssetLayout.grid,      icon: Icon(Icons.grid_view_outlined)),
    ],
    selected: {current},
    onSelectionChanged: (s) => onChange(s.first),
    showSelectedIcon: false,
  );
}

// ── Asset row ─────────────────────────────────────────────────────────────────

class _AssetRow extends StatelessWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String resourceBase;
  final bool showThumb;
  final VoidCallback onDelete;
  final VoidCallback onCopyUrl;
  final VoidCallback onMove;
  final VoidCallback onRename;
  final VoidCallback onPreviewKiosk;
  final VoidCallback onDuplicate;

  const _AssetRow({
    required this.asset, required this.dir, required this.resourceBase,
    required this.showThumb, required this.onDelete, required this.onCopyUrl,
    required this.onMove, required this.onRename,
    required this.onPreviewKiosk, required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget leading = showThumb
        ? _AssetThumb(asset: asset, resourceBase: resourceBase, dirName: dir.name, size: 52)
        : Icon(_typeIcon(asset), color: scheme.primary, size: 22);

    return ListTile(
      leading: leading,
      title: Text(asset.name, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_fmtSize(asset.sizeBytes)} · ${asset.mimeType}',
          style: TextStyle(color: scheme.outline, fontSize: 11)),
      trailing: _AssetMenu(
        asset: asset, dir: dir, resourceBase: resourceBase,
        onCopyUrl: onCopyUrl, onMove: onMove, onRename: onRename, onDelete: onDelete,
        onPreviewKiosk: onPreviewKiosk, onDuplicate: onDuplicate,
      ),
      onTap: () => _openPreview(context, asset, dir, resourceBase),
    );
  }
}

// ── Asset card (grid) ─────────────────────────────────────────────────────────

class _AssetCard extends StatelessWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String resourceBase;
  final VoidCallback onDelete;
  final VoidCallback onCopyUrl;
  final VoidCallback onMove;
  final VoidCallback onRename;
  final VoidCallback onPreviewKiosk;
  final VoidCallback onDuplicate;

  const _AssetCard({
    required this.asset, required this.dir, required this.resourceBase,
    required this.onDelete, required this.onCopyUrl, required this.onMove,
    required this.onRename, required this.onPreviewKiosk, required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openPreview(context, asset, dir, resourceBase),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: Container(
                color: scheme.surfaceContainerHighest,
                child: _AssetThumb(
                  asset: asset, resourceBase: resourceBase, dirName: dir.name,
                  size: 140, fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(asset.name, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                ),
                _AssetMenu(
                  asset: asset, dir: dir, resourceBase: resourceBase, compact: true,
                  onCopyUrl: onCopyUrl, onMove: onMove, onRename: onRename, onDelete: onDelete,
                  onPreviewKiosk: onPreviewKiosk, onDuplicate: onDuplicate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Asset popup menu ──────────────────────────────────────────────────────────

enum _AssetAction { view, previewKiosk, copyUrl, move, rename, duplicate, delete }

class _AssetMenu extends StatelessWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String resourceBase;
  final VoidCallback onCopyUrl;
  final VoidCallback onMove;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onPreviewKiosk;
  final VoidCallback onDuplicate;
  final bool compact;

  const _AssetMenu({
    required this.asset, required this.dir, required this.resourceBase,
    required this.onCopyUrl, required this.onMove,
    required this.onRename, required this.onDelete,
    required this.onPreviewKiosk, required this.onDuplicate,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconSize = compact ? 16.0 : 18.0;
    return PopupMenuButton<_AssetAction>(
      icon: Icon(Icons.more_vert, size: iconSize, color: scheme.outline),
      padding: EdgeInsets.zero,
      itemBuilder: (_) => [
        if (asset.isHtml)
          const PopupMenuItem(
            value: _AssetAction.view,
            child: ListTile(
              leading: Icon(Icons.open_in_browser_outlined),
              title: Text('Open in new tab'), dense: true,
            ),
          ),
        if (asset.isHtml)
          const PopupMenuItem(
            value: _AssetAction.previewKiosk,
            child: ListTile(
              leading: Icon(Icons.stay_current_portrait_outlined),
              title: Text('Preview as kiosk'), dense: true,
            ),
          ),
        const PopupMenuItem(
          value: _AssetAction.copyUrl,
          child: ListTile(
            leading: Icon(Icons.copy_outlined),
            title: Text('Copy URL'), dense: true,
          ),
        ),
        const PopupMenuItem(
          value: _AssetAction.rename,
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Rename'), dense: true,
          ),
        ),
        const PopupMenuItem(
          value: _AssetAction.move,
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outlined),
            title: Text('Move'), dense: true,
          ),
        ),
        const PopupMenuItem(
          value: _AssetAction.duplicate,
          child: ListTile(
            leading: Icon(Icons.copy_all_outlined),
            title: Text('Duplicate'), dense: true,
          ),
        ),
        PopupMenuItem(
          value: _AssetAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text('Delete', style: TextStyle(color: scheme.error)), dense: true,
          ),
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case _AssetAction.view:
            final assetUrl =
                '${AppConfig.apiBaseUrl}${asset.publicUrl(resourceBase, dir.name)}';
            launchUrl(Uri.parse(assetUrl), mode: LaunchMode.externalApplication);
          case _AssetAction.previewKiosk: onPreviewKiosk();
          case _AssetAction.copyUrl:      onCopyUrl();
          case _AssetAction.rename:       onRename();
          case _AssetAction.move:         onMove();
          case _AssetAction.duplicate:    onDuplicate();
          case _AssetAction.delete:       onDelete();
        }
      },
    );
  }
}

// ── Asset thumbnail ────────────────────────────────────────────────────────────

Widget _assetFallbackIcon(ResourceAsset asset, ColorScheme scheme, double size) {
  Color bg; Color fg; IconData icon;
  if (asset.isHtml) {
    bg = scheme.primaryContainer; fg = scheme.primary; icon = Icons.html_outlined;
  } else if (asset.mimeType.startsWith('video/')) {
    bg = scheme.secondaryContainer; fg = scheme.secondary; icon = Icons.videocam_outlined;
  } else if (asset.mimeType == 'application/pdf') {
    bg = scheme.errorContainer; fg = scheme.error; icon = Icons.picture_as_pdf_outlined;
  } else {
    bg = scheme.surfaceContainerHighest; fg = scheme.outline; icon = Icons.insert_drive_file_outlined;
  }
  return Container(
    width: size, height: size,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Icon(icon, color: fg, size: size * 0.5),
  );
}

class _AssetThumb extends StatelessWidget {
  final ResourceAsset asset;
  final String resourceBase;
  final String dirName;
  final double size;
  final BoxFit fit;

  const _AssetThumb({
    required this.asset, required this.resourceBase, required this.dirName,
    this.size = 40, this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (asset.isImage) {
      final url = '${AppConfig.apiBaseUrl}/api/resources/${asset.resourceId}';
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(url, width: size, height: size, fit: fit,
            errorBuilder: (_, __, ___) => _assetFallbackIcon(asset, scheme, size)),
      );
    }
    return _assetFallbackIcon(asset, scheme, size);
  }
}

// ── Preview dialog ─────────────────────────────────────────────────────────────

void _openPreview(BuildContext context, ResourceAsset asset,
    ResourceDirectory dir, String resourceBase) {
  showDialog<void>(
    context: context,
    builder: (_) => _PreviewDialog(asset: asset, dir: dir, resourceBase: resourceBase),
  );
}

class _PreviewDialog extends StatefulWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String resourceBase;
  const _PreviewDialog({required this.asset, required this.dir, required this.resourceBase});

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  _PreviewLayout _layout = _PreviewLayout.fitWidth;

  String get _url =>
      '${AppConfig.apiBaseUrl}${widget.asset.publicUrl(widget.resourceBase, widget.dir.name)}';

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _url));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $_url')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.of(context).size;
    double? dialogWidth;
    double? dialogHeight;
    switch (_layout) {
      case _PreviewLayout.fullscreen:
        dialogWidth = screen.width - 16; dialogHeight = screen.height - 16;
      case _PreviewLayout.fitHeight:
        dialogHeight = screen.height * 0.85; dialogWidth = null;
      case _PreviewLayout.fitWidth:
        dialogWidth = screen.width * 0.88; dialogHeight = null;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: dialogWidth, height: dialogHeight,
          child: Column(
            mainAxisSize: _layout == _PreviewLayout.fitWidth
                ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Container(
                color: scheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.asset.name, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    if (!widget.asset.isHtml) ...[
                      const SizedBox(width: 8),
                      _PreviewLayoutToggle(current: _layout,
                          onChange: (l) => setState(() => _layout = l)),
                    ],
                    const SizedBox(width: 8),
                    if (widget.asset.isHtml)
                      IconButton(
                        icon: const Icon(Icons.open_in_browser_outlined, size: 18),
                        tooltip: 'Open in new tab',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Navigator.pop(context);
                          launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: 'Copy URL',
                      visualDensity: VisualDensity.compact,
                      onPressed: _copyUrl,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              if (widget.asset.isImage)
                _ImageContent(url: _url, layout: _layout, height: dialogHeight)
              else
                _FileContent(asset: widget.asset, url: _url),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: scheme.surfaceContainerLowest,
                child: SelectableText(_url,
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 11, color: scheme.outline)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final String url;
  final _PreviewLayout layout;
  final double? height;
  const _ImageContent({required this.url, required this.layout, this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isExpanded = layout != _PreviewLayout.fitWidth;
    final imgWidget = InteractiveViewer(
      minScale: 0.5, maxScale: 4.0,
      child: Image.network(url, fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Center(child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null)),
        errorBuilder: (_, __, ___) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.broken_image_outlined, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('Image unavailable', style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
    return isExpanded
        ? Expanded(child: imgWidget)
        : ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: 200, maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: imgWidget,
          );
  }
}

class _FileContent extends StatelessWidget {
  final ResourceAsset asset;
  final String url;
  const _FileContent({required this.asset, required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _assetFallbackIcon(asset, scheme, 80),
        const SizedBox(height: 16),
        Text(asset.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text('${_fmtSize(asset.sizeBytes)} · ${asset.mimeType}',
            style: TextStyle(color: scheme.outline, fontSize: 12)),
      ]),
    );
  }
}

class _PreviewLayoutToggle extends StatelessWidget {
  final _PreviewLayout current;
  final ValueChanged<_PreviewLayout> onChange;
  const _PreviewLayoutToggle({required this.current, required this.onChange});

  static const _icons = {
    _PreviewLayout.fitWidth:   (Icons.fit_screen_outlined,  'Fit width'),
    _PreviewLayout.fitHeight:  (Icons.height_outlined,       'Fit height'),
    _PreviewLayout.fullscreen: (Icons.fullscreen_outlined,   'Full screen'),
  };

  _PreviewLayout _next() => switch (current) {
    _PreviewLayout.fitWidth   => _PreviewLayout.fitHeight,
    _PreviewLayout.fitHeight  => _PreviewLayout.fullscreen,
    _PreviewLayout.fullscreen => _PreviewLayout.fitWidth,
  };

  @override
  Widget build(BuildContext context) {
    final (icon, tooltip) = _icons[current]!;
    return IconButton(
      icon: Icon(icon, size: 18), tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () => onChange(_next()),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

IconData _typeIcon(ResourceAsset asset) {
  if (asset.isImage)  return Icons.image_outlined;
  if (asset.isHtml)   return Icons.html_outlined;
  if (asset.mimeType.startsWith('video/')) return Icons.videocam_outlined;
  if (asset.mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.insert_drive_file_outlined;
}

Future<String?> _showNameDialog(BuildContext context,
    {required String title, String hint = ''}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl, autofocus: true,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _guessMime(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png'           => 'image/png',
    'gif'           => 'image/gif',
    'webp'          => 'image/webp',
    'svg'           => 'image/svg+xml',
    'html' || 'htm' => 'text/html',
    'css'           => 'text/css',
    'js'            => 'application/javascript',
    'pdf'           => 'application/pdf',
    'mp4'           => 'video/mp4',
    _               => 'application/octet-stream',
  };
}
