import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/role.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/confirm_delete.dart';
import '../widgets/framed_card.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  List<RoleInfo>? _roles;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = context.read<AuthState>().token;
    if (token == null) {
      _redirectLogin();
      return;
    }
    try {
      final list = await ApiClient().getRoles(token);
      if (!mounted) return;
      setState(() {
        _roles = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _redirectLogin();
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _redirectLogin() {
    context.read<AuthState>().logout();
    Navigator.of(context).pushReplacementNamed(Routes.login);
  }

  Future<void> _delete(RoleInfo r) async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final done = await confirmAndDelete(
      context,
      title: 'Delete role?',
      message: 'Delete "${r.name}"? This cannot be undone.',
      action: () => ApiClient().deleteRole(r.id, token: token),
    );
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthState>();
    final canManage = auth.hasPermission('MANAGE_ROLES');
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSidebar(currentRoute: Routes.roles),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pagePad(context), 24, pagePad(context), 8),
                  child: adaptiveRow(context,
                    children: [
                      Text('Roles',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (canManage)
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('New role'),
                          onPressed: () => Navigator.of(context)
                              .pushNamed(Routes.roleEdit, arguments: null)
                              .then((_) => _load()),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_error!, style: TextStyle(color: scheme.error)),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _load, child: const Text('Retry')),
                            ]))
                          : _roles == null || _roles!.isEmpty
                              ? const Center(child: Text('No roles found.'))
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: CardGrid(
                                    itemCount: _roles!.length,
                                    itemBuilder: (_, i) {
                                      final r = _roles![i];
                                      final canEditThis = !r.fixed &&
                                          canManage &&
                                          (!r.builtIn || auth.isSuperAdmin);
                                      return _RoleCard(
                                        role: r,
                                        canEdit: canEditThis,
                                        canDelete: canManage && !r.builtIn,
                                        onOpen: () => Navigator.of(context)
                                            .pushNamed(Routes.roleEdit, arguments: r)
                                            .then((_) => _load()),
                                        onDelete: () => _delete(r),
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

class _RoleCard extends StatelessWidget {
  final RoleInfo role;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _RoleCard({
    required this.role,
    required this.canEdit,
    required this.canDelete,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = role.fixed ? 'Built-in · fixed' : role.builtIn ? 'Built-in' : 'Custom';
    return FramedCard(
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  if (role.fixed) ...[
                    Icon(Icons.lock_outline, size: 16, color: scheme.outline),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(role.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(kind, style: TextStyle(fontSize: 12, color: scheme.outline)),
                if ((role.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(role.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 6),
                Text('${role.permissions.length} permissions · given to ${role.assignedCount}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(onPressed: onOpen, child: Text(canEdit ? 'Edit' : 'View')),
          if (canDelete)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
