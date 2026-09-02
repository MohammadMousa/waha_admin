import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/payment_method.dart';
import '../models/store.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';

class PaymentMethodsScreen extends StatefulWidget {
  final Store store;
  const PaymentMethodsScreen({super.key, required this.store});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  bool _loading = false;
  String? _error;
  List<AdminPaymentMethodView> _methods = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    final token = context.read<AuthState>().token;
    try {
      final methods = await ApiClient()
          .getAdminPaymentMethods(storeId: widget.store.id, token: token);
      if (mounted) setState(() { _methods = methods; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle(AdminPaymentMethodView method) async {
    final newActive = !method.effectiveActive;
    final token = context.read<AuthState>().token;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: Card(child: Padding(padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Saving…'),
            ])))),
      ),
    );
    try {
      await ApiClient().setPaymentMethodStoreActive(method.id,
          active: newActive, storeId: widget.store.id, token: token);
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.paymentMethodsGlobal),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Text('Payment Methods',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_outlined),
                        tooltip: 'Refresh',
                        onPressed: _loading ? null : _load,
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_error!, style: TextStyle(color: scheme.error)),
                              const SizedBox(height: 12),
                              OutlinedButton(onPressed: _load, child: const Text('Retry')),
                            ]))
                          : _methods.isEmpty
                              ? Center(child: Text('No payment methods configured',
                                  style: TextStyle(color: scheme.outline)))
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _methods.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                                  itemBuilder: (_, i) {
                                    final m = _methods[i];
                                    final name = (m.displayName?['en'] as String?) ?? m.key;
                                    return CheckboxListTile(
                                      title: Text(name,
                                          style: const TextStyle(fontWeight: FontWeight.w500)),
                                      subtitle: Text(m.provider,
                                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                                      value: m.effectiveActive,
                                      onChanged: (_) => _toggle(m),
                                    );
                                  },
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
