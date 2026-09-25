// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/resource.dart';
import '../services/api_client.dart';
import '../utils/resource_scope.dart';
import 'error_dialog.dart';

// Per-entity-type "remember my choice" destination directory, set by the
// upload-destination dialog below. Scoped by entityType only (not by
// org/branch) — the dialog re-validates the directory still exists in the
// current scope before trusting it, so a stale/foreign value just falls
// back to asking again rather than silently uploading to the wrong place.
Future<String?> _getRememberedDir(String entityType) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('resourcePicker.rememberedDir.$entityType');
}

Future<void> _setRememberedDir(String entityType, String? dir) async {
  final prefs = await SharedPreferences.getInstance();
  if (dir == null) {
    await prefs.remove('resourcePicker.rememberedDir.$entityType');
  } else {
    await prefs.setString('resourcePicker.rememberedDir.$entityType', dir);
  }
}

// Last directory browsed per scope, in the Files Manager browse dialog below.
// Same key namespace as the standalone Files Manager screen
// (resource_explorer_screen.dart) so the two stay in sync — whichever one
// you used last is where the other lands too (human lead, 2026-09-17).
Future<String?> _getLastBrowsedDir(String apiScope) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('filesManager.lastDir.$apiScope');
}

Future<void> _setLastBrowsedDir(String apiScope, String dirName) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('filesManager.lastDir.$apiScope', dirName);
}

String mimeForFilename(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    'gif': 'image/gif', 'webp': 'image/webp', 'svg': 'image/svg+xml',
    'pdf': 'application/pdf',
    'mp4': 'video/mp4', 'mov': 'video/quicktime',
    'html': 'text/html', 'htm': 'text/html',
    'css': 'text/css', 'js': 'application/javascript',
  };
  return map[ext] ?? 'application/octet-stream';
}

// ── Image source picker — Camera / Gallery / Files Manager ───────────────────

/// Shows a bottom sheet asking the user to pick an image source.
/// Uploads camera/gallery picks to the store's `res` directory automatically.
Future<PickedResource?> showImageSourcePicker(
    BuildContext context, {
    required String orgSlug,
    required String token,
    required String entityType, // 'product' | 'category' | 'store' | 'employee' | 'advertisement' | 'landing' | 'receipt' — keys the "remember my choice" directory
    String? branchName, // null = organization-level (global) scope
  }) async {
  final source = await showModalBottomSheet<_ImgSource>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text('Add image',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SourceOption(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onTap: () => Navigator.pop(ctx, _ImgSource.camera),
                ),
                _SourceOption(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => Navigator.pop(ctx, _ImgSource.gallery),
                ),
                _SourceOption(
                  icon: Icons.folder_outlined,
                  label: 'Files Manager',
                  onTap: () => Navigator.pop(ctx, _ImgSource.files),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
  if (source == null || !context.mounted) return null;

  if (source == _ImgSource.files) {
    return showResourcePickerModal(context,
        orgSlug: orgSlug, branchName: branchName, token: token, imagesOnly: true);
  }

  // Camera or Gallery — pick a local file then upload
  Uint8List? bytes;
  String? filename;

  if (source == _ImgSource.camera) {
    final result = await _pickFromCamera();
    bytes = result?.$1;
    filename = result?.$2;
  } else {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result != null && result.files.isNotEmpty) {
      bytes = result.files.first.bytes;
      filename = result.files.first.name;
    }
  }

  if (bytes == null || filename == null || !context.mounted) return null;

  final api = ApiClient();
  final apiScope = apiScopeFor(orgSlug, branchName);

  // Fast path: a remembered directory from a previous "remember my choice" —
  // skip the dialog entirely, as long as it still exists in this scope.
  final remembered = await _getRememberedDir(entityType);
  if (remembered != null && context.mounted) {
    try {
      final dirs = await api.getDirectories(apiScope, token);
      if (dirs.any((d) => d.name == remembered)) {
        final mime = mimeForFilename(filename);
        final asset =
            await api.uploadAsset(apiScope, remembered, bytes, filename, mime, token);
        final base = resourceBaseFor(orgSlug, branchName);
        return PickedResource(
          resourceId: asset.resourceId,
          publicUrl: asset.publicUrl(base, remembered),
        );
      }
      // Remembered directory no longer exists (deleted, or wrong scope) —
      // forget it and fall through to the dialog below.
      await _setRememberedDir(entityType, null);
    } catch (e) {
      if (context.mounted) {
        showErrorDialog(context, 'Upload failed: $e');
      }
      return null;
    }
  }

  if (!context.mounted) return null;
  return _showUploadDestinationDialog(
    context,
    api: api,
    apiScope: apiScope,
    orgSlug: orgSlug,
    branchName: branchName,
    entityType: entityType,
    token: token,
    bytes: bytes,
    filename: filename,
  );
}

/// Lets the user pick (or create) the destination directory and optionally
/// rename the file before it's uploaded — "old normal behaviour" (human
/// lead, 2026-09-14) restored for Camera/Gallery picks, which previously
/// auto-uploaded straight to a hardcoded `res` directory with no say in it.
/// Checking "Remember my choice" skips this dialog on future picks for the
/// same entityType (see _getRememberedDir/_setRememberedDir above).
Future<PickedResource?> _showUploadDestinationDialog(
  BuildContext context, {
  required ApiClient api,
  required String apiScope,
  required String orgSlug,
  required String? branchName,
  required String entityType,
  required String token,
  required Uint8List bytes,
  required String filename,
}) async {
  List<ResourceDirectory> dirs;
  try {
    dirs = await api.getDirectories(apiScope, token);
  } catch (e) {
    if (context.mounted) {
      showErrorDialog(context, 'Could not load directories: $e');
    }
    return null;
  }
  if (!context.mounted) return null;

  final nameCtrl = TextEditingController(text: filename);
  final newDirCtrl = TextEditingController();
  String? selectedDir =
      dirs.any((d) => d.name == 'res') ? 'res' : (dirs.isNotEmpty ? dirs.first.name : null);
  // The dropdown always lists what's actually there — no memorizing directory
  // names. The new-directory field is opt-in via the + button, never the
  // default state, whether or not any directories exist yet (human lead,
  // 2026-09-14: "admin isn't a wizard he won't memorize them").
  bool showNewDirField = false;
  bool remember = false;
  bool uploading = false;
  String? error;

  final result = await showDialog<PickedResource>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => PopScope(
        canPop: !uploading,
        child: AlertDialog(
          title: const Text('Save image'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(bytes, width: 88, height: 88, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Destination directory',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedDir,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          isDense: true,
                          hintText: dirs.isEmpty ? 'No directories yet' : null,
                        ),
                        items: dirs
                            .map((d) => DropdownMenuItem(value: d.name, child: Text(d.name)))
                            .toList(),
                        onChanged: (uploading || dirs.isEmpty)
                            ? null
                            : (v) => setSt(() => selectedDir = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: showNewDirField ? 'Cancel new directory' : 'New directory',
                      icon: Icon(showNewDirField ? Icons.close : Icons.add),
                      onPressed:
                          uploading ? null : () => setSt(() => showNewDirField = !showNewDirField),
                    ),
                  ],
                ),
                if (showNewDirField) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: newDirCtrl,
                    enabled: !uploading,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'New directory name', border: OutlineInputBorder(), isDense: true),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  enabled: !uploading,
                  decoration: const InputDecoration(
                      labelText: 'Image name', border: OutlineInputBorder(), isDense: true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: remember,
                  onChanged: uploading ? null : (v) => setSt(() => remember = v ?? false),
                  title: const Text('Remember my choice', style: TextStyle(fontSize: 13)),
                ),
                if (error != null) ...[
                  const SizedBox(height: 4),
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
                if (uploading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: uploading
              ? null
              : [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () async {
                      final usingNewDir = showNewDirField && newDirCtrl.text.trim().isNotEmpty;
                      final dirName = usingNewDir ? newDirCtrl.text.trim() : (selectedDir ?? '');
                      if (dirName.isEmpty) {
                        setSt(() => error = 'Select or create a directory');
                        return;
                      }
                      final finalName =
                          nameCtrl.text.trim().isEmpty ? filename : nameCtrl.text.trim();
                      setSt(() {
                        uploading = true;
                        error = null;
                      });
                      try {
                        if (usingNewDir) {
                          try {
                            await api.createDirectory(apiScope, dirName, token);
                          } catch (_) { /* already exists — ignore */ }
                        }
                        final asset = await api.uploadAsset(apiScope, dirName, bytes, finalName,
                            mimeForFilename(finalName), token);
                        final base = resourceBaseFor(orgSlug, branchName);
                        await _setRememberedDir(entityType, remember ? dirName : null);
                        if (ctx.mounted) {
                          Navigator.pop(
                              ctx,
                              PickedResource(
                                  resourceId: asset.resourceId,
                                  publicUrl: asset.publicUrl(base, dirName)));
                        }
                      } catch (e) {
                        setSt(() {
                          uploading = false;
                          error = e.toString();
                        });
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
        ),
      ),
    ),
  );
  nameCtrl.dispose();
  newDirCtrl.dispose();
  return result;
}

enum _ImgSource { camera, gallery, files }

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: scheme.primary),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

// Uses dart:html to trigger a camera-capture file input
Future<(Uint8List, String)?> _pickFromCamera() async {
  final completer = Completer<(Uint8List, String)?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..setAttribute('capture', 'environment');
  input.onChange.listen((_) async {
    final file = input.files?.first;
    if (file == null) { completer.complete(null); return; }
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is List<int>) {
        completer.complete((Uint8List.fromList(result), file.name));
      } else {
        completer.complete(null);
      }
    });
  });
  input.click();
  return completer.future;
}

// ── Resource picker modal (Files Manager browse) ──────────────────────────────

Future<PickedResource?> showResourcePickerModal(
    BuildContext context, {
    required String orgSlug,
    required String token,
    String? branchName, // null = organization-level (global) scope
    bool imagesOnly = false,
  }) {
  return showDialog<PickedResource>(
    context: context,
    builder: (_) => ResourcePickerModal(
      orgSlug: orgSlug,
      branchName: branchName,
      token: token,
      imagesOnly: imagesOnly,
    ),
  );
}

class ResourcePickerModal extends StatefulWidget {
  final String orgSlug;
  final String? branchName; // null = organization-level (global) scope
  final String token;
  final bool imagesOnly;

  const ResourcePickerModal({
    super.key,
    required this.orgSlug,
    this.branchName,
    required this.token,
    this.imagesOnly = false,
  });

  @override
  State<ResourcePickerModal> createState() => _ResourcePickerModalState();
}

class _ResourcePickerModalState extends State<ResourcePickerModal> {
  List<ResourceDirectory>? _dirs;
  ResourceDirectory? _selectedDir;
  List<ResourceAsset>? _assets;
  bool _loadingDirs = true;
  bool _loadingAssets = false;
  String? _error;

  final _api = ApiClient();

  String get _apiScope => apiScopeFor(widget.orgSlug, widget.branchName);

  @override
  void initState() {
    super.initState();
    _loadDirs();
  }

  Future<void> _loadDirs() async {
    try {
      final dirs = await _api.getDirectories(_apiScope, widget.token);
      if (!mounted) return;
      setState(() { _dirs = dirs; _loadingDirs = false; });
      if (dirs.isEmpty) return;
      // Land back on whatever directory was last browsed in this scope —
      // shares state with the standalone Files Manager screen (same key),
      // instead of always resetting to the first directory.
      final lastName = await _getLastBrowsedDir(_apiScope);
      if (!mounted) return;
      final match = lastName == null ? const <ResourceDirectory>[]
          : dirs.where((d) => d.name == lastName).toList();
      await _selectDir(match.isNotEmpty ? match.first : dirs.first);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingDirs = false; });
    }
  }

  Future<void> _selectDir(ResourceDirectory dir) async {
    setState(() { _selectedDir = dir; _assets = null; _loadingAssets = true; });
    _setLastBrowsedDir(_apiScope, dir.name);
    try {
      final assets = await _api.getAssets(_apiScope, dir.name, widget.token);
      if (!mounted) return;
      setState(() { _assets = assets; _loadingAssets = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingAssets = false; });
    }
  }

  void _pick(ResourceAsset asset) {
    final base = resourceBaseFor(widget.orgSlug, widget.branchName);
    Navigator.of(context).pop(PickedResource(
      resourceId: asset.resourceId,
      publicUrl: asset.publicUrl(base, _selectedDir!.name),
    ));
  }

  Future<void> _uploadFile() async {
    final dir = _selectedDir;
    if (dir == null) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final pf = result.files.first;
    final bytes = pf.bytes;
    if (bytes == null) return;

    final nameCtrl = TextEditingController(text: pf.name);
    bool uploading = false;
    String? uploadError;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => PopScope(
          canPop: !uploading,
          child: AlertDialog(
            title: const Text('Upload file'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('To: ${dir.name}',
                      style: TextStyle(fontSize: 13,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    enabled: !uploading,
                    decoration: const InputDecoration(
                        labelText: 'Filename', border: OutlineInputBorder()),
                    autofocus: true,
                  ),
                  if (uploadError != null) ...[
                    const SizedBox(height: 10),
                    Text(uploadError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  if (uploading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
            actions: uploading
                ? null
                : [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () async {
                        setSt(() { uploading = true; uploadError = null; });
                        try {
                          final name = nameCtrl.text.trim().isEmpty
                              ? pf.name : nameCtrl.text.trim();
                          await _api.uploadAsset(
                              _apiScope, dir.name,
                              Uint8List.fromList(bytes), name,
                              mimeForFilename(name), widget.token);
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setSt(() { uploading = false; uploadError = e.toString(); });
                        }
                      },
                      child: const Text('Upload'),
                    ),
                  ],
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    if (confirmed == true && mounted && _selectedDir != null) _selectDir(_selectedDir!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.folder_open_outlined, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Select Resource',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    tooltip: _selectedDir == null ? 'Select a directory first' : 'Upload file',
                    onPressed: _loadingDirs || _selectedDir == null ? null : _uploadFile,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loadingDirs
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : Row(
                          children: [
                            SizedBox(
                              width: 160,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _dirs?.length ?? 0,
                                itemBuilder: (ctx, i) {
                                  final dir = _dirs![i];
                                  final selected = _selectedDir?.id == dir.id;
                                  return ListTile(
                                    dense: true,
                                    selected: selected,
                                    selectedTileColor: scheme.primaryContainer,
                                    leading: Icon(Icons.folder_outlined, size: 18,
                                        color: selected ? scheme.primary : scheme.onSurfaceVariant),
                                    title: Text(dir.name, style: const TextStyle(fontSize: 13)),
                                    onTap: () => _selectDir(dir),
                                  );
                                },
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: _loadingAssets
                                  ? const Center(child: CircularProgressIndicator())
                                  : _assets == null || _assets!.isEmpty
                                      ? Center(child: Text('No assets',
                                          style: TextStyle(color: scheme.outline)))
                                      : Builder(builder: (ctx) {
                                          final visible = widget.imagesOnly
                                              ? _assets!.where((a) => a.isImage).toList()
                                              : _assets!;
                                          if (visible.isEmpty) {
                                            return Center(child: Text(
                                                widget.imagesOnly
                                                    ? 'No images in this directory'
                                                    : 'No assets',
                                                style: TextStyle(color: scheme.outline)));
                                          }
                                          return GridView.builder(
                                            padding: const EdgeInsets.all(12),
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              crossAxisSpacing: 8,
                                              mainAxisSpacing: 8,
                                            ),
                                            itemCount: visible.length,
                                            itemBuilder: (ctx, i) {
                                              final asset = visible[i];
                                              return _AssetTile(
                                                asset: asset,
                                                onTap: () => _pick(asset),
                                              );
                                            },
                                          );
                                        }),
                            ),
                          ],
                        ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final ResourceAsset asset;
  final VoidCallback onTap;

  const _AssetTile({
    required this.asset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset.isImage)
              Image.network('${AppConfig.apiBaseUrl}/api/resources/${asset.resourceId}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallbackIcon(scheme))
            else
              _fallbackIcon(scheme),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.all(4),
                child: Text(asset.name,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.insert_drive_file_outlined,
            color: scheme.onSurfaceVariant, size: 32));
}
