import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/product_image.dart';

class CategoriesScreen extends StatefulWidget {
  final Store store;
  const CategoriesScreen({super.key, required this.store});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category>? _categories;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    try {
      final cats = await ApiClient().getCategories(storeId: widget.store.id, token: token);
      if (mounted) setState(() { _categories = cats; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _openEdit(Category cat) {
    Navigator.of(context)
        .pushNamed(Routes.categoryEdit, arguments: {'store': widget.store, 'category': cat})
        .then((_) => _load());
  }

  void _openCreate() {
    Navigator.of(context)
        .pushNamed(Routes.categoryEdit, arguments: {
          'store': widget.store,
          'category': Category(id: -1, name: {}),
        })
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_outlined, size: 56, color: scheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_categories == null || _categories!.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined, size: 72, color: scheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No categories yet', style: TextStyle(color: scheme.outline)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            ),
          ],
        ),
      );
    } else {
      body = GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _categories!.length,
        itemBuilder: (context, i) {
          final cat = _categories![i];
          final name = (cat.name['en'] ?? cat.name['ar'] ?? '').toString();
          return _CategoryCard(
            name: name,
            imageResourceId: cat.imageResourceId,
            onTap: () => _openEdit(cat),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.categories),
          Expanded(
            child: Column(
              children: [
                // Header bar
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Categories — ${widget.store.name}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                          icon: const Icon(Icons.refresh_outlined),
                          onPressed: _load),
                      FloatingActionButton.small(
                        onPressed: _openCreate,
                        tooltip: 'Add category',
                        child: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String name;
  final int? imageResourceId;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.imageResourceId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProductImage(imageResourceId: imageResourceId, fit: BoxFit.cover),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
