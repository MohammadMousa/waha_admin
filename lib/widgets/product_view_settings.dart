import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display settings for the Products grid, kept in local prefs (never any
/// credentials): product-name font size, price font size, and column count
/// (0 = automatic).
class ProductViewSettings {
  final double nameSize;
  final double priceSize;
  final int columns;
  /// Image height as a percentage of the card width (50–130).
  final int imagePercent;

  const ProductViewSettings({
    this.nameSize = 12,
    this.priceSize = 11,
    this.columns = 0,
    this.imagePercent = 90,
  });

  static const _kName = 'productView.nameSize';
  static const _kPrice = 'productView.priceSize';
  static const _kCols = 'productView.columns';
  static const _kImage = 'productView.imagePercent';

  static Future<ProductViewSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return ProductViewSettings(
      nameSize: p.getDouble(_kName) ?? 12,
      priceSize: p.getDouble(_kPrice) ?? 11,
      columns: p.getInt(_kCols) ?? 0,
      imagePercent: p.getInt(_kImage) ?? 90,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kName, nameSize);
    await p.setDouble(_kPrice, priceSize);
    await p.setInt(_kCols, columns);
    await p.setInt(_kImage, imagePercent);
  }
}

Future<ProductViewSettings?> showProductViewSettingsDialog(
    BuildContext context, ProductViewSettings current) {
  var name = current.nameSize;
  var price = current.priceSize;
  var cols = current.columns;
  var image = current.imagePercent.toDouble();
  return showDialog<ProductViewSettings>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('Products display'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Product font size: ${name.round()}'),
              Slider(
                value: name, min: 10, max: 28, divisions: 18,
                onChanged: (v) => setSt(() => name = v),
              ),
              Text('Price font size: ${price.round()}'),
              Slider(
                value: price, min: 10, max: 28, divisions: 18,
                onChanged: (v) => setSt(() => price = v),
              ),
              Text('Image size: ${image.round()}%'),
              Slider(
                value: image, min: 50, max: 130, divisions: 8,
                label: '${image.round()}%',
                onChanged: (v) => setSt(() => image = v),
              ),
              Text('Columns: ${cols == 0 ? 'Auto' : cols}'),
              Slider(
                value: cols.toDouble(), min: 0, max: 12, divisions: 12,
                label: cols == 0 ? 'Auto' : '$cols',
                onChanged: (v) => setSt(() => cols = v.round()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setSt(() { name = 12; price = 11; cols = 0; image = 90; }),
            child: const Text('Reset'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx,
                ProductViewSettings(
                    nameSize: name, priceSize: price, columns: cols, imagePercent: image.round())),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
