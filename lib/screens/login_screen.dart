import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../router/routes.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  Timer? _lockTimer;
  int _lockSeconds = 0;
  String _lockMessage = 'Account temporarily locked.';

  bool get _locked => _lockSeconds > 0;

  void _startLock(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockSeconds = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _lockSeconds--;
        if (_lockSeconds <= 0) _error = null;
      });
      if (_lockSeconds <= 0) t.cancel();
    });
  }

  String get _countdown =>
      '${(_lockSeconds ~/ 60).toString().padLeft(2, '0')}:${(_lockSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _lockTimer?.cancel();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_locked) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final api = ApiClient();
      final data = await api.login(_username.text.trim(), _password.text);
      final token = data['token'] as String?;
      final username = data['username'] as String?;
      if (token == null) throw const ApiException(0, 'No token in response');
      if (mounted) {
        final auth = context.read<AuthState>();
        final nav = Navigator.of(context);
        await auth.setSession(
          token,
          username ?? _username.text.trim(),
          roleName: data['roleName'] as String?,
          permissions: (data['permissions'] as List?)?.cast<String>().toSet() ?? const {},
        );
        nav.pushReplacementNamed(Routes.dashboard);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final secs = e.retryAfterSeconds;
      setState(() {
        _loading = false;
        _error = (secs != null && secs > 0) ? null : e.message;
      });
      if (secs != null && secs > 0) {
        _lockMessage = e.message;
        _startLock(secs);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.admin_panel_settings_outlined,
                            color: scheme.onPrimary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text('Waha Admin',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _username,
                    enabled: !_locked,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    enabled: !_locked,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.key_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_locked || _error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _locked
                            ? '$_lockMessage Try again in $_countdown'
                            : _error!,
                        style: TextStyle(
                            color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: (_loading || _locked) ? null : _login,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign In', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
