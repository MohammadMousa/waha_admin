import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/role_labels.dart';
import '../widgets/account_sessions_dialog.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';
import '../widgets/form_page.dart';
import '../widgets/personal_details_form.dart';

/// The signed-in person's own profile: same layout as the employee and account
/// edit pages (picture first, then sections), plus password and sessions.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Personal details (api level 5).
  final _pd = PersonalDetailsController();
  bool _profileLoading = false;
  bool _profileSaving = false;
  bool _avatarBusy = false;

  // Password change.
  bool _changingPassword = false;
  bool _saving = false;
  String? _error;
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _pd.dispose();
    // Password values never leave these controllers and never touch any
    // persistent store — dispose clears them the moment the screen closes.
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final auth = context.read<AuthState>();
    final token = auth.token;
    if (token == null || auth.apiLevel < 5) return;
    setState(() => _profileLoading = true);
    try {
      final p = await ApiClient().getProfile(token);
      if (!mounted) return;
      setState(() {
        _pd.apply(p);
        _profileLoading = false;
      });
      auth.setAvatar((p['avatarResourceId'] as num?)?.toInt());
    } catch (e) {
      if (!mounted) return;
      setState(() => _profileLoading = false);
      showErrorDialog(context, e is ApiException ? e.message : 'Could not load the profile: $e');
    }
  }

  Future<void> _saveProfile() async {
    final auth = context.read<AuthState>();
    final token = auth.token;
    if (token == null || auth.apiLevel < 5) return;
    final changed = _pd.changed();
    if (changed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to save.')));
      return;
    }
    setState(() => _profileSaving = true);
    try {
      final p = await ApiClient().updateProfile(token, changed);
      if (!mounted) return;
      setState(() {
        _pd.apply(p); // shows the phone the way the server stored it
        _profileSaving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Personal details saved.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _profileSaving = false);
      showErrorDialog(context, e is ApiException ? e.message : 'Could not save: $e');
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
    setState(() => _avatarBusy = true);
    try {
      final p = await ApiClient().uploadProfileAvatar(token, file.bytes!, file.name);
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      context.read<AuthState>().setAvatar((p['avatarResourceId'] as num?)?.toInt());
    } catch (e) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      showErrorDialog(context, e is ApiException ? e.message : 'Could not upload: $e');
    }
  }

  Future<void> _removeAvatar() async {
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() => _avatarBusy = true);
    try {
      await ApiClient().deleteProfileAvatar(token);
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      context.read<AuthState>().setAvatar(null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      showErrorDialog(context, e is ApiException ? e.message : 'Could not remove: $e');
    }
  }

  void _cancelChangePassword() {
    _currentPasswordCtrl.clear();
    _newPasswordCtrl.clear();
    _confirmPasswordCtrl.clear();
    setState(() {
      _changingPassword = false;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final current = _currentPasswordCtrl.text;
    final next = _newPasswordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;
    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    if (next.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New password and confirmation do not match.');
      return;
    }
    final token = context.read<AuthState>().token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ApiClient().changeOwnPassword(current, next, token: token);
      if (!mounted) return;
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      setState(() { _saving = false; _changingPassword = false; });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password changed successfully.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.statusCode == 401 ? 'Current password is incorrect.' : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  Widget _passwordField(TextEditingController c, String label, bool obscure, VoidCallback toggle,
      {String? helper, VoidCallback? onSubmitted}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      enabled: !_saving,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: toggle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthState>();
    final hasProfile = auth.apiLevel >= 5;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSidebar(currentRoute: Routes.profile),
          Expanded(
            child: Column(
              children: [
                FormPageHeader(
                  title: 'My Profile',
                  showSave: hasProfile,
                  saving: _profileSaving,
                  onSave: _saveProfile,
                ),
                Expanded(
                  child: _profileLoading
                      ? const Center(child: CircularProgressIndicator())
                      : FormPageBody(
                          children: [
                            if (hasProfile) ...[
                              PersonAvatar(
                                avatarId: auth.avatarResourceId,
                                busy: _avatarBusy,
                                onPick: _pickAvatar,
                                onRemove: _removeAvatar,
                              ),
                              const SizedBox(height: 24),
                            ],
                            const FormSectionLabel('Account'),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: auth.username ?? '',
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: roleDisplayName(auth.roleName),
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            if (hasProfile) ...[
                              const Divider(height: 32),
                              const FormSectionLabel('Personal Info'),
                              const SizedBox(height: 12),
                              PersonalDetailsFields(controller: _pd),
                            ],
                            const Divider(height: 32),
                            const FormSectionLabel('Security'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text('Password', style: Theme.of(context).textTheme.titleSmall),
                                const Spacer(),
                                if (!_changingPassword)
                                  TextButton(
                                    onPressed: () => setState(() => _changingPassword = true),
                                    child: const Text('Change Password'),
                                  ),
                              ],
                            ),
                            if (_changingPassword) ...[
                              const SizedBox(height: 8),
                              _passwordField(_currentPasswordCtrl, 'Current Password', _obscureCurrent,
                                  () => setState(() => _obscureCurrent = !_obscureCurrent)),
                              const SizedBox(height: 12),
                              _passwordField(_newPasswordCtrl, 'New Password', _obscureNew,
                                  () => setState(() => _obscureNew = !_obscureNew),
                                  helper: 'At least 8 characters'),
                              const SizedBox(height: 12),
                              _passwordField(_confirmPasswordCtrl, 'Confirm New Password',
                                  _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm),
                                  onSubmitted: _submit),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: _saving ? null : _cancelChangePassword,
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: _saving ? null : _submit,
                                    child: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Save password'),
                                  ),
                                ],
                              ),
                            ],
                            // Own sessions exist from backend api level 3.
                            if (auth.apiLevel >= 3) ...[
                              const Divider(height: 24),
                              Row(
                                children: [
                                  Text('Active sessions',
                                      style: Theme.of(context).textTheme.titleSmall),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _showSessions,
                                    child: const Text('View sessions'),
                                  ),
                                ],
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

  void _showSessions() {
    showDialog<void>(
      context: context,
      builder: (_) => AccountSessionsDialog(
        title: 'My sessions',
        load: (t) => ApiClient().getMySessions(t),
        deleteOne: (ref, t) => ApiClient().deleteMySession(ref, t),
        signOutAll: (t) => ApiClient().signOutMyOtherSessions(t),
        signOutLabel: 'Sign out other devices',
        signOutQuestion: 'Sign out every other device? This one stays signed in.',
      ),
    );
  }
}
