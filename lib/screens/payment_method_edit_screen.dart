import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/payment_method.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/product_image.dart';
import '../widgets/resource_picker_modal.dart';

const _providers = ['REDIRECT', 'TERMINAL', 'SIMULATED', 'QR_LINK', 'PAYMENT_URL'];
const _modes = ['NORMAL', 'KIOSK', 'SHOPPING'];

class PaymentMethodEditScreen extends StatefulWidget {
  final AdminPaymentMethodView method;
  const PaymentMethodEditScreen({super.key, required this.method});

  @override
  State<PaymentMethodEditScreen> createState() => _PaymentMethodEditScreenState();
}

class _PaymentMethodEditScreenState extends State<PaymentMethodEditScreen> {
  late final TextEditingController _nameEn;
  late final TextEditingController _nameAr;
  late final TextEditingController _sort;
  late final TextEditingController _url;
  late String _provider;
  late Set<String> _selectedModes;
  late bool _offline;
  late bool _active;
  int? _iconId;
  bool _saving = false;

  AdminPaymentMethodView get _m => widget.method;

  @override
  void initState() {
    super.initState();
    _nameEn = TextEditingController(text: (_m.displayName?['en'] ?? '').toString());
    _nameAr = TextEditingController(text: (_m.displayName?['ar'] ?? '').toString());
    _sort = TextEditingController(text: '${_m.sortOrder}');
    _url = TextEditingController(text: _m.paymentUrl ?? '');
    _provider = _m.provider;
    _selectedModes = _m.availableModes.toSet();
    _offline = _m.offlineCapable;
    _active = _m.effectiveActive;
    _iconId = _m.iconResourceId;
  }

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    _sort.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final stores = await ApiClient().getAdminStores(token);
      final slug = stores.firstOrNull?.orgSlug;
      if (slug == null) {
        if (mounted) showErrorDialog(context, 'No organization found to browse images from.');
        return;
      }
      if (!mounted) return;
      final r = await showImageSourcePicker(context,
          orgSlug: slug, token: token, entityType: 'payment_method');
      if (r == null || !mounted) return;
      await ApiClient().setPaymentMethodIcon(_m.id, r.resourceId, token: token);
      if (mounted) setState(() => _iconId = r.resourceId);
    } catch (e) {
      if (mounted) showErrorDialog(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _clearIcon() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      await ApiClient().setPaymentMethodIcon(_m.id, null, token: token);
      if (mounted) setState(() => _iconId = null);
    } catch (e) {
      if (mounted) showErrorDialog(context, e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _save() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final sort = int.tryParse(_sort.text.trim());
    if (sort == null) {
      showErrorDialog(context, 'Sort order must be a whole number.');
      return;
    }
    final body = <String, dynamic>{};
    final en = _nameEn.text.trim(), ar = _nameAr.text.trim();
    if (en != (_m.displayName?['en'] ?? '') || ar != (_m.displayName?['ar'] ?? '')) {
      body['displayName'] = {'ar': ar, 'en': en};
    }
    final providerChanged = _provider != _m.provider;
    if (providerChanged) body['provider'] = _provider;
    final modes = _modes.where(_selectedModes.contains).toList();
    if (modes.toSet().difference(_m.availableModes.toSet()).isNotEmpty ||
        _m.availableModes.toSet().difference(modes.toSet()).isNotEmpty) {
      body['availableModes'] = modes;
    }
    if (_offline != _m.offlineCapable) body['offlineCapable'] = _offline;
    if (_active != _m.effectiveActive) body['active'] = _active;
    if (sort != _m.sortOrder) body['sortOrder'] = sort;
    final url = _url.text.trim();
    if (_provider == 'PAYMENT_URL') {
      if (url != (_m.paymentUrl ?? '')) body['paymentUrl'] = url;
    } else if (_m.paymentUrl != null && _m.paymentUrl!.isNotEmpty) {
      body['paymentUrl'] = null; // leaving PAYMENT_URL: server wants it cleared too
    }
    if (body.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    if (providerChanged) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change the provider?'),
          content: Text('Kiosks and apps will switch this method from ${_m.provider} '
              'to $_provider at their next sync. A wrong choice can stop payments.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient().updatePaymentMethod(_m.id, body, token: token);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorDialog(context, e is ApiException ? e.message : '$e');
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
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 16, 24, 16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                  ),
                  child: Row(children: [
                    BackButton(onPressed: () => Navigator.of(context).pop(false)),
                    Text('Edit Payment Method',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: _iconId != null
                                      ? ProductImage(imageResourceId: _iconId, fit: BoxFit.cover)
                                      : Container(
                                          color: scheme.surfaceContainerHighest,
                                          child: Icon(Icons.payments_outlined,
                                              color: scheme.onSurfaceVariant)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _pickIcon,
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('Change icon'),
                              ),
                              const SizedBox(width: 8),
                              if (_iconId != null)
                                TextButton(
                                    onPressed: _saving ? null : _clearIcon,
                                    child: const Text('Clear')),
                            ]),
                            const SizedBox(height: 4),
                            Text('The icon is saved right away. Cleared = the kiosk uses its built-in icon.',
                                style: TextStyle(fontSize: 12, color: scheme.outline)),
                            const SizedBox(height: 20),
                            TextFormField(
                              initialValue: _m.key,
                              enabled: false,
                              decoration: const InputDecoration(
                                  labelText: 'Key (cannot be changed)', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _nameEn,
                              decoration: const InputDecoration(
                                  labelText: 'Name (English)', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _nameAr,
                              textDirection: TextDirection.rtl,
                              decoration: const InputDecoration(
                                  labelText: 'Name (Arabic)', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _provider,
                              decoration: const InputDecoration(
                                  labelText: 'Provider', border: OutlineInputBorder()),
                              items: [
                                for (final p in _providers) DropdownMenuItem(value: p, child: Text(p)),
                              ],
                              onChanged: (v) => setState(() => _provider = v ?? _provider),
                            ),
                            if (_provider == 'PAYMENT_URL') ...[
                              const SizedBox(height: 16),
                              TextField(
                                controller: _url,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(
                                    labelText: 'Payment URL (https://…)',
                                    border: OutlineInputBorder()),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Text('Available in', style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 4),
                            Wrap(spacing: 8, children: [
                              for (final mode in _modes)
                                FilterChip(
                                  label: Text(mode),
                                  selected: _selectedModes.contains(mode),
                                  onSelected: (v) => setState(() {
                                    v ? _selectedModes.add(mode) : _selectedModes.remove(mode);
                                  }),
                                ),
                            ]),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _sort,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Sort order', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Works offline'),
                              value: _offline,
                              onChanged: (v) => setState(() => _offline = v),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Active'),
                              value: _active,
                              onChanged: (v) => setState(() => _active = v),
                            ),
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
