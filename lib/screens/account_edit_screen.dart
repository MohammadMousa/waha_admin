import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_user.dart';
import '../models/organization.dart';
import '../models/role.dart';
import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/person_roles_section.dart';
import '../widgets/personal_details_form.dart';
import '../widgets/form_page.dart';
import '../widgets/error_dialog.dart';

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

  /// With the permission to give roles, an existing account's roles are managed
  /// in the roles list (saved at once). Owners and super admins keep the single
  /// dropdown, because those roles cannot be given through the roles list.
  bool get _roleListMode => !_isCreate && context.read<AuthState>().hasPermission('ASSIGN_ROLES');
  final List<RoleAssignment> _pendingRoles = [];
  bool get _canAssignRoles => context.read<AuthState>().hasPermission('ASSIGN_ROLES');

  bool get _hasBuiltInTopRole => _role == 'ORGANIZATION_OWNER' || _role == 'SUPER_ADMIN';

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  // Full personal profile (api level 5): name, phone, email, gender, birth
  // date, language and picture. Older servers keep the three fields above.
  final _pd = PersonalDetailsController();
  int? _avatarId;
  Uint8List? _pendingAvatar; // chosen for a new account, uploaded after creating it
  String _pendingAvatarName = 'photo.jpg';
  bool _avatarBusy = false;
  bool get _hasProfile => context.read<AuthState>().apiLevel >= 5;

  // null = a regular account with no role (can sign in, can do nothing yet)
  String? _role;
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
      _role = u.roleName;
      _enabled = u.enabled;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrganizations();
      _loadProfile();
    });
  }

  Future<void> _loadProfile() async {
    final token = context.read<AuthState>().token;
    if (token == null || !_hasProfile || _isCreate) return;
    try {
      final p = await ApiClient().getAdminProfile(token, widget.account!.id);
      if (!mounted) return;
      setState(() {
        _pd.apply(p);
        _avatarId = (p['avatarResourceId'] as num?)?.toInt();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pickAvatar() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png'], withData: true);
    final file = res?.files.single;
    if (file == null || file.bytes == null || !mounted) return;
    if (file.size > 5 * 1024 * 1024) {
      showErrorDialog(context, 'The picture is too large (5 MB at most).');
      return;
    }
    if (_isCreate) {
      // The account does not exist yet: keep the picture until it is created.
      setState(() {
        _pendingAvatar = file.bytes;
        _pendingAvatarName = file.name;
      });
      return;
    }
    setState(() => _avatarBusy = true);
    try {
      final p = await ApiClient().uploadAdminAvatar(token, widget.account!.id, file.bytes!, file.name);
      if (mounted) {
        setState(() {
          _avatarId = (p['avatarResourceId'] as num?)?.toInt();
          _avatarBusy = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _avatarBusy = false);
        showErrorDialog(context, e.message);
      }
    }
  }

  Future<void> _removeAvatar() async {
    if (_isCreate) {
      setState(() => _pendingAvatar = null);
      return;
    }
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _avatarBusy = true);
    try {
      await ApiClient().deleteAdminAvatar(token, widget.account!.id);
      if (mounted) {
        setState(() {
          _avatarId = null;
          _avatarBusy = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _avatarBusy = false);
        showErrorDialog(context, e.message);
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _pd.dispose();
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
    // An existing account's organization can't be changed, so only a new
    // Organization Owner has to pick one.
    if (_isCreate && _role == 'ORGANIZATION_OWNER' && _selectedOrgId == null) {
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
        final newId = await api.createAdminAccount({
          'username': username,
          'password': _password.text.trim(),
          'enabled': _enabled,
          if (!_hasProfile) ...{
            if (_firstName.text.trim().isNotEmpty) 'firstName': _firstName.text.trim(),
            if (_lastName.text.trim().isNotEmpty) 'lastName': _lastName.text.trim(),
            if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          },
          if (_role != null) 'role': _role,
          // Super admins are system-wide; everyone else belongs to the chosen
          // organization (the server uses its default one when none is sent).
          if (_role != 'SUPER_ADMIN' && _selectedOrgId != null)
            'organizationId': _selectedOrgId,
        }, token: token);
        if (_pendingRoles.isNotEmpty) {
          final problem = await givePendingRoles('users', newId, _pendingRoles, token);
          if (problem != null && mounted) await showErrorDialog(context, problem);
        }
        if (_hasProfile) {
          // The account exists now; a failure here must not lose it.
          try {
            final fields = _pd.filled();
            if (fields.isNotEmpty) await api.updateAdminProfile(token, newId, fields);
            if (_pendingAvatar != null) {
              await api.uploadAdminAvatar(token, newId, _pendingAvatar!, _pendingAvatarName);
            }
          } on ApiException catch (e) {
            if (mounted) {
              await showErrorDialog(context,
                  'The account was created, but its personal details were not saved: ${e.message}');
            }
          }
        }
      } else {
        await api.patchAdminAccount(widget.account!.id, {
          'enabled': _enabled,
          if (!_hasProfile) ...{
            'firstName': _firstName.text.trim().isNotEmpty ? _firstName.text.trim() : null,
            'lastName': _lastName.text.trim().isNotEmpty ? _lastName.text.trim() : null,
            'phone': _phone.text.trim().isNotEmpty ? _phone.text.trim() : null,
          },
          if (_password.text.trim().isNotEmpty)
            'password': _password.text.trim(),
          // Only when it changed; the server can switch a role but not remove it.
          if (_role != null && _role != widget.account!.roleName) 'role': _role,
        }, token: token);
        if (_hasProfile) {
          final changed = _pd.changed();
          if (changed.isNotEmpty) {
            await api.updateAdminProfile(token, widget.account!.id, changed);
          }
        }
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
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    final roles = <String>{
      ..._kAccountRoles,
      if (_role != null && _role!.isNotEmpty)
        _role!, // keep showing a legacy role even if no longer offered
    }.toList();
    // The server can switch an existing role but never clear it, so "No role"
    // is only offered for new accounts and for accounts that have none.
    final canPickNoRole = _isCreate || widget.account!.roleName == null;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSidebar(currentRoute: Routes.accounts),
          Expanded(
            child: Column(
              children: [
                FormPageHeader(
                  title: _isCreate ? 'New Account' : 'Edit Account',
                  showSave: !_loadingOrgs,
                  saving: _saving,
                  onSave: _save,
                ),
                // Form body
                Expanded(
                  child: _loadingOrgs
                      ? const Center(child: CircularProgressIndicator())
                      : FormPageBody(
                          children: [
                                  if (_hasProfile) ...[
                                  PersonAvatar(
                                    avatarId: _avatarId,
                                    pendingBytes: _pendingAvatar,
                                    busy: _avatarBusy,
                                    onPick: _pickAvatar,
                                    onRemove: _removeAvatar,
                                  ),
                                  const SizedBox(height: 24),
                                  ],
                                  FormSectionLabel('Credentials'),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _username,
                                    enabled: _isCreate,
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                      labelText: 'Username *',
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
                                  FormSectionLabel('Account level & Organization'),
                                  const SizedBox(height: 12),
                                  if (!_roleListMode || _hasBuiltInTopRole)
                                  DropdownButtonFormField<String?>(
                                    value: roles.contains(_role) ? _role : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Account level',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    items: [
                                      if (canPickNoRole)
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('None'),
                                        ),
                                      ...roles.map(
                                        (r) => DropdownMenuItem<String?>(
                                          value: r,
                                          child: Text(r),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) => setState(() => _role = v),
                                  ),
                                  const SizedBox(height: 12),
                                  // Always shown. Disabled when it does not apply:
                                  // super admins are system-wide and an existing
                                  // account's organization can't be changed.
                                  DropdownButtonFormField<int?>(
                                    value: _selectedOrgId,
                                    decoration: InputDecoration(
                                      labelText: _role == 'ORGANIZATION_OWNER'
                                          ? 'Organization *'
                                          : 'Organization',
                                      helperText: _role == 'SUPER_ADMIN'
                                          ? 'System-wide account — no organization'
                                          : (!_isCreate
                                              ? 'The organization of an existing account cannot be changed'
                                              : null),
                                      prefixIcon: const Icon(Icons.apartment_outlined),
                                    ),
                                    items: [
                                      DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text(_isCreate
                                            ? 'Select organization'
                                            : 'Current organization'),
                                      ),
                                      ...(_organizations ?? []).map(
                                        (o) => DropdownMenuItem<int?>(
                                          value: o.id,
                                          child: Text(o.name),
                                        ),
                                      ),
                                    ],
                                    onChanged: (!_isCreate || _role == 'SUPER_ADMIN')
                                        ? null
                                        : (v) => setState(() => _selectedOrgId = v),
                                  ),
                                  if (_roleListMode || (_isCreate && _canAssignRoles)) ...[
                                    const SizedBox(height: 16),
                                    FormSectionLabel('Additional roles'),
                                    const SizedBox(height: 8),
                                    PersonRolesSection(
                                      kind: 'users',
                                      personId: widget.account?.id,
                                      pending: _isCreate ? _pendingRoles : null,
                                      canAdd: !_isCreate ||
                                          !context.read<AuthState>().isSuperAdmin ||
                                          _selectedOrgId != null,
                                      disabledHint: 'Choose the organization first.',
                                      note: 'Added on top of the account level. Permissions add up across all roles.',
                                    ),
                                  ],
                                  const Divider(height: 32),
                                  FormSectionLabel('Personal Info'),
                                  const SizedBox(height: 12),
                                  if (_hasProfile) ...[
                                    PersonalDetailsFields(controller: _pd),
                                  ] else ...[
                                    TextField(
                                      controller: _firstName,
                                      decoration: const InputDecoration(
                                        labelText: 'First name',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _lastName,
                                      decoration: const InputDecoration(
                                        labelText: 'Last name',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _phone,
                                      keyboardType: TextInputType.phone,
                                      decoration: const InputDecoration(
                                        labelText: 'Phone',
                                        prefixIcon: Icon(Icons.phone_outlined),
                                      ),
                                    ),
                                  ],
                          ],
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
