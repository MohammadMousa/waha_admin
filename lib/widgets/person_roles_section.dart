import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/branch_group.dart';
import '../models/role.dart';
import '../models/store.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import 'error_dialog.dart';

/// Roles given to one person (an account or an employee). Adding and removing
/// save at once, because the server answers with the person's updated list.
class PersonRolesSection extends StatefulWidget {
  /// 'users' for accounts, 'employees' for POS employees.
  final String kind;
  final int personId;
  const PersonRolesSection({super.key, required this.kind, required this.personId});

  @override
  State<PersonRolesSection> createState() => _PersonRolesSectionState();
}

// These can never be given through the roles calls.
const _kNotGivable = {'ORGANIZATION_OWNER', 'SUPER_ADMIN', 'KIOSK'};

class _PersonRolesSectionState extends State<PersonRolesSection> {
  List<RoleAssignment>? _assignments;
  List<RoleInfo> _roles = [];
  List<Store> _stores = [];
  List<BranchGroup> _groups = [];
  bool _loading = true;
  String? _error;

  bool get _isUser => widget.kind == 'users';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _token => context.read<AuthState>().token;

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final api = ApiClient();
      final results = await Future.wait([
        api.getPersonRoles(widget.kind, widget.personId, token: token),
        api.getRoles(token),
        api.getAdminStores(token),
        api.getBranchGroups(token),
      ]);
      if (!mounted) return;
      setState(() {
        _assignments = results[0] as List<RoleAssignment>;
        _roles = results[1] as List<RoleInfo>;
        _stores = results[2] as List<Store>;
        _groups = results[3] as List<BranchGroup>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  String _scopeLabel(RoleAssignment a) {
    switch (a.scopeType) {
      case 'COMPANY':
        return 'Company';
      case 'BRANCH_GROUP':
        final g = _groups.where((g) => g.id == a.scopeId);
        return 'Branch group: ${g.isEmpty ? '#${a.scopeId}' : g.first.name}';
      default:
        final s = _stores.where((s) => s.id == a.scopeId);
        return 'Branch: ${s.isEmpty ? '#${a.scopeId}' : s.first.name}';
    }
  }

  Future<void> _remove(RoleAssignment a) async {
    final token = _token;
    if (token == null) return;
    try {
      final list = await ApiClient().removePersonRole(widget.kind, widget.personId, a, token: token);
      if (mounted) setState(() => _assignments = list);
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    }
  }

  Future<void> _add() async {
    final givable = _roles.where((r) => !(r.builtIn && _kNotGivable.contains(r.name))).toList();
    final picked = await showDialog<_NewAssignment>(
      context: context,
      builder: (_) => _AddRoleDialog(
        roles: givable,
        stores: _stores,
        groups: _groups,
        allowCompany: _isUser,
      ),
    );
    if (picked == null || !mounted) return;
    final token = _token;
    if (token == null) return;
    try {
      final list = await ApiClient().addPersonRole(widget.kind, widget.personId,
          roleId: picked.roleId, scopeType: picked.scopeType, scopeId: picked.scopeId, token: token);
      if (mounted) setState(() => _assignments = list);
    } on ApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: scheme.error));
    }
    final list = _assignments ?? const <RoleAssignment>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('Permissions add up across all roles.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add role'),
          ),
        ]),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Text('No roles given yet.', style: TextStyle(color: scheme.outline))
        else
          for (final a in list)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: a.roleName ?? 'Role #${a.roleId}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: '   ${_scopeLabel(a)}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  ])),
                ),
                IconButton(
                  tooltip: 'Take away',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _remove(a),
                ),
              ]),
            ),
      ],
    );
  }
}

class _NewAssignment {
  final int roleId;
  final String scopeType;
  final int scopeId;
  const _NewAssignment(this.roleId, this.scopeType, this.scopeId);
}

class _AddRoleDialog extends StatefulWidget {
  final List<RoleInfo> roles;
  final List<Store> stores;
  final List<BranchGroup> groups;
  final bool allowCompany;
  const _AddRoleDialog({
    required this.roles,
    required this.stores,
    required this.groups,
    required this.allowCompany,
  });

  @override
  State<_AddRoleDialog> createState() => _AddRoleDialogState();
}

class _AddRoleDialogState extends State<_AddRoleDialog> {
  int? _roleId;
  late String _scopeType = widget.allowCompany ? 'COMPANY' : 'BRANCH';
  int? _targetId;

  @override
  Widget build(BuildContext context) {
    final needsTarget = _scopeType != 'COMPANY';
    final ready = _roleId != null && (!needsTarget || _targetId != null);
    return AlertDialog(
      title: const Text('Add role'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _roleId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              items: [
                for (final r in widget.roles)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (v) => setState(() => _roleId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _scopeType,
              decoration: const InputDecoration(labelText: 'Scope', border: OutlineInputBorder()),
              items: [
                if (widget.allowCompany)
                  const DropdownMenuItem(value: 'COMPANY', child: Text('Company')),
                const DropdownMenuItem(value: 'BRANCH_GROUP', child: Text('Branch group')),
                const DropdownMenuItem(value: 'BRANCH', child: Text('Branch')),
              ],
              onChanged: (v) => setState(() {
                _scopeType = v!;
                _targetId = null;
              }),
            ),
            if (needsTarget) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(_scopeType),
                initialValue: _targetId,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: _scopeType == 'BRANCH' ? 'Branch' : 'Branch group',
                    border: const OutlineInputBorder()),
                items: _scopeType == 'BRANCH'
                    ? [for (final s in widget.stores) DropdownMenuItem(value: s.id, child: Text(s.name))]
                    : [for (final g in widget.groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
                onChanged: (v) => setState(() => _targetId = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: ready
              ? () => Navigator.pop(context, _NewAssignment(_roleId!, _scopeType, needsTarget ? _targetId! : 0))
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
