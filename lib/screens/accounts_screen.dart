import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_user.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<AccountUser>? _accounts;
  bool _loading = true;
  String? _error;
  String? _filter;

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
      final list = await ApiClient().getAdminAccounts(token, accountType: _filter);
      if (!mounted) return;
      setState(() { _accounts = list; _loading = false; });
    } on ApiException catch (e) {
      if (e.statusCode == 401) { _redirectLogin(); return; }
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _toggleEnabled(AccountUser u) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      await ApiClient().patchAdminAccount(u.id, {'enabled': !u.enabled}, token: token);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(AccountUser u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text('Delete "${u.username}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      await ApiClient().deleteAdminAccount(u.id, token: token);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.accounts),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Accounts',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.person_add_outlined, size: 18),
                        label: const Text('New Account'),
                        onPressed: () => Navigator.of(context)
                            .pushNamed(Routes.accountEdit, arguments: null)
                            .then((_) => _load()),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(label: 'All', selected: _filter == null,
                            onTap: () { setState(() => _filter = null); _load(); }),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'Human', selected: _filter == 'HUMAN',
                            onTap: () { setState(() => _filter = 'HUMAN'); _load(); }),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'Kiosk', selected: _filter == 'KIOSK',
                            onTap: () { setState(() => _filter = 'KIOSK'); _load(); }),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_error!, style: TextStyle(color: scheme.error)),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _load, child: const Text('Retry')),
                            ]))
                          : _accounts == null || _accounts!.isEmpty
                              ? const Center(child: Text('No accounts found.'))
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 100),
                                    itemCount: _accounts!.length,
                                    itemBuilder: (_, i) => _AccountCard(
                                      account: _accounts![i],
                                      onEdit: () => Navigator.of(context)
                                          .pushNamed(Routes.accountEdit, arguments: _accounts![i])
                                          .then((_) => _load()),
                                      onToggle: () => _toggleEnabled(_accounts![i]),
                                      onDelete: () => _delete(_accounts![i]),
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 13,
        )),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AccountUser account;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _AccountCard({required this.account, required this.onEdit,
      required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final u = account;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _typeColor(u.accountType, scheme).withValues(alpha: 0.15),
              child: Text(u.initials, style: TextStyle(
                color: _typeColor(u.accountType, scheme),
                fontWeight: FontWeight.w700, fontSize: 18,
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(u.username, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(width: 8),
                    _TypeBadge(u.accountType),
                    if (!u.enabled) ...[
                      const SizedBox(width: 6),
                      _Badge('Disabled', Colors.grey),
                    ],
                  ]),
                  if (u.displayName != u.username) ...[
                    const SizedBox(height: 2),
                    Text(u.displayName, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, children: [
                    if (u.roleName != null)
                      Text(u.roleName!, style: TextStyle(fontSize: 12, color: scheme.primary,
                          fontWeight: FontWeight.w500)),
                    if (u.storeName != null)
                      Text(u.storeName!, style: TextStyle(fontSize: 12, color: scheme.outline)),
                    if (u.lastLoginAt != null)
                      Text('Last login: ${_fmtDate(u.lastLoginAt!)}',
                          style: TextStyle(fontSize: 11, color: scheme.outline)),
                  ]),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'toggle') onToggle();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'toggle', child: Text(u.enabled ? 'Disable' : 'Enable')),
                const PopupMenuItem(value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type, ColorScheme scheme) => switch (type) {
        'KIOSK' => Colors.deepPurple,
        'SYSTEM' => Colors.orange,
        _ => scheme.primary,
      };

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (type) {
      'KIOSK' => (Colors.deepPurple.shade50, Colors.deepPurple),
      'SYSTEM' => (Colors.orange.shade50, Colors.orange.shade800),
      _ => (Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(type, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );
}
