import 'package:flutter/material.dart';

import 'framed_card.dart';
import 'product_image.dart';

/// Compact framed category item: thumbnail, English + Arabic name, edit icon.
class CategoryCard extends StatelessWidget {
  final String nameEn;
  final String nameAr;
  final int? imageResourceId;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.nameEn,
    required this.nameAr,
    required this.imageResourceId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FramedCard(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: imageResourceId != null
                  ? ProductImage(imageResourceId: imageResourceId, fit: BoxFit.cover)
                  : Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.category_outlined,
                          color: scheme.onSurfaceVariant, size: 24),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nameEn,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (nameAr.isNotEmpty)
                  Text(nameAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
              ],
            ),
          ),
          Icon(Icons.edit_outlined, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
