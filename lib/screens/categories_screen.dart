import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/category_card.dart';
import '../widgets/framed_card.dart';

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
      body = CardGrid(
        padding: const EdgeInsets.all(16),
        itemCount: _categories!.length,
        itemBuilder: (context, i) {
          final cat = _categories![i];
          return CategoryCard(
            nameEn: (cat.name['en'] ?? cat.name['ar'] ?? '').toString(),
            nameAr: (cat.name['ar'] ?? '').toString(),
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
