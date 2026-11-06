import 'package:flutter/material.dart';

/// Numbered pager used by the inventory report tables (Visits, Transfers,
/// Returns, Stock) — same look as the ad-hoc pagination bars in
/// orders_screen.dart / products_sales_screen.dart, factored out since three
/// new screens share it identically.
class WahaPaginationBar extends StatelessWidget {
  final int page;
  final int totalCount;
  final int pageSize;
  final ValueChanged<int> onPage;

  const WahaPaginationBar({
    super.key,
    required this.page,
    required this.totalCount,
    required this.pageSize,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    final total = (totalCount / pageSize).ceil();
    if (total <= 1) return const SizedBox.shrink();

    final first = (page - 2).clamp(0, (total - 5).clamp(0, total - 1));
    final last  = (first + 5).clamp(0, total);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (page > 0) ...[
          _Btn(label: '«', onTap: () => onPage(0)),
          _Btn(label: '‹', onTap: () => onPage(page - 1)),
        ],
        if (first > 0) const _Btn(label: '…', onTap: null),
        for (int i = first; i < last; i++)
          _Btn(label: '${i + 1}', selected: i == page,
              onTap: i == page ? null : () => onPage(i)),
        if (last < total) const _Btn(label: '…', onTap: null),
        if (page < total - 1) ...[
          _Btn(label: '›', onTap: () => onPage(page + 1)),
          _Btn(label: '»', onTap: () => onPage(total - 1)),
        ],
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _Btn({required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        constraints: const BoxConstraints(minWidth: 30),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected ? null : Border.all(color: scheme.outlineVariant),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? scheme.onPrimary : scheme.onSurface)),
      ),
    );
  }
}

/// "Rows per page" dropdown shown beside the pager in report footers.
class WahaPageSizeSelector extends StatelessWidget {
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const WahaPageSizeSelector({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Rows per page', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: value,
          underline: const SizedBox.shrink(),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text('$o', style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ],
    );
  }
}

