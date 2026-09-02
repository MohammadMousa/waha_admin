import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/product_image.dart';

/// Global categories screen — always shows categories for the root store (id=1).
class CategoriesAdminScreen extends StatefulWidget {
  const CategoriesAdminScreen({super.key});

  @override
  State<CategoriesAdminScreen> createState() => _CategoriesAdminScreenState();
}

class _CategoriesAdminScreenState extends State<CategoriesAdminScreen> {
  // Root store slug used for the resource picker; adjust if your root differs.
  static const _kRootStoreId   = 1;
  static const _kRootStoreSlug = 'waha';

  List<Category>? _categories;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    if (token == null) { _logout(); return; }
    try {
      final cats = await ApiClient().getCategories(
          storeId: _kRootStoreId, token: token);
      if (mounted) setState(() { _categories = cats; _loading = false; });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _logout(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _logout() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  void _openEdit(Category cat) {
    Navigator.of(context)
        .pushNamed(Routes.categoryEdit, arguments: {
          'store': const Store(
            id: _kRootStoreId,
            name: _kRootStoreSlug,
          ),
          'category': cat,
        })
        .then((_) => _load());
  }

  void _openCreate() {
    Navigator.of(context)
        .pushNamed(Routes.categoryEdit, arguments: {
          'store': const Store(
            id: _kRootStoreId,
            name: _kRootStoreSlug,
          ),
          'category': Category(id: -1, name: {}),
        })
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.categories),
          Expanded(child: _buildContent(scheme)),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Row(
            children: [
              Text('Categories',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Category'),
                onPressed: _openCreate,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(scheme)),
      ],
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _load, child: const Text('Retry')),
      ]));
    }
    if (_categories == null || _categories!.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.category_outlined, size: 64,
            color: scheme.outline.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Text('No categories yet', style: TextStyle(color: scheme.outline)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _openCreate,
          icon: const Icon(Icons.add),
          label: const Text('Add category'),
        ),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 72,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _categories!.length,
        itemBuilder: (_, i) {
          final cat = _categories![i];
          final nameEn = (cat.name['en'] ?? cat.name['ar'] ?? '').toString();
          final nameAr = (cat.name['ar'] ?? '').toString();
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openEdit(cat),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _CategoryThumb(imageResourceId: cat.imageResourceId),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nameEn,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          if (nameAr.isNotEmpty)
                            Text(nameAr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(fontSize: 11, color: scheme.outline)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _openEdit(cat),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryThumb extends StatelessWidget {
  final int? imageResourceId;
  const _CategoryThumb({this.imageResourceId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: imageResourceId != null
            ? ProductImage(
                imageResourceId: imageResourceId, fit: BoxFit.cover)
            : Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.category_outlined,
                    color: scheme.onSurfaceVariant, size: 24),
              ),
      ),
    );
  }
}
