import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../utils/role_labels.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/error_dialog.dart';

// No backend GET /me was delivered alongside the password-change endpoint
// (see to_Frontend_AI_On_Auth_Task [1]) — the identity shown here is the
// already-authenticated session's own cached username/role from login,
// not a fresh server round-trip. Swap in a real fetch if/when one exists.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
  void dispose() {
    // Password values never leave these controllers and never touch any
    // persistent store — dispose clears them the moment the screen closes.
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      showErrorDialogLater(context, _error!);
      _error = null;
    }
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthState>();

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.profile),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Text('My Profile',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: scheme.primary,
                                        child: Icon(Icons.person_outline,
                                            color: scheme.onPrimary, size: 24),
                                      ),
                                      const SizedBox(width: 14),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(auth.username ?? '',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700, fontSize: 16)),
                                          const SizedBox(height: 2),
                                          Text(roleDisplayName(auth.roleName),
                                              style: TextStyle(
                                                  fontSize: 13, color: scheme.onSurfaceVariant)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('Password',
                                          style: Theme.of(context).textTheme.titleSmall),
                                      const Spacer(),
                                      if (!_changingPassword)
                                        TextButton(
                                          onPressed: () => setState(() => _changingPassword = true),
                                          child: const Text('Change Password'),
                                        ),
                                    ],
                                  ),
                                  if (_changingPassword) ...[
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _currentPasswordCtrl,
                                      obscureText: _obscureCurrent,
                                      enabled: !_saving,
                                      decoration: InputDecoration(
                                        labelText: 'Current Password',
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.lock_outline),
                                        suffixIcon: IconButton(
                                          icon: Icon(_obscureCurrent
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined),
                                          onPressed: () =>
                                              setState(() => _obscureCurrent = !_obscureCurrent),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _newPasswordCtrl,
                                      obscureText: _obscureNew,
                                      enabled: !_saving,
                                      decoration: InputDecoration(
                                        labelText: 'New Password',
                                        helperText: 'At least 8 characters',
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.lock_outline),
                                        suffixIcon: IconButton(
                                          icon: Icon(_obscureNew
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined),
                                          onPressed: () =>
                                              setState(() => _obscureNew = !_obscureNew),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _confirmPasswordCtrl,
                                      obscureText: _obscureConfirm,
                                      enabled: !_saving,
                                      onSubmitted: (_) => _submit(),
                                      decoration: InputDecoration(
                                        labelText: 'Confirm New Password',
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.lock_outline),
                                        suffixIcon: IconButton(
                                          icon: Icon(_obscureConfirm
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined),
                                          onPressed: () =>
                                              setState(() => _obscureConfirm = !_obscureConfirm),
                                        ),
                                      ),
                                    ),

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
                                              : const Text('Save'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
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
