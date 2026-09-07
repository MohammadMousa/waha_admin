import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_user.dart';
import '../models/organization.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';

// Accounts (the `users` table) is platform/organization level only now —
// SUPER_ADMIN (system-wide, no organization) or ORGANIZATION_OWNER (scoped
// to one organization). Branch-level identities (BRANCH_ADMIN, OPERATOR,
// CASHIER) are created as Employees, and kiosks as Devices — both scoped to
// a store, not the `users` table.
const _kAccountRoles = ['SUPER_ADMIN', 'ORGANIZATION_OWNER'];

class AccountEditScreen extends StatefulWidget {
  final AccountUser? account;
  const AccountEditScreen({super.key, this.account});

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  bool get _isCreate => widget.account == null;

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  String _role = 'ORGANIZATION_OWNER';
  bool _enabled = true;
  bool _obscurePass = true;

  List<Organization>? _organizations;
  int? _selectedOrgId;
  bool _loadingOrgs = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = widget.account;
    if (u != null) {
      _username.text = u.username;
      _firstName.text = u.firstName ?? '';
      _lastName.text = u.lastName ?? '';
      _phone.text = u.phone ?? '';
      _role = u.roleName ?? 'ORGANIZATION_OWNER';
      _enabled = u.enabled;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrganizations());
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizations() async {
    final token = context.read<AuthState>().token;
    if (token == null) {
      setState(() => _loadingOrgs = false);
      return;
    }
    try {
      final orgs = await ApiClient().getOrganizations(token);
      if (mounted)
        setState(() {
          _organizations = orgs;
          _loadingOrgs = false;
        });
    } on ApiException catch (_) {
      if (mounted) setState(() => _loadingOrgs = false);
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Username is required.');
      return;
    }
    if (_isCreate && _password.text.trim().isEmpty) {
      setState(() => _error = 'Password is required for new accounts.');
      return;
    }
    if (_role == 'ORGANIZATION_OWNER' && _selectedOrgId == null) {
      setState(
        () => _error =
            'An organization is required for Organization Owner accounts.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final token = context.read<AuthState>().token;
    if (token == null) {
      setState(() {
        _saving = false;
        _error = 'Not logged in.';
      });
      return;
    }
    try {
      final api = ApiClient();
      if (_isCreate) {
        await api.createAdminAccount({
          'username': username,
          'password': _password.text.trim(),
          'enabled': _enabled,
          if (_firstName.text.trim().isNotEmpty)
            'firstName': _firstName.text.trim(),
          if (_lastName.text.trim().isNotEmpty)
            'lastName': _lastName.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          'role': _role,
          if (_role == 'ORGANIZATION_OWNER') 'organizationId': _selectedOrgId,
        }, token: token);
      } else {
        await api.patchAdminAccount(widget.account!.id, {
          'enabled': _enabled,
          'firstName': _firstName.text.trim().isNotEmpty
              ? _firstName.text.trim()
              : null,
          'lastName': _lastName.text.trim().isNotEmpty
              ? _lastName.text.trim()
              : null,
          'phone': _phone.text.trim().isNotEmpty ? _phone.text.trim() : null,
          if (_password.text.trim().isNotEmpty)
            'password': _password.text.trim(),
          'role': _role,
          if (_role == 'ORGANIZATION_OWNER' && _selectedOrgId != null)
            'organizationId': _selectedOrgId,
        }, token: token);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted)
        setState(() {
          _error = e.message;
          _saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = <String>{
      ..._kAccountRoles,
      if (_role.isNotEmpty)
        _role, // keep showing a legacy role even if no longer offered
    }.toList();

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.accounts),
          Expanded(
            child: Column(
              children: [
                // Header bar
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border(
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isCreate ? 'New Account' : 'Edit Account',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (!_loadingOrgs)
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                    ],
                  ),
                ),
                // Form body
                Expanded(
                  child: _loadingOrgs
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 540),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Label('Credentials'),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _username,
                                    enabled: _isCreate,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                      labelText: 'Username *',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _password,
                                    obscureText: _obscurePass,
                                    decoration: InputDecoration(
                                      labelText: _isCreate
                                          ? 'Password *'
                                          : 'New password (leave blank to keep)',
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(
                                        Icons.key_outlined,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePass = !_obscurePass,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Enabled'),
                                    subtitle: Text(
                                      _enabled
                                          ? 'Account can log in'
                                          : 'Account is disabled',
                                    ),
                                    value: _enabled,
                                    onChanged: (v) =>
                                        setState(() => _enabled = v),
                                  ),
                                  const Divider(height: 32),
                                  _Label('Role & Organization'),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    value: roles.contains(_role)
                                        ? _role
                                        : roles.first,
                                    decoration: const InputDecoration(
                                      labelText: 'Role',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    items: roles
                                        .map(
                                          (r) => DropdownMenuItem(
                                            value: r,
                                            child: Text(r),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) setState(() => _role = v);
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  if (_role == 'ORGANIZATION_OWNER')
                                    DropdownButtonFormField<int?>(
                                      value: _selectedOrgId,
                                      decoration: const InputDecoration(
                                        labelText: 'Organization *',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(
                                          Icons.apartment_outlined,
                                        ),
                                      ),
                                      items: [
                                        const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text('Select organization'),
                                        ),
                                        ...(_organizations ?? []).map(
                                          (o) => DropdownMenuItem<int?>(
                                            value: o.id,
                                            child: Text(o.name),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _selectedOrgId = v),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.public_outlined,
                                            size: 18,
                                            color: scheme.outline,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'System-wide account — no organization',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const Divider(height: 32),
                                  _Label('Personal Info'),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _firstName,
                                    decoration: const InputDecoration(
                                      labelText: 'First name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _lastName,
                                    decoration: const InputDecoration(
                                      labelText: 'Last name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _phone,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'Phone',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.phone_outlined),
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: scheme.errorContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: scheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 40),
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  );
}
