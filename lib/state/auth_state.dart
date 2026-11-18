import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/organization.dart';
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

  // ── Super-admin "acting as" organization (backend api level 3) ─────────────
  // A super-admin belongs to organization 0, so org-scoped screens are empty
  // until one is picked. The pick lives in memory only (one per tab) and goes
  // out as a header on every request.
  List<Organization> _organizations = const [];
  Organization? _acting;

  // appName system property (from sign-in), shown where an organization cannot be picked.
  String _appName = 'Waha';
  String get appName => _appName;

  // Own profile picture (api level 5); loaded once per sign-in.
  int? _avatarResourceId;
  bool _avatarLoaded = false;
  int? get avatarResourceId => _avatarResourceId;
  bool get avatarLoaded => _avatarLoaded;
  void setAvatar(int? id) {
    _avatarResourceId = id;
    _avatarLoaded = true;
    notifyListeners();
  }

  bool get isSuperAdmin => hasPermission('MANAGE_SYSTEM');

  // Permissions split out of broader ones on newer servers. A server that
  // does not know them sends none, so then the screens stay shown as before
  // (settings fall back to the old store permission).
  static const _splitKeys = {
    'VIEW_REPORTS',
    'EXPORT_REPORTS',
    'MANAGE_PAYMENT_METHODS',
    'MANAGE_INTEGRATIONS',
    'MANAGE_SETTINGS',
    'VIEW_INVENTORY_REPORTS',
    'VIEW_ORGANIZATION_AUDIT',
  };
  bool get _serverSplitsPermissions => _permissions.any(_splitKeys.contains);
  bool get canViewReports => !_serverSplitsPermissions || hasPermission('VIEW_REPORTS');
  bool get canViewInventoryReports =>
      !_serverSplitsPermissions || hasPermission('VIEW_INVENTORY_REPORTS');
  bool get canExportReports => !_serverSplitsPermissions || hasPermission('EXPORT_REPORTS');
  bool get canManagePaymentMethods =>
      !_serverSplitsPermissions || hasPermission('MANAGE_PAYMENT_METHODS');
  bool get canManageIntegrations =>
      !_serverSplitsPermissions || hasPermission('MANAGE_INTEGRATIONS');
  bool get canManageSettings =>
      _serverSplitsPermissions ? hasPermission('MANAGE_SETTINGS') : hasPermission('MANAGE_STORES');
  /// Inventory wastes (api level 5).
  bool get canViewWastes => _apiLevel >= 5 && (isSuperAdmin || hasPermission('VIEW_WASTES'));
  bool get canDeleteUnpaidOrders => _apiLevel >= 6 && (isSuperAdmin || hasPermission('DELETE_UNPAID_ORDERS'));
  bool get canCreateWastes => _apiLevel >= 5 && (isSuperAdmin || hasPermission('CREATE_WASTES'));
  /// Audit menu: super admin, or VIEW_ORGANIZATION_AUDIT (api level 5).
  bool get canViewAudit =>
      _apiLevel >= 5 ? (isSuperAdmin || hasPermission('VIEW_ORGANIZATION_AUDIT')) : (_apiLevel >= 3 && isSuperAdmin);
  List<Organization> get organizations => _organizations;
  Organization? get actingOrganization => _acting;

  /// True when a super-admin must choose before org-scoped screens show data.
  bool get needsOrganizationPick =>
      isSuperAdmin && _apiLevel >= 3 && _organizations.length > 1 && _acting == null;

  /// Loads the organizations a super-admin can act as; with exactly one it is
  /// picked automatically. Never sends the header to a backend below level 3.
  Future<void> loadOrganizations() async {
    if (_token == null || !isSuperAdmin || _apiLevel < 3) {
      _clearActing();
      _organizations = const [];
      return;
    }
    try {
      _organizations = await ApiClient().getOrganizations(_token!);
    } catch (_) {
      return; // keep what we had
    }
    if (_organizations.length == 1) {
      _setActing(_organizations.first);
    } else if (_acting == null) {
      // Survive a page reload: restore the last pick of this login.
      final saved = (await SharedPreferences.getInstance()).getInt('admin_acting_org');
      final match = _organizations.where((o) => o.id == saved).firstOrNull;
      if (match != null) _setActing(match);
    } else if (_acting != null && !_organizations.any((o) => o.id == _acting!.id)) {
      _clearActing();
    }
  }

  /// Re-reads the list and tells the screens (the refresh button).
  Future<void> refreshOrganizations() async {
    await loadOrganizations();
    notifyListeners();
  }

  /// Switches the organization the super-admin acts as.
  void selectOrganization(Organization org) {
    _setActing(org);
    SharedPreferences.getInstance().then((p) => p.setInt('admin_acting_org', org.id));
    notifyListeners();
  }

  void _setActing(Organization org) {
    _acting = org;
    ApiClient.actingOrganizationId = org.id;
  }

  void _clearActing() {
    _acting = null;
    ApiClient.actingOrganizationId = null;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('admin_token');
    _username = prefs.getString('admin_username');
    _appName = prefs.getString('admin_app_name') ?? _appName;
    _roleName = prefs.getString('admin_role');
    _permissions = (prefs.getStringList('admin_permissions') ?? const []).toSet();
    await _loadApiLevel();
    // The saved role and permissions are only a copy from the last login or
    // refresh. A backend release can add permissions (e.g. coupons) that an
    // already-saved session never received, so those menu entries stayed
    // hidden until the user signed in again. Whenever the backend's feature
    // level differs from the level the copy was saved at, re-read it once.
    // Normal starts cost nothing extra: the level is fetched above anyway.
    // A saved copy without a level (older app version) counts as different,
    // so it refreshes once on the first start after this change.
    if (_token != null && _apiLevel > 0 && prefs.getInt('admin_permissions_level') != _apiLevel) {
      try {
        await refreshSession();
        return;
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          await logout(); // the session is gone on the server
          return;
        }
        // Any other failure: keep the saved copy and try again next start.
      } catch (_) {}
    }
    await loadOrganizations();
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
    String? appName,
  }) async {
    if (appName != null && appName.isNotEmpty) {
      _appName = appName;
      (await SharedPreferences.getInstance()).setString('admin_app_name', appName);
    }
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
    if (_apiLevel > 0) await prefs.setInt('admin_permissions_level', _apiLevel);
    await loadOrganizations();
    notifyListeners();
  }

  /// Re-reads role and permissions from the server without a new login, so a
  /// permission change shows up at once. Throws [ApiException] on failure
  /// (a 401 means the session is gone: the caller signs out).
  Future<void> refreshSession() async {
    final token = _token;
    if (token == null) return;
    final me = await ApiClient().getMe(token);
    final permissions = ((me['permissions'] as List?) ?? const []).map((e) => e.toString()).toSet();
    _permissions = permissions;
    _roleName = me['roleName']?.toString() ?? _inferRoleName(permissions);
    final prefs = await SharedPreferences.getInstance();
    if (_roleName != null) {
      await prefs.setString('admin_role', _roleName!);
    } else {
      await prefs.remove('admin_role');
    }
    await prefs.setStringList('admin_permissions', permissions.toList());
    await _loadApiLevel();
    if (_apiLevel > 0) await prefs.setInt('admin_permissions_level', _apiLevel);
    await loadOrganizations();
    notifyListeners();
  }

  // Fallback only — used when the server sends no role name (old servers). A
  // custom role's name always comes from the server, never from this guess.
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
    _organizations = const [];
    _avatarResourceId = null;
    _avatarLoaded = false;
    _clearActing();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_token');
    await prefs.remove('admin_username');
    await prefs.remove('admin_role');
    await prefs.remove('admin_permissions');
    await prefs.remove('admin_permissions_level');
    await prefs.remove('admin_acting_org'); // a new login starts with no pick
    notifyListeners();
    // Delete the session row on the server too (tokens never expire).
    if (oldToken != null) await ApiClient().logout(oldToken);
  }
}
