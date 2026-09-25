import 'package:flutter/material.dart';

/// The light-gray rounded frame shared by dashboard cards and every list item
/// card (employees, devices, stores, categories): flat, 12 px radius, thin
/// outline, content-sized with a modest inner margin.
class FramedCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const FramedCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Lays list items out 3 per row (2 on medium, 1 on narrow windows). Each
/// card is only as tall as its content; cards in the same row match the
/// tallest one so the row lines up.
class CardGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final EdgeInsetsGeometry padding;

  const CardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.fromLTRB(24, 4, 24, 100),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1000 ? 3 : box.maxWidth >= 650 ? 2 : 1;
      return ListView.builder(
        padding: padding,
        itemCount: (itemCount / cols).ceil(),
        itemBuilder: (_, row) {
          final items = <Widget>[];
          for (var c = 0; c < cols; c++) {
            final i = row * cols + c;
            if (c > 0) items.add(const SizedBox(width: 12));
            items.add(Expanded(
              child: i < itemCount ? itemBuilder(context, i) : const SizedBox.shrink(),
            ));
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
            ),
          );
        },
      );
    });
  }
}
