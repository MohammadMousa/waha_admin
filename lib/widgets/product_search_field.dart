import 'dart:async';
import 'package:flutter/material.dart';
import 'waha_filter_controls.dart';

/// Type-to-search product picker for filters where a plain dropdown doesn't
/// scale — a catalog can run into the thousands of products, so this queries
/// [onSearch] with debounce as the user types instead of preloading
/// everything up front.
class ProductSearchField extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function(String query) onSearch;
  final String Function(Map<String, dynamic> product) labelBuilder;
  final ValueChanged<Map<String, dynamic>?> onSelected;
  final String hintText;
  final double width;

  const ProductSearchField({
    super.key,
    required this.onSearch,
    required this.labelBuilder,
    required this.onSelected,
    this.hintText = 'Search product…',
    this.width = 220,
  });

  @override
  State<ProductSearchField> createState() => _ProductSearchFieldState();
}

class _ProductSearchFieldState extends State<ProductSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _menuCtrl = MenuController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _hasSelection = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() {}); // refresh the clear (x) button's visibility immediately
    if (_hasSelection) {
      _hasSelection = false;
      widget.onSelected(null);
    }
    _debounce?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      _menuCtrl.close();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final results = await widget.onSearch(query);
        if (!mounted) return;
        setState(() { _results = results; _loading = false; });
        if (_results.isNotEmpty && _focusNode.hasFocus) {
          _menuCtrl.open();
        } else {
          _menuCtrl.close();
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _select(Map<String, dynamic> product) {
    _hasSelection = true;
    _controller.text = widget.labelBuilder(product);
    _menuCtrl.close();
    _focusNode.unfocus();
    widget.onSelected(product);
  }

  void _clear() {
    _hasSelection = false;
    _controller.clear();
    setState(() => _results = []);
    _menuCtrl.close();
    widget.onSelected(null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      controller: _menuCtrl,
      alignmentOffset: const Offset(0, 4),
      menuChildren: _results
          .map((p) => MenuItemButton(
                onPressed: () => _select(p),
                child: SizedBox(
                  width: widget.width - 24,
                  child: Text(widget.labelBuilder(p), overflow: TextOverflow.ellipsis),
                ),
              ))
          .toList(),
      child: Container(
        width: widget.width,
        height: kWahaFilterControlHeight,
        padding: kWahaFilterControlPadding,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: kWahaFilterControlRadius,
          color: scheme.surface,
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: scheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onChanged,
                onTap: () { if (_results.isNotEmpty) _menuCtrl.open(); },
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(fontSize: kWahaFilterControlFontSize, color: scheme.onSurface),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.hintText,
                  hintStyle: TextStyle(fontSize: kWahaFilterControlFontSize, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            if (_loading)
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_controller.text.isNotEmpty)
              GestureDetector(
                onTap: _clear,
                child: Icon(Icons.close, size: 16, color: scheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}
