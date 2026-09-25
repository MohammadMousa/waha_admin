import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/category_card.dart';
import '../widgets/framed_card.dart';

/// Global categories screen — always shows categories for the root store (id=1).
class CategoriesAdminScreen extends StatefulWidget {
  const CategoriesAdminScreen({super.key});

  @override
  State<CategoriesAdminScreen> createState() => _CategoriesAdminScreenState();
}

class _CategoriesAdminScreenState extends State<CategoriesAdminScreen> {
  // Root store id categories are always scoped to.
  static const _kRootStoreId = 1;

  List<Category>? _categories;
  List<Store>? _stores;
  bool _loading = true;
  String? _error;

  // Org-wide asset bucket for the image picker — real org slug, same
  // mechanism landing pages use for global (no-branch) resource scope.
  String? get _orgSlug => _stores?.firstOrNull?.orgSlug;

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
      final results = await Future.wait([
        ApiClient().getCategories(storeId: _kRootStoreId, token: token),
        ApiClient().getAdminStores(token).catchError((_) => <Store>[]),
      ]);
      if (!mounted) return;
      final cats = results[0] as List<Category>;
      final stores = results[1] as List<Store>;
      setState(() { _categories = cats; _stores = stores; _loading = false; });
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
    final orgSlug = _orgSlug;
    if (orgSlug == null) {
      showErrorDialog(context, 'No organization found for this account');
      return;
    }
    Navigator.of(context)
        .pushNamed(Routes.categoryEdit, arguments: {
          'storeSlug': orgSlug,
          'category': cat,
        })
        .then((_) => _load());
  }

  void _openCreate() {
    final orgSlug = _orgSlug;
    if (orgSlug == null) {
      showErrorDialog(context, 'No organization found for this account');
      return;
    }
    Navigator.of(context)
        .pushNamed(Routes.categoryEdit, arguments: {
          'storeSlug': orgSlug,
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
      child: CardGrid(
        padding: const EdgeInsets.all(16),
        itemCount: _categories!.length,
        itemBuilder: (_, i) {
          final cat = _categories![i];
          return CategoryCard(
            nameEn: (cat.name['en'] ?? cat.name['ar'] ?? '').toString(),
            nameAr: (cat.name['ar'] ?? '').toString(),
            imageResourceId: cat.imageResourceId,
            onTap: () => _openEdit(cat),
          );
        },
      ),
    );
  }
}
