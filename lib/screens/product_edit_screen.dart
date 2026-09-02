import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/product_image.dart';
import '../widgets/resource_picker_modal.dart';

class ProductEditScreen extends StatefulWidget {
  /// null = create mode, non-null = edit mode
  final int? productId;
  final String storeSlug;

  const ProductEditScreen({
    super.key,
    required this.productId,
    required this.storeSlug,
  });

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  bool _loading = true;
  bool _saving  = false;
  String? _error;

  final _nameArCtrl   = TextEditingController();
  final _nameEnCtrl   = TextEditingController();
  final _descArCtrl   = TextEditingController();
  final _descEnCtrl   = TextEditingController();
  final _priceCtrl    = TextEditingController();
  final _tagInputCtrl = TextEditingController();

  int?  _imageResourceId;
  bool  _removeAvatar = false;
  List<int>    _galleryIds = [];
  List<String> _tags       = [];

  int?  _categoryId;
  bool  _active = true;
  List<Map<String, dynamic>> _categories = [];

  bool get _isCreate => widget.productId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _descArCtrl.dispose();
    _descEnCtrl.dispose();
    _priceCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      if (_isCreate) {
        // Only need categories
        final cats = (await ApiClient().getReportCategories(token))
            .cast<Map<String, dynamic>>();
        if (!mounted) return;
        setState(() { _categories = cats; _loading = false; });
      } else {
        final results = await Future.wait([
          ApiClient().getProductDetail(widget.productId!),
          ApiClient().getReportCategories(token),
        ]);
        if (!mounted) return;
        final product = results[0] as Map<String, dynamic>;
        final cats    = (results[1] as List).cast<Map<String, dynamic>>();
        final price   = product['price'];
        setState(() {
          _nameArCtrl.text = _str(product['name'], 'ar');
          _nameEnCtrl.text = _str(product['name'], 'en');
          _descArCtrl.text = _str(product['description'], 'ar');
          _descEnCtrl.text = _str(product['description'], 'en');
          _priceCtrl.text  = price?.toString() ?? '';
          _imageResourceId = product['imageResourceId'] as int?;
          _galleryIds = ((product['imageResourceIds'] as List?)?.cast<int>()) ?? [];
          _tags       = ((product['tags'] as List?)?.cast<String>()) ?? [];
          _categoryId = product['categoryId'] as int?;
          _active     = product['active'] != false;
          _categories = cats;
          _loading    = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _str(dynamic raw, String lang) {
    if (raw == null) return '';
    if (raw is Map) return raw[lang]?.toString() ?? '';
    return '';
  }

  String _catName(Map<String, dynamic> c) {
    final n = c['name_en'] ?? c['name'] ?? '';
    if (n.toString().startsWith('{')) {
      try {
        final m = Map<String, dynamic>.from(n as Map);
        return m['en'] ?? m['ar'] ?? '';
      } catch (_) {}
    }
    return n.toString();
  }

  Future<void> _pickAvatar() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final result = await showImageSourcePicker(context,
        storeSlug: widget.storeSlug, token: token);
    if (result == null || !mounted) return;
    setState(() { _imageResourceId = result.resourceId; _removeAvatar = false; });
  }

  Future<void> _addGalleryImage() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final result = await showImageSourcePicker(context,
        storeSlug: widget.storeSlug, token: token);
    if (result == null || !mounted) return;
    setState(() => _galleryIds.add(result.resourceId));
  }

  void _addTag() {
    final tag = _tagInputCtrl.text.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() { _tags.add(tag); _tagInputCtrl.clear(); });
  }

  Future<void> _save() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; });
    final api = ApiClient();
    try {
      final priceVal = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
      final body = <String, dynamic>{
        'name':        {'ar': _nameArCtrl.text.trim(), 'en': _nameEnCtrl.text.trim()},
        'description': {'ar': _descArCtrl.text.trim(), 'en': _descEnCtrl.text.trim()},
        'price':       priceVal,
        'active':      _active,
        'tags':        _tags,
        if (_categoryId != null) 'categoryId': _categoryId,
        if (_removeAvatar) 'imageResourceId': null
        else if (_imageResourceId != null) 'imageResourceId': _imageResourceId,
      };

      int productId;
      if (_isCreate) {
        productId = await api.createProduct(body, token: token);
      } else {
        await api.patchProduct(widget.productId!, body, token: token);
        productId = widget.productId!;
      }

      // Sync gallery images
      if (true) {
        final fresh = await api.getProductDetail(productId);
        if (!mounted) return;
        final serverIds = ((fresh['imageResourceIds'] as List?)?.cast<int>() ?? []).toSet();
        final localIds  = _galleryIds.toSet();
        for (final id in localIds.difference(serverIds)) {
          await api.addProductGalleryImage(productId, id, token: token);
        }
        for (final id in serverIds.difference(localIds)) {
          await api.removeProductGalleryImage(productId, id, token: token);
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.products),
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
                      Text(
                        _isCreate ? 'New Product' : 'Edit Product',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      if (!_loading)
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(_isCreate ? 'Create' : 'Save'),
                        ),
                    ],
                  ),
                ),
                // Form body
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Avatar
                                  Center(
                                    child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                      GestureDetector(
                                        onTap: _pickAvatar,
                                        child: CircleAvatar(
                                          radius: 52,
                                          backgroundColor:
                                              scheme.surfaceContainerHighest,
                                          child: ClipOval(
                                            child: (_imageResourceId != null &&
                                                    !_removeAvatar)
                                                ? ProductImage(
                                                    imageResourceId:
                                                        _imageResourceId,
                                                    width: 104,
                                                    height: 104)
                                                : Icon(
                                                    Icons.add_a_photo_outlined,
                                                    size: 36,
                                                    color:
                                                        scheme.onSurfaceVariant),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: GestureDetector(
                                          onTap: _pickAvatar,
                                          child: CircleAvatar(
                                              radius: 16,
                                              backgroundColor: scheme.primary,
                                              child: Icon(Icons.edit,
                                                  size: 16,
                                                  color: scheme.onPrimary)),
                                        ),
                                      ),
                                      if (_imageResourceId != null &&
                                          !_removeAvatar)
                                        Positioned(
                                          top: -4,
                                          right: -4,
                                          child: GestureDetector(
                                            onTap: () => setState(
                                                () => _removeAvatar = true),
                                            child: CircleAvatar(
                                                radius: 12,
                                                backgroundColor: scheme.error,
                                                child: Icon(Icons.close,
                                                    size: 14,
                                                    color: scheme.onError)),
                                          ),
                                        ),
                                    ]),
                                  ),
                                  const SizedBox(height: 28),

                                  // Active toggle
                                  Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                          color: scheme.outlineVariant),
                                    ),
                                    child: SwitchListTile(
                                      title: const Text('Enabled',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                          _active
                                              ? 'Product is visible in the kiosk'
                                              : 'Product is hidden from the kiosk',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.outline)),
                                      value: _active,
                                      onChanged: (v) =>
                                          setState(() => _active = v),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Gallery
                                  ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Gallery',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall),
                                        TextButton.icon(
                                          onPressed: _addGalleryImage,
                                          icon: const Icon(
                                              Icons.add_photo_alternate_outlined,
                                              size: 18),
                                          label: const Text('Add'),
                                        ),
                                      ],
                                    ),
                                    if (_galleryIds.isEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(
                                            'No gallery images yet',
                                            style: TextStyle(
                                                color: scheme.outline,
                                                fontSize: 13)),
                                      )
                                    else
                                      SizedBox(
                                        height: 90,
                                        child: ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _galleryIds.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(width: 8),
                                          itemBuilder: (_, i) {
                                            final rid = _galleryIds[i];
                                            return Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: ProductImage(
                                                    imageResourceId: rid,
                                                    width: 80,
                                                    height: 80),
                                              ),
                                              Positioned(
                                                top: -6,
                                                right: -6,
                                                child: GestureDetector(
                                                  onTap: () => setState(() =>
                                                      _galleryIds.removeAt(i)),
                                                  child: CircleAvatar(
                                                      radius: 11,
                                                      backgroundColor:
                                                          scheme.error,
                                                      child: Icon(Icons.close,
                                                          size: 12,
                                                          color:
                                                              scheme.onError)),
                                                ),
                                              ),
                                            ]);
                                          },
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                  ],

                                  // Category
                                  Text('Category',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<int?>(
                                    value: _categoryId,
                                    decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true),
                                    hint: const Text('No category'),
                                    items: [
                                      const DropdownMenuItem(
                                          value: null,
                                          child: Text('No category')),
                                      ..._categories.map((c) =>
                                          DropdownMenuItem(
                                            value: (c['id'] as num).toInt(),
                                            child: Text(_catName(c)),
                                          )),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _categoryId = v),
                                  ),
                                  const SizedBox(height: 20),

                                  // Price
                                  Text('Price',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _priceCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Price (SAR)',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Name
                                  Text('Name',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _nameArCtrl,
                                    textDirection: TextDirection.rtl,
                                    decoration: const InputDecoration(
                                        labelText: 'Arabic',
                                        border: OutlineInputBorder()),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _nameEnCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'English',
                                        border: OutlineInputBorder()),
                                  ),
                                  const SizedBox(height: 20),

                                  // Description
                                  Text('Description',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _descArCtrl,
                                    textDirection: TextDirection.rtl,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                        labelText: 'Arabic',
                                        border: OutlineInputBorder(),
                                        alignLabelWithHint: true),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _descEnCtrl,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                        labelText: 'English',
                                        border: OutlineInputBorder(),
                                        alignLabelWithHint: true),
                                  ),
                                  const SizedBox(height: 20),

                                  // Tags
                                  Text('Tags',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _tagInputCtrl,
                                        onSubmitted: (_) => _addTag(),
                                        decoration: const InputDecoration(
                                            labelText: 'Add tag',
                                            border: OutlineInputBorder(),
                                            isDense: true),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.tonal(
                                        onPressed: _addTag,
                                        child: const Text('Add')),
                                  ]),
                                  if (_tags.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: _tags
                                            .map((t) => Chip(
                                                  label: Text(t,
                                                      style: const TextStyle(
                                                          fontSize: 12)),
                                                  onDeleted: () => setState(
                                                      () => _tags.remove(t)),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ))
                                            .toList(),
                                      ),
                                    ),

                                  if (_error != null) ...[
                                    const SizedBox(height: 16),
                                    Text(_error!,
                                        style: const TextStyle(
                                            color: Colors.red, fontSize: 13)),
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
}
