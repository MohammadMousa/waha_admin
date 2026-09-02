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
import '../widgets/admin_sidebar.dart';
import '../widgets/resource_picker_modal.dart';

class AdvertisementsScreen extends StatefulWidget {
  const AdvertisementsScreen({super.key});

  @override
  State<AdvertisementsScreen> createState() => _AdvertisementsScreenState();
}

class _AdvertisementsScreenState extends State<AdvertisementsScreen> {
  List<Store>? _stores;
  Store? _selectedStore;
  bool _loadingStores = true;
  bool _loadingSlides = false;
  bool _saving = false;
  String? _error;
  String? _successMsg;

  final List<_Slide> _slides = [];
  int? _draggingIndex;

  static const _pagesDir = 'pages';
  static const _filename  = 'KIOSK_LANDING.html';

  Store? get _globalStore => _stores?.where((s) => s.id == 1).firstOrNull;
  String? get _activeSlug => (_selectedStore ?? _globalStore)?.name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _logout(); return; }
    try {
      final stores = await ApiClient().getAdminStores(token);
      if (!mounted) return;
      setState(() { _stores = stores; _loadingStores = false; });
      await _loadSlides();
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _logout(); return; }
      if (mounted) setState(() { _error = e.message; _loadingStores = false; });
    }
  }

  Future<void> _loadSlides() async {
    final slug = _activeSlug;
    if (slug == null) {
      setState(() { _error = 'Could not resolve store slug'; _loadingSlides = false; });
      return;
    }
    setState(() { _slides.clear(); _loadingSlides = true; _error = null; _successMsg = null; });
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/resource/$slug/$_pagesDir/$_filename');
      final resp = await http.get(uri);
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _parseHtml(utf8.decode(resp.bodyBytes));
      } else if (resp.statusCode != 404) {
        _error = 'Failed to load: HTTP ${resp.statusCode}';
      }
    } catch (e) {
      if (mounted) _error = 'Network error: $e';
    }
    if (mounted) setState(() => _loadingSlides = false);
  }

  void _parseHtml(String html) {
    final re = RegExp(r'<div class="slide" data-rid="(\d+)"(?:\s+data-label="([^"]*)")?[^>]*><img src="([^"]+)"');
    for (final m in re.allMatches(html)) {
      final rid    = int.tryParse(m.group(1)!);
      final label  = m.group(2) ?? '';
      final srcUrl = m.group(3) ?? '';
      if (rid != null) _slides.add(_Slide(resourceId: rid, label: label, publicUrl: srcUrl));
    }
  }

  // Extract a human-readable default name from a resource URL
  static String _defaultLabelFromUrl(String url) {
    final seg = url.split('/').last;
    final dot = seg.lastIndexOf('.');
    return dot > 0 ? seg.substring(0, dot) : seg;
  }

  Future<void> _addSlide() async {
    final token = context.read<AuthState>().token;
    final slug  = _activeSlug;
    if (token == null || slug == null) return;

    final picked = await showImageSourcePicker(context, storeSlug: slug, token: token);
    if (picked == null || !mounted) return;

    final defaultLabel = _defaultLabelFromUrl(picked.publicUrl);
    final label = await _askLabel(context, defaultText: defaultLabel);
    if (!mounted) return;

    setState(() => _slides.add(
        _Slide(resourceId: picked.resourceId, label: label ?? defaultLabel, publicUrl: picked.publicUrl)));
  }

  Future<String?> _askLabel(BuildContext ctx, {String defaultText = ''}) {
    final ctrl = TextEditingController(text: defaultText);
    return showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Display name'),
          onSubmitted: (_) => Navigator.of(dCtx).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dCtx).pop(null), child: const Text('Skip')),
          FilledButton(onPressed: () => Navigator.of(dCtx).pop(ctrl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
  }

  Future<void> _renameSlide(int i) async {
    final ctrl = TextEditingController(text: _slides[i].label);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Display name'),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    if (result != null && mounted) setState(() => _slides[i] = _slides[i].withLabel(result));
  }

  String _buildHtml() {
    final base = AppConfig.apiBaseUrl;
    final slideHtml = _slides.map((s) {
      final src = s.publicUrl.isNotEmpty
          ? (s.publicUrl.startsWith('http') ? s.publicUrl : '$base${s.publicUrl}')
          : '$base/api/resources/${s.resourceId}';
      final labelAttr = s.label.isNotEmpty ? ' data-label="${s.label}"' : '';
      return '  <div class="slide" data-rid="${s.resourceId}"$labelAttr><img src="$src" loading="eager" alt="${s.label}"></div>';
    }).join('\n');

    return '''<!DOCTYPE html>
<html lang="ar">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<meta name="waha-mode" content="fullscreen">
<title>Advertisements</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden;background:#000;touch-action:none}
.slide{position:absolute;inset:0;transform:translateX(100%)}
.slide img{width:100%;height:100%;object-fit:cover;display:block}
.tap{position:fixed;inset:0;z-index:99;cursor:pointer;-webkit-tap-highlight-color:transparent}
</style>
</head>
<body>
<div id="reel" data-slide-sec="5" style="position:relative;width:100%;height:100%">
$slideHtml
</div>
<a class="tap" href="/screen?name=cart_screen"></a>
<script>
(function(){
  var slides=Array.from(document.querySelectorAll('.slide'));
  if(!slides.length)return;
  var dur=parseInt(document.getElementById('reel').dataset.slideSec||'5',10)*1000;
  var t=700,cur=0;
  slides[0].style.transform='translateX(0)';
  function advance(){
    var nxt=(cur+1)%slides.length,old=cur;
    cur=nxt;
    slides[nxt].style.transition='none';
    slides[nxt].style.transform='translateX(100%)';
    requestAnimationFrame(function(){requestAnimationFrame(function(){
      slides[old].style.transition='transform '+t+'ms ease-in-out';
      slides[nxt].style.transition='transform '+t+'ms ease-in-out';
      slides[old].style.transform='translateX(-100%)';
      slides[nxt].style.transform='translateX(0)';
      setTimeout(function(){slides[old].style.transition='none';slides[old].style.transform='translateX(100%)';},t+50);
    });});
    setTimeout(advance,dur);
  }
  setTimeout(advance,dur);
})();
</script>
</body>
</html>''';
  }

  Future<bool> _save() async {
    if (_slides.isEmpty) {
      setState(() => _error = 'Add at least one image first.');
      return false;
    }
    final token = context.read<AuthState>().token;
    final slug  = _activeSlug;
    if (token == null || slug == null) return false;

    setState(() { _saving = true; _error = null; _successMsg = null; });
    try {
      try { await ApiClient().createDirectory(slug, _pagesDir, token); } catch (_) {}
      final bytes = utf8.encode(_buildHtml());
      await ApiClient().uploadAsset(slug, _pagesDir, bytes, _filename, 'text/html', token,
          nameOverride: _filename);
      if (!mounted) return false;
      setState(() => _successMsg = 'Saved.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _error = e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previewKiosk() async {
    final ok = await _save();
    if (!ok || !mounted) return;
    final slug = _activeSlug;
    if (slug == null) return;
    final url = '${AppConfig.apiBaseUrl}/resource/$slug/$_pagesDir/$_filename';
    html.window.open(url, '_blank', 'width=450,height=800,resizable=yes');
  }

  void _reorder(int from, int to) {
    if (from == to) return;
    setState(() {
      final s = _slides.removeAt(from);
      _slides.insert(to > from ? to - 1 : to, s);
    });
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
          const AdminSidebar(currentRoute: Routes.advertisements),
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
        _buildTopBar(scheme),
        Expanded(child: _buildBody(scheme)),
      ],
    );
  }

  Widget _buildTopBar(ColorScheme scheme) {
    final branches = <Store?>[null, ...?_stores];
    final busy = _loadingSlides || _saving;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Advertisements',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (_activeSlug != null)
                    Text('store: $_activeSlug', style: TextStyle(fontSize: 11, color: scheme.outline)),
                ],
              ),
              const Spacer(),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add image'),
                onPressed: busy ? null : _addSlide,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.stay_current_portrait_outlined, size: 16),
                label: const Text('Preview'),
                onPressed: (busy || _slides.isEmpty) ? null : _previewKiosk,
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (busy || _slides.isEmpty) ? null : () => _save(),
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Store?>(
                value: _selectedStore,
                hint: Text('Global (all branches)', style: TextStyle(fontSize: 13, color: scheme.onSurface)),
                isDense: true,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
                items: branches.map((s) => DropdownMenuItem<Store?>(
                  value: s,
                  child: Text(s == null ? 'Global (all branches)' : s.label()),
                )).toList(),
                onChanged: busy ? null : (s) {
                  setState(() => _selectedStore = s);
                  _loadSlides();
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
            ),
          if (_successMsg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_successMsg!, style: const TextStyle(color: Colors.green, fontSize: 13)),
            ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loadingSlides) return const Center(child: CircularProgressIndicator());

    if (_slides.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.burst_mode_outlined, size: 56, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text('No images yet', style: TextStyle(fontSize: 16, color: scheme.outline, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Tap "Add image" to upload the first slide', style: TextStyle(fontSize: 13, color: scheme.outline)),
        ]),
      );
    }

    return LayoutBuilder(builder: (_, constraints) {
      final cols = constraints.maxWidth > 1000 ? 4 : 3;
      final gap = 14.0;
      final cardW = (constraints.maxWidth - 40 - gap * (cols - 1)) / cols;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(_slides.length, (i) {
            final isDragging = _draggingIndex == i;
            return SizedBox(
              width: cardW,
              child: LongPressDraggable<int>(
                data: i,
                delay: const Duration(milliseconds: 250),
                onDragStarted: () => setState(() => _draggingIndex = i),
                onDragEnd: (_) => setState(() => _draggingIndex = null),
                feedback: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: cardW,
                    child: _buildCard(scheme, i, cardW, ghost: false),
                  ),
                ),
                childWhenDragging: Container(
                  width: cardW,
                  height: cardW,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.4), width: 2),
                  ),
                ),
                child: DragTarget<int>(
                  onAcceptWithDetails: (d) => _reorder(d.data, i),
                  builder: (_, candidates, rejected) {
                    final isTarget = candidates.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: isTarget
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: scheme.primary, width: 2),
                            )
                          : null,
                      child: isDragging
                          ? const SizedBox.shrink()
                          : _buildCard(scheme, i, cardW, ghost: false),
                    );
                  },
                ),
              ),
            );
          }),
        ),
      );
    });
  }

  Widget _buildCard(ColorScheme scheme, int i, double cardW, {required bool ghost}) {
    final slide = _slides[i];
    final base = AppConfig.apiBaseUrl;
    final url = slide.publicUrl.isNotEmpty
        ? (slide.publicUrl.startsWith('http') ? slide.publicUrl : '$base${slide.publicUrl}')
        : '$base/api/resources/${slide.resourceId}';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Square image area
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, err, stack) => Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.broken_image_outlined, size: 36, color: scheme.outline),
                    )),
                // Index badge
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                            color: scheme.onPrimary)),
                  ),
                ),
                // Drag hint
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.drag_indicator, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          // Bottom action bar
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            color: scheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (slide.label.isNotEmpty)
                  Text(slide.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Btn(Icons.stay_current_portrait_outlined, 'Preview',
                        () => _showPreview(context, slide)),
                    _Btn(Icons.drive_file_rename_outline, 'Rename', () => _renameSlide(i)),
                    _Btn(Icons.copy_outlined, 'Dup', () => setState(() => _slides.insert(
                        i + 1,
                        _Slide(resourceId: slide.resourceId,
                            label: slide.label.isEmpty ? 'copy' : '${slide.label} copy',
                            publicUrl: slide.publicUrl)))),
                    const Spacer(),
                    InkWell(
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Remove image?'),
                            content: const Text('Removes it from the slideshow only.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                            ],
                          ),
                        );
                        if (ok == true) setState(() => _slides.removeAt(i));
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline, size: 16, color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPreview(BuildContext context, _Slide slide) {
    final base = AppConfig.apiBaseUrl;
    final url = slide.publicUrl.isNotEmpty
        ? (slide.publicUrl.startsWith('http') ? slide.publicUrl : '$base${slide.publicUrl}')
        : '$base/api/resources/${slide.resourceId}';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 600),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url, fit: BoxFit.cover),
                ),
              ),
            ),
            if (slide.label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(slide.label,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tiny action button ────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Btn(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: scheme.primary),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 10, color: scheme.primary, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _Slide {
  final int resourceId;
  final String label;
  final String publicUrl;
  const _Slide({required this.resourceId, required this.label, required this.publicUrl});
  _Slide withLabel(String l) => _Slide(resourceId: resourceId, label: l, publicUrl: publicUrl);
}
