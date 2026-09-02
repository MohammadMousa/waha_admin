import 'package:flutter/material.dart';

import '../config/app_config.dart';

class ProductImage extends StatelessWidget {
  final int? imageResourceId;
  final double? width;
  final double? height;
  final BoxFit fit;

  const ProductImage({
    super.key,
    required this.imageResourceId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = imageResourceId;
    if (id == null) {
      return Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
      );
    }
    return Image.network(
      '${AppConfig.apiBaseUrl}/api/resources/$id',
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
