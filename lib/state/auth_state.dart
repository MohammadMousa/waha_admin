import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';

class AuthState extends ChangeNotifier {
  String? _token;
  String? _username;
  String? _roleName;
  Set<String> _permissions = {};
  int _apiLevel = 0;

  String? get token => _token;
  String? get username => _username;
  String? get roleName => _roleName;
  Set<String> get permissions => _permissions;
  bool get isLoggedIn => _token != null;

  /// Backend feature level from GET /api/config (0 if the backend predates
  /// this scheme, or the call failed). Lets a feature gate on the exact
  /// level it needs instead of guessing from permissions.
  int get apiLevel => _apiLevel;

  bool hasPermission(String permission) => _permissions.contains(permission);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('admin_token');
    _username = prefs.getString('admin_username');
    _roleName = prefs.getString('admin_role');
    _permissions = (prefs.getStringList('admin_permissions') ?? const []).toSet();
    await _loadApiLevel();
    notifyListeners();
  }

  Future<void> _loadApiLevel() async {
    try {
      final config = await ApiClient().getConfig();
      _apiLevel = int.tryParse(config['api_level']?.toString() ?? '') ?? 0;
    } catch (_) {
      // Keep the previous level — never enable new features on a failed check.
    }
  }

  Future<void> setSession(
    String token,
    String username, {
    String? roleName,
    Set<String> permissions = const {},
  }) async {
    _token = token;
    _username = username;
    _roleName = roleName ?? _inferRoleName(permissions);
    _permissions = permissions;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_token', token);
    await prefs.setString('admin_username', username);
    if (_roleName != null) {
      await prefs.setString('admin_role', _roleName!);
    } else {
      await prefs.remove('admin_role');
    }
    await prefs.setStringList('admin_permissions', permissions.toList());
    await _loadApiLevel();
    notifyListeners();
  }

  // Fallback only — used while the backend doesn't yet return an explicit
  // role name at login. Once it does, `roleName` from the response always
  // wins; this heuristic never overrides it.
  String? _inferRoleName(Set<String> permissions) {
    if (permissions.contains('MANAGE_SYSTEM')) return 'SUPER_ADMIN';
    if (permissions.contains('MANAGE_USERS')) return 'ORGANIZATION_OWNER';
    if (permissions.contains('MANAGE_STORES')) return 'BRANCH_ADMIN';
    if (permissions.contains('EDIT_PRODUCTS')) return 'OPERATOR';
    if (permissions.contains('VIEW_ALL_ORDERS')) return 'CASHIER';
    if (permissions.isNotEmpty) return 'KIOSK';
    return null;
  }

  Future<void> logout() async {
    final oldToken = _token;
    _token = null;
    _username = null;
    _roleName = null;
    _permissions = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_token');
    await prefs.remove('admin_username');
    await prefs.remove('admin_role');
    await prefs.remove('admin_permissions');
    notifyListeners();
    // Delete the session row on the server too (tokens never expire).
    if (oldToken != null) await ApiClient().logout(oldToken);
  }
}
