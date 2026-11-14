import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/role.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';

class RoleEditScreen extends StatefulWidget {
  final RoleInfo? role;
  const RoleEditScreen({super.key, this.role});

  @override
  State<RoleEditScreen> createState() => _RoleEditScreenState();
}

class _RoleEditScreenState extends State<RoleEditScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final Set<String> _selected = {};
  List<PermissionInfo>? _all;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isCreate => widget.role == null;

  @override
  void initState() {
    super.initState();
    final r = widget.role;
    if (r != null) {
      _name.text = r.name;
      _description.text = r.description ?? '';
      _selected.addAll(r.permissions);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    try {
      final list = await ApiClient().getPermissions(token);
      if (mounted) {
        setState(() {
          _all = list;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showErrorDialog(context, e.message);
      }
    }
  }

  bool _readOnly(AuthState auth) {
    final r = widget.role;
    if (r == null) return false;
    if (r.fixed) return true;
    if (!auth.hasPermission('MANAGE_ROLES')) return true;
    return r.builtIn && !auth.isSuperAdmin;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': name,
      'description': _description.text.trim(),
      'permissions': _selected.toList()..sort(),
    };
    try {
      if (_isCreate) {
        await ApiClient().createRole(body, token: token);
      } else {
        await ApiClient().updateRole(widget.role!.id, body, token: token);
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await showErrorDialog(context, e.message);
      }
    }
  }

  /// Groups permissions by the part of the name before the first underscore
  /// (EDIT_PRODUCTS -> EDIT), so the list reads in sections.
  Map<String, List<PermissionInfo>> _grouped() {
    final map = <String, List<PermissionInfo>>{};
    for (final p in _all ?? const <PermissionInfo>[]) {
      if (!p.assignableToRoles) continue;
      final i = p.key.indexOf('_');
      final group = i > 0 ? p.key.substring(0, i) : 'OTHER';
      map.putIfAbsent(group, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthState>();
    final readOnly = _readOnly(auth);
    final groups = _grouped();
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.roles),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            _isCreate ? 'New role' : (readOnly ? 'Role' : 'Edit role'),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 16),
                          if (widget.role?.fixed == true)
                            _Note('This role is fixed and cannot be changed.')
                          else if (readOnly && widget.role != null)
                            _Note('You can only view this role.'),
                          TextField(
                            controller: _name,
                            enabled: !readOnly,
                            maxLength: 60,
                            decoration: const InputDecoration(
                              labelText: 'Name *',
                              counterText: '',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _description,
                            enabled: !readOnly,
                            maxLength: 255,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              counterText: '',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const Divider(height: 32),
                          Row(children: [
                            Text('Permissions (${_selected.length})',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: scheme.primary, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            if (!readOnly)
                              TextButton(
                                onPressed: () => setState(() {
                                  for (final p in _all ?? const <PermissionInfo>[]) {
                                    if (p.assignableToRoles && auth.hasPermission(p.key)) {
                                      _selected.add(p.key);
                                    }
                                  }
                                }),
                                child: const Text('Select all I can give'),
                              ),
                            if (!readOnly)
                              TextButton(
                                onPressed: () => setState(_selected.clear),
                                child: const Text('Clear'),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          for (final e in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Text(e.key,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: scheme.outline)),
                            ),
                            for (final p in e.value)
                              CheckboxListTile(
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                value: _selected.contains(p.key),
                                title: Text(p.key,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 13)),
                                subtitle: Text(
                                  auth.hasPermission(p.key) || _selected.contains(p.key)
                                      ? p.description
                                      : '${p.description} — you do not hold this permission',
                                ),
                                // Can't tick what you don't hold; an already
                                // ticked one can still be removed.
                                onChanged: readOnly ||
                                        (!auth.hasPermission(p.key) &&
                                            !_selected.contains(p.key))
                                    ? null
                                    : (v) => setState(() {
                                          if (v == true) {
                                            _selected.add(p.key);
                                          } else {
                                            _selected.remove(p.key);
                                          }
                                        }),
                              ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!, style: TextStyle(color: scheme.error)),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(readOnly ? 'Back' : 'Cancel'),
                              ),
                              if (!readOnly) ...[
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _saving ? null : _save,
                                  child: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('Save'),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
      );
}
