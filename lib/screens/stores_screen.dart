import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  List<Store>? _stores;
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
    if (token == null) { _redirectLogin(); return; }
    try {
      final stores = await ApiClient().getAdminStores(token);
      if (!mounted) return;
      setState(() { _stores = stores; _loading = false; });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.stores),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, style: TextStyle(color: scheme.error)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ]))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                            child: Row(
                              children: [
                                Text('Stores',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                FilledButton.icon(
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('New Store'),
                                  onPressed: () => Navigator.of(context)
                                      .pushNamed(Routes.storeEdit, arguments: null)
                                      .then((r) { if (r == true && mounted) _load(); }),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(24),
                                itemCount: _stores?.length ?? 0,
                                itemBuilder: (_, i) {
                                  final s = _stores![i];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: scheme.primaryContainer,
                                        child: Text(
                                          s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                                          style: TextStyle(color: scheme.onPrimaryContainer,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      title: Text(s.label(), style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text(s.name,
                                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _StoreActionBtn(
                                            label: 'Categories',
                                            icon: Icons.category_outlined,
                                            onTap: () => Navigator.of(context)
                                                .pushNamed(Routes.categories, arguments: s),
                                          ),
                                          const SizedBox(width: 4),
                                          _StoreActionBtn(
                                            label: 'Resources',
                                            icon: Icons.folder_outlined,
                                            onTap: () => Navigator.of(context)
                                                .pushNamed(Routes.resourceExplorer, arguments: s),
                                          ),
                                          const SizedBox(width: 4),
                                          _StoreActionBtn(
                                            label: 'Payment',
                                            icon: Icons.payment_outlined,
                                            onTap: () => Navigator.of(context)
                                                .pushNamed(Routes.paymentMethods, arguments: s),
                                          ),
                                          const SizedBox(width: 4),
                                          _StoreActionBtn(
                                            label: 'Receipt',
                                            icon: Icons.receipt_long_outlined,
                                            onTap: () => Navigator.of(context)
                                                .pushNamed(Routes.receiptInfoEdit, arguments: s),
                                          ),
                                          const SizedBox(width: 4),
                                          _StoreActionBtn(
                                            label: 'Landing',
                                            icon: Icons.web_outlined,
                                            onTap: () => Navigator.of(context)
                                                .pushNamed(Routes.landingEditor, arguments: s),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined),
                                            tooltip: 'Edit store',
                                            onPressed: () => Navigator.of(context)
                                                .pushNamed(Routes.storeEdit, arguments: s)
                                                .then((r) { if (r == true && mounted) _load(); }),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
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

class _StoreActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _StoreActionBtn({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: IconButton(
          icon: Icon(icon, size: 20),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
        ),
      );
}
