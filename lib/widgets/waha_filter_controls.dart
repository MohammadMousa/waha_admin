import 'package:flutter/material.dart';

/// Shared visual constants for toolbar filter controls (dropdowns, search
/// fields, and similar pickers) so every screen renders them identically.
/// Height is fixed explicitly rather than derived from padding, since
/// [TextField]'s internal InputDecorator does not reliably match the height
/// of a plain [Container] even with identical padding.
const kWahaFilterControlHeight = 38.0;
const kWahaFilterControlPadding = EdgeInsets.symmetric(horizontal: 12);
final kWahaFilterControlRadius = BorderRadius.circular(8);
const kWahaFilterControlFontSize = 13.0;

/// A boxed, single-select dropdown used in screen toolbars (status/category/
/// branch filters, etc). Matches the style of [WahaSearchField] and the
/// waha date-range trigger button — same height, border, and font — and
/// opens its menu directly below the control.
class WahaFilterDropdown<T> extends StatefulWidget {
  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Fill the width it is given (arrow at the far edge) instead of hugging the
  /// text. Only use where the width is bounded, e.g. inside an Expanded.
  final bool expand;

  /// Box colour; defaults to the surface colour.
  final Color? fillColor;

  const WahaFilterDropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.expand = false,
    this.fillColor,
  });

  @override
  State<WahaFilterDropdown<T>> createState() => _WahaFilterDropdownState<T>();
}

class _WahaFilterDropdownState<T> extends State<WahaFilterDropdown<T>> {
  final _menuCtrl = MenuController();
  double _width = 0;
  final _boxKey = GlobalKey();

  /// Keeps the list as wide as the box: measured after layout, so it is right
  /// before the first tap and follows the box when its text changes.
  void _measure() {
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && (box.size.width - _width).abs() > 0.5) {
      setState(() => _width = box.size.width);
    }
  }

  String _label() {
    final match = widget.items.where((i) => i.value == widget.value).firstOrNull;
    final child = match?.child;
    if (child is Text) return child.data ?? widget.hint;
    return widget.hint;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaceholder = widget.value == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });

    return MenuAnchor(
      controller: _menuCtrl,
      alignmentOffset: const Offset(0, 4),
      // The list is at least as wide as the box and drawn in the same colours.
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: kWahaFilterControlRadius,
          side: BorderSide(color: scheme.outlineVariant),
        )),
      ),
      // Each row is at least as wide as the box, so the list never is narrower
      // (MenuStyle.minimumSize alone does not widen it).
      menuChildren: widget.items
          .map((item) => ConstrainedBox(
                constraints: BoxConstraints(minWidth: _width),
                child: MenuItemButton(
                  onPressed: () => widget.onChanged(item.value),
                  child: item.child,
                ),
              ))
          .toList(),
      child: GestureDetector(
        onTap: () {
          _measure();
          _menuCtrl.open();
        },
        child: Container(
          key: _boxKey,
          height: kWahaFilterControlHeight,
          padding: kWahaFilterControlPadding,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline),
            borderRadius: kWahaFilterControlRadius,
            color: widget.fillColor ?? scheme.surface,
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              (widget.expand ? (Widget w) => Expanded(child: w) : (Widget w) => Flexible(child: w))(Text(_label(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: kWahaFilterControlFontSize,
                      color: isPlaceholder
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface))),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// A boxed search field matching [WahaFilterDropdown]'s height, border, and
/// font so search and filter controls sit in the same visual theme.
class WahaSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final double width;

  /// Called when the user presses Enter.
  final VoidCallback? onSubmitted;

  /// When set, a clear (×) button shows while the field has text; the
  /// callback runs after the field has been emptied.
  final VoidCallback? onClear;

  /// Called on every keystroke, for filters that apply as the user types.
  final ValueChanged<String>? onChanged;

  /// Leading icon (the magnifier by default).
  final IconData icon;

  const WahaSearchField({
    super.key,
    required this.controller,
    this.hintText = 'Search…',
    this.width = 220,
    this.onSubmitted,
    this.onClear,
    this.onChanged,
    this.icon = Icons.search,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The border is drawn by this Container, not by the TextField's own
    // InputDecoration — OutlineInputBorder reserves internal gap-padding for
    // a floating label even with isCollapsed: true, which made this field
    // render taller than WahaFilterDropdown's plain Container despite
    // matching height/padding values. InputBorder.none sidesteps that.
    return Container(
      width: width,
      height: kWahaFilterControlHeight,
      padding: kWahaFilterControlPadding,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: kWahaFilterControlRadius,
        color: scheme.surface,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
              onChanged: onChanged,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                  fontSize: kWahaFilterControlFontSize, color: scheme.onSurface),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hintText,
                hintStyle: TextStyle(
                    fontSize: kWahaFilterControlFontSize,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          if (onClear != null)
            ListenableBuilder(
              listenable: controller,
              builder: (_, __) => controller.text.isEmpty
                  ? const SizedBox.shrink()
                  : InkWell(
                      onTap: () {
                        controller.clear();
                        onClear!();
                      },
                      child: Icon(Icons.close, size: 16, color: scheme.outline),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Date-range trigger for filter toolbars, drawn like the Orders screen's:
/// a bordered calendar button that shows the range, plus a × when one is set.
class WahaFilterDateRange extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String hint;

  const WahaFilterDateRange({
    super.key,
    required this.range,
    required this.onTap,
    this.onClear,
    this.hint = 'Select date range',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = range;
    return InkWell(
      onTap: onTap,
      borderRadius: kWahaFilterControlRadius,
      child: Container(
        height: kWahaFilterControlHeight,
        padding: kWahaFilterControlPadding,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: kWahaFilterControlRadius,
          color: scheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text(r == null ? hint : '${fmt(r.start)}  –  ${fmt(r.end)}',
                style: const TextStyle(fontSize: kWahaFilterControlFontSize)),
            if (r != null && onClear != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: scheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Header label for a sortable [DataColumn], drawn like the Orders report: a
/// faint two-way arrow on every sortable column, and a solid up/down arrow on
/// the column the table is currently sorted by. Use it without the DataTable's
/// own sortColumnIndex, which would add a second arrow.
Widget wahaSortableLabel(BuildContext context, String text,
    {required bool active, required bool asc}) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(width: 3),
      Icon(
        active ? (asc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
        size: 13,
        color: active ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
      ),
    ],
  );
}
