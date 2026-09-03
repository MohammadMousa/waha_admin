import 'dart:async';
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

class LandingEditorScreen extends StatefulWidget {
  final Store store;
  /// Which landing page to edit (e.g. 'KIOSK_LANDING', 'SHOPPING_LANDING').
  final String pageKey;
  const LandingEditorScreen({
    super.key,
    required this.store,
    this.pageKey = 'KIOSK_LANDING',
  });

  @override
  State<LandingEditorScreen> createState() => _LandingEditorScreenState();
}

class _LandingEditorScreenState extends State<LandingEditorScreen> {
  final List<_Slide> _slides = [];

  int _slideSec = 5;
  bool _fullscreen = true;   // embedded vs fullscreen display mode
  bool _initializing  = true;
  bool _existingLoaded = false;
  bool _saving = false;
  String? _error;
  String? _savedMessage;

  static const _pagesDir = 'pages';

  String get _storeSlug => widget.store.name;
  String get _filename  => '${widget.pageKey}.html';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  Future<void> _loadExisting() async {
    try {
      final token = context.read<AuthState>().token;
      final uri = Uri.parse(
          '${AppConfig.apiBaseUrl}/resource/$_storeSlug/$_pagesDir/$_filename');
      final resp = await http.get(uri); // public resource — no auth header (avoids CORS preflight)
      if (resp.statusCode == 200) {
        final htmlBody = utf8.decode(resp.bodyBytes);
        if (htmlBody.contains('data-rid=')) {
          _parseExistingHtml(htmlBody);
          _existingLoaded = true;
        }
      }
      // 404 or non-editor HTML = start blank
    } catch (e) {
      if (mounted) setState(() => _error = 'Load error: $e');
    }
    if (mounted) setState(() => _initializing = false);
  }

  void _parseExistingHtml(String html) {
    final secM = RegExp(r'data-slide-sec="(\d+)"').firstMatch(html);
    if (secM != null) _slideSec = int.tryParse(secM.group(1)!) ?? _slideSec;

    // Parse display mode from meta tag
    final modeM = RegExp(r'<meta name="waha-mode" content="([^"]+)"').firstMatch(html);
    if (modeM != null) _fullscreen = modeM.group(1) == 'fullscreen';

    final slideRe = RegExp(r'<div class="slide" data-rid="(\d+)"[^>]*><img src="([^"]+)"');
    for (final m in slideRe.allMatches(html)) {
      final rid = int.tryParse(m.group(1)!);
      final src = m.group(2)!;
      if (rid != null) _slides.add(_Slide(resourceId: rid, publicUrl: src));
    }
  }

  Future<void> _addSlide() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final picked = await showImageSourcePicker(context,
        storeSlug: _storeSlug, token: token);
    if (picked == null || !mounted) return;
    setState(() => _slides.add(_Slide(
      resourceId: picked.resourceId,
      publicUrl: picked.publicUrl,
    )));
  }

  static String _toRelativePath(String url) {
    if (url.startsWith('/')) return url;
    if (url.startsWith('http')) return Uri.parse(url).path;
    return '/$url';
  }

  String _buildHtml() {
    final mode = _fullscreen ? 'fullscreen' : 'embedded';
    final slideHtml = _slides.map((s) {
      final src = s.publicUrl.isNotEmpty
          ? _toRelativePath(s.publicUrl)
          : '/api/resources/${s.resourceId}';
      return '  <div class="slide" data-rid="${s.resourceId}"><img src="$src" loading="eager" alt=""></div>';
    }).join('\n');

    return '''<!DOCTYPE html>
<html lang="ar">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<meta name="waha-mode" content="$mode">
<title>Preview</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden;background:#000;touch-action:none}
.slide{position:absolute;inset:0;transform:translateX(100%)}
.slide img{width:100%;height:100%;object-fit:cover;display:block}
.tap{position:fixed;inset:0;z-index:99;cursor:pointer;-webkit-tap-highlight-color:transparent}
</style>
</head>
<body>
<div id="reel" data-slide-sec="$_slideSec" style="position:relative;width:100%;height:100%">
$slideHtml
</div>
<a class="tap" href="/screen?name=cart_screen"></a>
<script>
(function(){
  var slides=Array.from(document.querySelectorAll('.slide'));
  if(!slides.length)return;
  var dur=parseInt(document.getElementById('reel').dataset.slideSec||'5',10)*1000;
  var t=700;
  var cur=0;
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
      setTimeout(function(){
        slides[old].style.transition='none';
        slides[old].style.transform='translateX(100%)';
      },t+50);
    });});
    setTimeout(advance,dur);
  }
  setTimeout(advance,dur);
})();
</script>
</body>
</html>''';
  }

  Future<void> _save() async {
    if (_slides.isEmpty) {
      setState(() => _error = 'Add at least one image first.');
      return;
    }
    final token = context.read<AuthState>().token;
    if (token == null) { setState(() => _error = 'Not authenticated.'); return; }

    if (!_existingLoaded) {
      final exists = await _pageExistsOnServer();
      if (!mounted) return;
      if (exists) {
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace existing page?'),
            content: const Text(
                'A landing page already exists. Saving will replace it permanently.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
            ],
          ),
        );
        if (overwrite != true || !mounted) return;
      }
    }

    setState(() { _saving = true; _error = null; _savedMessage = null; });
    final api = ApiClient();

    try {
      try { await api.createDirectory(_storeSlug, _pagesDir, token); } catch (_) {}

      final html  = _buildHtml();
      final bytes = utf8.encode(html);
      await api.uploadAsset(_storeSlug, _pagesDir, bytes, _filename, 'text/html', token,
          nameOverride: _filename);

      if (!mounted) return;
      setState(() {
        _existingLoaded = true;
        _savedMessage   = 'Saved — reload the kiosk to see changes.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _pageExistsOnServer() async {
    try {
      final uri = Uri.parse(
          '${AppConfig.apiBaseUrl}/resource/$_storeSlug/$_pagesDir/$_filename');
      final resp = await http.head(uri);
      return resp.statusCode == 200;
    } catch (_) { return false; }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.landingPages),
          Expanded(
            child: Column(
              children: [
                // Header bar
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Text('Edit ${_pageKeyLabel(widget.pageKey)}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('— ${widget.store.label()}',
                          style: TextStyle(color: scheme.outline, fontSize: 14)),
                      const Spacer(),
                      if (!_initializing)
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('Save'),
                        ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: _initializing
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SectionLabel('Display Mode'),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ModeCard(
                                          icon: Icons.fullscreen_outlined,
                                          title: 'Fullscreen',
                                          subtitle: 'Covers entire screen, no app bar or navigation',
                                          selected: _fullscreen,
                                          onTap: () => setState(() => _fullscreen = true),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ModeCard(
                                          icon: Icons.web_asset_outlined,
                                          title: 'Embedded',
                                          subtitle: 'Inside app frame with header and navigation',
                                          selected: !_fullscreen,
                                          onTap: () => setState(() => _fullscreen = false),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  Row(
                                    children: [
                                      _SectionLabel('Slides'),
                                      const Spacer(),
                                      TextButton.icon(
                                        icon: const Icon(Icons.add_photo_alternate_outlined,
                                            size: 18),
                                        label: const Text('Add image'),
                                        onPressed: _addSlide,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  if (_slides.isEmpty)
                                    Container(
                                      height: 120,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: scheme.outlineVariant),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.image_outlined, size: 36,
                                              color: scheme.outlineVariant),
                                          const SizedBox(height: 8),
                                          Text('No images yet — tap Add image',
                                              style: TextStyle(color: scheme.outline)),
                                        ]),
                                      ),
                                    )
                                  else
                                    ReorderableListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _slides.length,
                                      onReorderItem: (oldIdx, newIdx) {
                                        setState(() {
                                          final s = _slides.removeAt(oldIdx);
                                          _slides.insert(newIdx, s);
                                        });
                                      },
                                      itemBuilder: (_, i) => _SlideRow(
                                        key: ValueKey(_slides[i]),
                                        index: i,
                                        slide: _slides[i],
                                        onDelete: () => setState(() => _slides.removeAt(i)),
                                      ),
                                    ),

                                  const SizedBox(height: 24),
                                  _SectionLabel('Settings'),
                                  const SizedBox(height: 12),
                                  _SettingsCard(
                                    slideSec: _slideSec,
                                    onSlideSecChanged: (v) => setState(() => _slideSec = v),
                                  ),

                                  if (_error != null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: scheme.errorContainer,
                                          borderRadius: BorderRadius.circular(8)),
                                      child: Text(_error!,
                                          style: TextStyle(color: scheme.onErrorContainer,
                                              fontSize: 13)),
                                    ),
                                  ],
                                  if (_savedMessage != null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(8)),
                                      child: Row(children: [
                                        const Icon(Icons.check_circle_outline,
                                            color: Colors.green, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(_savedMessage!,
                                            style: const TextStyle(color: Colors.green,
                                                fontSize: 13))),
                                      ]),
                                    ),
                                  ],

                                  if (_slides.isNotEmpty) ...[
                                    const SizedBox(height: 24),
                                    _SectionLabel('Preview — 9:16 aspect ratio'),
                                    const SizedBox(height: 8),
                                    _ScreensaverPreview(slides: _slides),
                                  ],
                                  const SizedBox(height: 40),
                                ],
                              ),
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

  static String _pageKeyLabel(String key) => switch (key) {
    'KIOSK_LANDING'    => 'Kiosk Landing',
    'SHOPPING_LANDING' => 'Shopping Landing',
    'CLIENT_LANDING'   => 'Client Landing',
    'ADMIN_LANDING'    => 'Admin Landing',
    _                  => key,
  };
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _Slide {
  final int resourceId;
  final String publicUrl;
  const _Slide({required this.resourceId, required this.publicUrl});
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700, letterSpacing: 0.5,
    ),
  );
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ModeCard({required this.icon, required this.title,
      required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                    color: selected ? scheme.onPrimaryContainer : scheme.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11,
                    color: selected
                        ? scheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : scheme.outline)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideRow extends StatelessWidget {
  final int index;
  final _Slide slide;
  final VoidCallback onDelete;
  const _SlideRow({super.key, required this.index, required this.slide, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            '${AppConfig.apiBaseUrl}${slide.publicUrl}',
            width: 52, height: 52, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 52, height: 52, color: Colors.black12,
              child: const Icon(Icons.image_outlined, size: 20),
            ),
          ),
        ),
        title: Text('Slide ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(slide.publicUrl, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: scheme.outline)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_handle, color: scheme.outline),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.close, color: scheme.error, size: 18),
              onPressed: onDelete, tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final int slideSec;
  final ValueChanged<int> onSlideSecChanged;
  const _SettingsCard({required this.slideSec, required this.onSlideSecChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _SettingRow(
            label: 'Slide duration', value: slideSec, unit: 'sec',
            min: 2, max: 30, onChanged: onSlideSecChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.shopping_cart_outlined, size: 16, color: scheme.outline),
              const SizedBox(width: 6),
              Text('Tap anywhere → Cart',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _SettingRow({required this.label, required this.value, required this.unit,
      required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          color: scheme.primary, padding: EdgeInsets.zero,
        ),
        SizedBox(
          width: 48,
          child: Text('$value $unit', textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          color: scheme.primary, padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _ScreensaverPreview extends StatefulWidget {
  final List<_Slide> slides;
  const _ScreensaverPreview({required this.slides});

  @override
  State<_ScreensaverPreview> createState() => _ScreensaverPreviewState();
}

class _ScreensaverPreviewState extends State<_ScreensaverPreview> {
  late final PageController _pageCtrl;
  Timer? _timer;
  // Never wraps — always increments so PageView scrolls forward infinitely
  int _page = 0;

  static const _transitionMs = 700;
  static const _pauseSec = 3;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer(const Duration(seconds: _pauseSec), _advance);
  }

  void _advance() {
    if (!mounted) return;
    _page++;            // always forward, never wraps back to 0
    _pageCtrl.animateToPage(_page,
        duration: const Duration(milliseconds: _transitionMs), curve: Curves.easeInOut);
    _scheduleNext();
  }

  @override
  void didUpdateWidget(_ScreensaverPreview old) {
    super.didUpdateWidget(old);
    if (old.slides != widget.slides) {
      _page = 0;
      _pageCtrl.jumpToPage(0);
      _scheduleNext();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black),
                PageView.builder(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: null, // infinite — page index keeps incrementing forward
                  itemBuilder: (_, i) {
                    final slide = widget.slides[i % widget.slides.length];
                    final url = '${AppConfig.apiBaseUrl}${slide.publicUrl}';
                    return Image.network(url,
                      fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26),
                    );
                  },
                ),
                Positioned(
                  bottom: 12, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart_outlined, size: 12,
                              color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(width: 4),
                          Text('tap → cart',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8), fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
