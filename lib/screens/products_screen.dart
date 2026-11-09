import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/localized_name.dart';
import '../utils/number_format.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/product_image.dart';
import '../widgets/waha_filter_controls.dart';
import '../widgets/confirm_delete.dart';
import '../widgets/error_dialog.dart';
import '../widgets/product_view_settings.dart';

// Global parent store id — products are always scoped to this.
const _kRootStoreId = 1;

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  ProductViewSettings _view = const ProductViewSettings();

  bool _transferring = false;

  Future<void> _export(String format) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _transferring = true);
    try {
      final bytes = await ApiClient().exportProducts(token, format);
      final mime = format == 'xlsx'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/csv;charset=utf-8';
      final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));
      html.AnchorElement(href: url)
        ..setAttribute('download', 'products.$format')
        ..click();
      html.Url.revokeObjectUrl(url);
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) showErrorDialog(context, e.toString());
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  /// Pick a file, have the server check it, show what would change, then apply on confirm.
  Future<void> _import() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'xlsx'], withData: true);
    final file = picked?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    setState(() => _transferring = true);
    try {
      final api = ApiClient();
      final check = await api.importProducts(token, bytes, file.name, 'validate');
      if (!mounted) return;
      final errors = (check['errors'] as List? ?? []).cast<Map<String, dynamic>>();
      final confirmed = await _showImportPreview(file.name, check, errors);
      if (confirmed != true || !mounted) return;
      final done = await api.importProducts(token, bytes, file.name, 'apply');
      if (!mounted) return;
      final left = (done['errors'] as List? ?? []).cast<Map<String, dynamic>>();
      if (left.isNotEmpty) {
        await _showImportPreview(file.name, done, left);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Import done: ${fmtCount(done['created'])} created, '
                '${fmtCount(done['updated'])} updated.')));
      }
      await _loadPage(0);
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) showErrorDialog(context, e.toString());
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  /// Summary of a validate (or failed apply) result; true when the user chooses Import.
  Future<bool?> _showImportPreview(
      String name, Map<String, dynamic> r, List<Map<String, dynamic>> errors) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(errors.isEmpty ? 'Import $name' : 'Import has errors'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${fmtCount(r['created'])} to create, ${fmtCount(r['updated'])} to update, '
                  '${fmtCount(r['unchanged'])} unchanged.'),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('${errors.length} error(s). Nothing was imported.',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in errors)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('Row ${e['row']}${e['field'] != null ? ' · ${e['field']}' : ''}: ${e['message']}'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(errors.isEmpty ? 'Cancel' : 'Close')),
          if (errors.isEmpty)
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
  }

  Future<void> _openViewSettings() async {
    final r = await showProductViewSettingsDialog(context, _view);
    if (r == null || !mounted) return;
    setState(() => _view = r);
    await r.save();
  }

  List<Category> _categories = [];
  Category? _selectedCategory;
  bool? _activeFilter;

  List<Map<String, dynamic>> _products = [];
  int _page = 0;
  bool _hasMore = false;

  bool _loading = true;
  bool _loadingProducts = false;
  String? _error;

  List<Store>? _stores;
  // Org-wide asset bucket for the image picker — real org slug, same
  // mechanism landing pages use for global (no-branch) resource scope.
  String? get _orgSlug => _stores?.firstOrNull?.orgSlug;

  final _scrollCtrl = ScrollController();
  // Product just saved: kept in place and shown with a short highlight.
  int? _highlightId;
  Timer? _highlightTimer;

  final _searchCtrl = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    ProductViewSettings.load().then((v) { if (mounted) setState(() => _view = v); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchTimer?.cancel();
    _highlightTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 400), () => _loadPage(0));
  }

  Future<void> _init() async {
    final token = context.read<AuthState>().token;
    if (token == null) { _logout(); return; }
    try {
      final results = await Future.wait([
        ApiClient().getCategories(storeId: _kRootStoreId, token: token)
            .catchError((_) => <Category>[]),
        ApiClient().getProducts(
          storeId: _kRootStoreId,
          page: 0,
          size: 24,
          token: token,
        ),
        ApiClient().getAdminStores(token).catchError((_) => <Store>[]),
      ]);
      if (!mounted) return;
      final cats = results[0] as List<Category>;
      final data  = results[1] as Map<String, dynamic>;
      final stores = results[2] as List<Store>;
      setState(() {
        _categories = cats;
        _products   = (data['products'] as List? ?? []).cast<Map<String, dynamic>>();
        _hasMore    = data['hasMore'] == true;
        _stores     = stores;
        _loading    = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _logout(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _loadPage(int page) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() { _loadingProducts = true; _error = null; });
    try {
      final data = await ApiClient().getProducts(
        storeId: _kRootStoreId,
        categoryId: _selectedCategory?.id,
        page: page,
        size: 24,
        token: token,
      );
      if (!mounted) return;
      var items = (data['products'] as List? ?? []).cast<Map<String, dynamic>>();

      if (_activeFilter != null) {
        items = items.where((p) => p['active'] == _activeFilter).toList();
      }

      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        items = items.where((p) {
          final name = _flatName(p['name']).toLowerCase();
          final barcode = (p['barcode'] ?? '').toString().toLowerCase();
          return name.contains(q) || barcode.contains(q);
        }).toList();
      }

      setState(() {
        _products = items;
        _page     = page;
        _hasMore  = data['hasMore'] == true;
        _loadingProducts = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loadingProducts = false; });
    }
  }

  String _flatName(dynamic name) => parseLocalizedName(name, fallback: '');

  void _logout() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  /// After the edit screen saves: keep the page as it is, put the new values
  /// in the same spot (a new product goes first on this page), and highlight it.
  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    final token = context.read<AuthState>().token!;
    final name = parseLocalizedName(p['name'], fallback: '');
    final done = await confirmAndDelete(
      context,
      title: 'Delete product?',
      message: 'Delete "$name" permanently? This cannot be undone.',
      action: () => ApiClient().deleteProduct((p['id'] as num).toInt(), token),
    );
    if (done && mounted) _loadPage(_page);
  }

  Future<void> _afterSave(Object? result, {required bool created}) async {
    if (result is! int) return; // closed without saving
    try {
      final fresh = await ApiClient().getProductDetail(result);
      if (!mounted) return;
      setState(() {
        final i = _products.indexWhere((p) => p['id'] == result);
        if (i >= 0) {
          _products[i] = {..._products[i], ...fresh};
        } else if (created) {
          _products.insert(0, fresh);
        }
        _highlightId = result;
      });
      if (created && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlightId = null);
      });
    } on ApiException {
      if (mounted) _loadPage(_page);
    }
  }

  void _openCreate() {
    final orgSlug = _orgSlug;
    if (orgSlug == null) {
      showErrorDialog(context, 'No organization found for this account');
      return;
    }
    Navigator.of(context)
        .pushNamed(Routes.productEdit, arguments: {
          'productId': null,
          'storeSlug': orgSlug,
        })
        .then((r) => _afterSave(r, created: true));
  }

  void _openEdit(Map<String, dynamic> p) {
    final orgSlug = _orgSlug;
    if (orgSlug == null) {
      showErrorDialog(context, 'No organization found for this account');
      return;
    }
    Navigator.of(context)
        .pushNamed(Routes.productEdit, arguments: {
          'productId': p['id'] as int,
          'storeSlug': orgSlug,
        })
        .then((r) => _afterSave(r, created: false));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.products),
          Expanded(child: _buildContent(scheme)),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(scheme),
        Expanded(child: _buildBody(scheme)),
        if (_products.isNotEmpty || _page > 0) _buildPagination(scheme),
      ],
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Products',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_loadingProducts)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Display settings',
                onPressed: _openViewSettings,
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Export products',
                enabled: !_transferring,
                onSelected: _export,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'csv', child: Text('Export as CSV')),
                  PopupMenuItem(value: 'xlsx', child: Text('Export as Excel (XLSX)')),
                ],
                child: IgnorePointer(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Export'),
                    onPressed: _transferring ? null : () {},
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import'),
                onPressed: _transferring ? null : _import,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Product'),
                onPressed: _openCreate,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Category filter
              if (_categories.isNotEmpty)
                WahaFilterDropdown<Category?>(
                  value: _selectedCategory,
                  hint: 'Select Category',
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Select Category')),
                    ..._categories.map((c) {
                      final name = (c.name['en'] ?? c.name['ar'] ?? '').toString();
                      return DropdownMenuItem(value: c, child: Text(name));
                    }),
                  ],
                  onChanged: (c) {
                    setState(() => _selectedCategory = c);
                    _loadPage(0);
                  },
                ),
              // Status filter
              WahaFilterDropdown<bool?>(
                value: _activeFilter,
                hint: 'Select Status',
                items: const [
                  DropdownMenuItem(value: null, child: Text('Select Status')),
                  DropdownMenuItem(value: true, child: Text('Enabled')),
                  DropdownMenuItem(value: false, child: Text('Disabled')),
                ],
                onChanged: (v) {
                  setState(() => _activeFilter = v);
                  _loadPage(0);
                },
              ),
              // Search
              WahaSearchField(
                controller: _searchCtrl,
                hintText: 'Search products…',
                onClear: () {
                  _searchTimer?.cancel();
                  _loadPage(0);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => _loadPage(_page), child: const Text('Retry')),
      ]));
    }
    if (!_loadingProducts && _products.isEmpty) {
      return Center(child: Text('No products found',
          style: TextStyle(color: scheme.outline)));
    }

    return LayoutBuilder(builder: (context, box) {
      const pad = 20.0, gap = 10.0;
      final avail = box.maxWidth - pad * 2;
      final cols = _view.columns > 0
          ? _view.columns
          : (avail / (210 + gap)).ceil().clamp(1, 20);
      final itemW = (avail - gap * (cols - 1)) / cols;
      // image square-ish, then room for 2 name lines + price + category + badge
      final textH = _view.nameSize * 1.3 * 2 + _view.priceSize * 1.4 + 10 * 1.4 + 4 + 20 + 16;
      return GridView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(pad),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisExtent: itemW * (_view.imagePercent / 100) + textH,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
        ),
        itemCount: _products.length,
        itemBuilder: (_, i) {
          final p = _products[i];
          final catId = p['categoryId'];
          final catName = catId == null
              ? null
              : _categories
                  .where((c) => c.id == catId)
                  .map((c) => (c.name['en'] ?? c.name['ar'] ?? '').toString())
                  .firstOrNull;
          return _ProductCard(
            product: p,
            highlighted: p['id'] == _highlightId,
            categoryName: catName,
            view: _view,
            onEdit: () => _openEdit(p),
            onDelete: context.read<AuthState>().hasPermission('EDIT_PRODUCTS')
                ? () => _deleteProduct(p)
                : null,
          );
        },
      );
    });
  }

  Widget _buildPagination(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          Text('Page ${_page + 1}',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
          const Spacer(),
          TextButton(
            onPressed:
                _page > 0 && !_loadingProducts ? () => _loadPage(_page - 1) : null,
            child: const Text('← Previous'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed:
                _hasMore && !_loadingProducts ? () => _loadPage(_page + 1) : null,
            child: const Text('Next →'),
          ),
        ],
      ),
    );
  }
}

// ── Product card ──────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool highlighted;
  final String? categoryName;
  final ProductViewSettings view;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _ProductCard({
    required this.product,
    this.highlighted = false,
    this.categoryName,
    required this.view,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name   = _flatName(product['name']);
    final price  = product['price'];
    final active = product['active'] != false;
    final imageId = product['imageResourceId'] as int?;

    final (statusBg, statusFg, statusLabel) = active
        ? (Colors.green.shade50, Colors.green.shade700, 'Enabled')
        : (Colors.red.shade50, Colors.red.shade700, 'Disabled');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: highlighted
            ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.55), blurRadius: 12, spreadRadius: 2)]
            : const [],
      ),
      child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ProductImage(imageResourceId: imageId, fit: BoxFit.cover),
                if (!active)
                  Container(color: Colors.black12),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: view.nameSize,
                              height: 1.3)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      tooltip: 'Edit',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: onEdit,
                    ),
                    if (onDelete != null)
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 16, color: scheme.error),
                        tooltip: 'Delete',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: onDelete,
                      ),
                  ],
                ),
                if (price != null)
                  Row(
                    children: [
                      Flexible(
                        child: Text('SAR ${fmtMoney(price)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: view.priceSize,
                                color: scheme.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                      // The list shows the price with VAT unless the organization
                      // turned that off, in which case it differs from priceWithVat.
                      if (product['priceWithVat'] != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (price as num) == (product['priceWithVat'] as num)
                                ? 'incl. VAT'
                                : 'excl. VAT',
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ],
                  ),
                if (categoryName != null && categoryName!.isNotEmpty)
                  Text(categoryName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10, color: scheme.outline)),
                const SizedBox(height: 4),
                // Status badge — always shown
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          fontSize: 10,
                          color: statusFg,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _flatName(dynamic name) => parseLocalizedName(name, fallback: '');
}
