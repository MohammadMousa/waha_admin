import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/account_user.dart';
import '../models/category.dart';
import '../models/device.dart';
import '../models/employee.dart';
import '../models/payment_method.dart';
import '../models/receipt_info.dart';
import '../models/resource.dart';
import '../models/branch_group.dart';
import '../models/organization.dart';
import '../models/store.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final http.Client _http;
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  String _extractMessage(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['message'] as String? ?? 'Request failed (${resp.statusCode})';
    } catch (_) {
      return 'Request failed (${resp.statusCode})';
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String username, String password) async {
    final resp = await _http.post(
      _uri('/api/auth/login'),
      headers: _headers(),
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboardKpis(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/dashboard/kpis')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Map<String, dynamic>>> getDashboardSeries(
      String token, String metric, String period, {int? storeId}) async {
    final uri = _uri('/api/admin/dashboard/series').replace(queryParameters: {
      'metric': metric,
      'period': period,
      if (storeId != null) 'storeId': '$storeId',
    });
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Map<String, dynamic>>> getDashboardMonthly(
      String token, String period, {int? storeId}) async {
    final uri = _uri('/api/admin/dashboard/monthly').replace(queryParameters: {
      'period': period,
      if (storeId != null) 'storeId': '$storeId',
    });
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Map<String, dynamic>>> getRecentOrders(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/dashboard/recent-orders')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getReportStores(String token) async {
    final resp = await _http.get(_uri('/api/admin/reports/stores'),
        headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Map<String, dynamic>>> getReportCategories(String token) async {
    final resp = await _http.get(_uri('/api/admin/reports/categories'),
        headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Map<String, dynamic>>> getReportKiosks(String token) async {
    final resp = await _http.get(_uri('/api/admin/reports/kiosks'),
        headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Map<String, dynamic>>> getReportPaymentMethods(String token) async {
    final resp = await _http.get(_uri('/api/admin/reports/payment-methods'),
        headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<Map<String, dynamic>> getIntegrationLogs(String token, {
    String? entityType, String? status, int page = 0, int size = 20,
  }) async {
    final params = <String, String>{
      if (entityType != null) 'entityType': entityType,
      if (status     != null) 'status':     status,
      'page': '$page', 'size': '$size',
    };
    final resp = await _http.get(
      _uri('/api/admin/integrations/logs').replace(queryParameters: params),
      headers: _headers(token: token),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Stores ────────────────────────────────────────────────────────────────

  Future<List<Store>> getAdminStores(String token) async {
    final resp = await _http.get(_uri('/api/stores/admin'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<Map<String, dynamic>?> getStoreAdminDetails(int storeId, {required String token}) async {
    final resp = await _http.get(_uri('/api/stores/$storeId/admin'), headers: _headers(token: token));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 200) return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> patchStore(int id, Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.patch(_uri('/api/stores/$id'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> createStore(Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.post(_uri('/api/stores'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) {
      return ((jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['id'] as num).toInt();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Organization>> getOrganizations(String token) async {
    final resp = await _http.get(_uri('/api/organizations'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => Organization.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<BranchGroup>> getBranchGroups(String token) async {
    final resp = await _http.get(_uri('/api/branch-groups'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => BranchGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Categories ────────────────────────────────────────────────────────────

  Future<List<Category>> getCategories({required int storeId, String? token}) async {
    final resp = await _http.get(
      _uri('/api/categories').replace(queryParameters: {'storeId': '$storeId'}),
      headers: _headers(token: token),
    );
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> patchCategory(int id, Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.patch(_uri('/api/categories/$id'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Products ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getProducts({
    required int storeId,
    int? categoryId,
    int page = 0,
    int size = 20,
    required String token,
  }) async {
    final uri = _uri('/api/products').replace(queryParameters: {
      'storeId': storeId.toString(),
      if (categoryId != null) 'categoryId': categoryId.toString(),
      'page': page.toString(),
      'size': size.toString(),
    });
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<Map<String, dynamic>> getProductDetail(int id) async {
    final resp = await _http.get(_uri('/api/products/$id'));
    if (resp.statusCode == 200) return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> patchProduct(int id, Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.patch(_uri('/api/products/$id'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<Map<String, dynamic>>> getChartData({
    required String token,
    required String endpoint,
    required DateTime from,
    required DateTime to,
  }) async {
    String pad(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime d) => '${d.year}-${pad(d.month)}-${pad(d.day)}';
    final uri = _uri('/api/admin/charts/$endpoint').replace(
        queryParameters: {'from': fmt(from), 'to': fmt(to)});
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> createProduct(Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.post(_uri('/api/products'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      return (data['id'] as num).toInt();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> addProductGalleryImage(int productId, int resourceId, {required String token}) async {
    final resp = await _http.post(_uri('/api/products/$productId/images'),
        headers: _headers(token: token), body: jsonEncode({'resourceId': resourceId}));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> removeProductGalleryImage(int productId, int resourceId, {required String token}) async {
    final resp = await _http.delete(_uri('/api/products/$productId/images/$resourceId'),
        headers: _headers(token: token));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Accounts ──────────────────────────────────────────────────────────────

  Future<List<String>> getAssignableRoles(String token) async {
    final resp = await _http.get(_uri('/api/admin/users/roles'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List).cast<String>();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<AccountUser>> getAdminAccounts(String token, {String? role}) async {
    final uri = _uri('/api/admin/users').replace(
      queryParameters: role != null ? {'role': role} : null,
    );
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => AccountUser.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> createAdminAccount(Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.post(_uri('/api/admin/users'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) {
      return ((jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['id'] as num).toInt();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> patchAdminAccount(int id, Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.patch(_uri('/api/admin/users/$id'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> deleteAdminAccount(int id, {required String token}) async {
    final resp = await _http.delete(_uri('/api/admin/users/$id'), headers: _headers(token: token));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> register(String username, String password) async {
    final resp = await _http.post(_uri('/api/auth/register'),
        headers: _headers(), body: jsonEncode({'username': username, 'password': password}));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Employees (POS staff — org owner manages) ────────────────────────────────

  Future<List<Employee>> getEmployees(String token) async {
    final resp = await _http.get(_uri('/api/admin/employees'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<Employee> getEmployee(int id, {required String token}) async {
    final resp = await _http.get(_uri('/api/admin/employees/$id'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return Employee.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> createEmployee(Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.post(_uri('/api/admin/employees'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) {
      return ((jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['id'] as num).toInt();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> patchEmployee(int id, Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.patch(_uri('/api/admin/employees/$id'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> deleteEmployee(int id, {required String token}) async {
    final resp = await _http.delete(_uri('/api/admin/employees/$id'), headers: _headers(token: token));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> addEmployeeStore(int id, int storeId, {required String token}) async {
    final resp = await _http.post(_uri('/api/admin/employees/$id/stores'),
        headers: _headers(token: token), body: jsonEncode({'storeId': storeId}));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> removeEmployeeStore(int id, int storeId, {required String token}) async {
    final resp = await _http.delete(_uri('/api/admin/employees/$id/stores/$storeId'),
        headers: _headers(token: token));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Devices (kiosks — org owner manages) ─────────────────────────────────────

  Future<List<Device>> getDevices(String token) async {
    final resp = await _http.get(_uri('/api/admin/devices'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => Device.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<Device> getDevice(int id, {required String token}) async {
    final resp = await _http.get(_uri('/api/admin/devices/$id'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return Device.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<Map<String, dynamic>> createDevice(Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.post(_uri('/api/admin/devices'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> patchDevice(int id, Map<String, dynamic> body, {required String token}) async {
    final resp = await _http.patch(_uri('/api/admin/devices/$id'),
        headers: _headers(token: token), body: jsonEncode(body));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> deleteDevice(int id, {required String token}) async {
    final resp = await _http.delete(_uri('/api/admin/devices/$id'), headers: _headers(token: token));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Payment methods ───────────────────────────────────────────────────────

  Future<List<AdminPaymentMethodView>> getAdminPaymentMethods({int? storeId, String? token}) async {
    final resp = await _http.get(
      _uri('/api/payment-methods/admin').replace(
          queryParameters: storeId != null ? {'storeId': '$storeId'} : null),
      headers: _headers(token: token),
    );
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => AdminPaymentMethodView.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> setPaymentMethodStoreActive(int id,
      {required bool active, int? storeId, String? token}) async {
    final resp = await _http.put(
      _uri('/api/payment-methods/$id/store-active').replace(queryParameters: {
        'active': '$active',
        if (storeId != null) 'storeId': '$storeId',
      }),
      headers: _headers(token: token),
    );
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Receipt info ──────────────────────────────────────────────────────────

  Future<ReceiptInfoData?> getReceiptInfo({int? storeId, String? token}) async {
    final resp = await _http.get(
      _uri('/api/receipt-info').replace(
          queryParameters: storeId != null ? {'storeId': '$storeId'} : null),
      headers: _headers(token: token),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 200) {
      return ReceiptInfoData.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> patchReceiptInfo(Map<String, dynamic> body, {required String token, int? storeId}) async {
    final resp = await _http.patch(
      _uri('/api/receipt-info').replace(
          queryParameters: storeId != null ? {'storeId': '$storeId'} : null),
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Odoo ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> odooStatus(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/status')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> oodooConfigure(String token, String baseUrl, String apiKey,
      String username, {String? customerOverride, int? storeId}) async {
    final uri = _uri('/api/admin/odoo/configure')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _http.post(uri,
        headers: _headers(token: token),
        body: jsonEncode({
          'baseUrl': baseUrl,
          'apiKey': apiKey,
          'username': username,
          if (customerOverride != null && customerOverride.isNotEmpty)
            'customerOverride': customerOverride,
        }));
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> oodooPullCategories(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/pull/categories')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _http.post(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as Map<String, dynamic>)['pulled'] as int? ?? 0;
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<(int, int)> oodooPullProducts(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/pull/products')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _http.post(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (body['pulled'] as int? ?? 0, body['visible'] as int? ?? 0);
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> oodooPushOrders(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/push/orders')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _http.post(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as Map<String, dynamic>)['pushed'] as int? ?? 0;
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Resource library ──────────────────────────────────────────────────────

  Future<List<ResourceDirectory>> getDirectories(String store, String token) async {
    final resp = await _http.get(
        _uri('/api/resources/$store/directories'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => ResourceDirectory.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<ResourceDirectory> createDirectory(String store, String name, String token) async {
    final resp = await _http.post(
      _uri('/api/resources/$store/directories'),
      headers: _headers(token: token),
      body: jsonEncode({'name': name}),
    );
    if (resp.statusCode == 200) {
      return ResourceDirectory.fromJson(
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<ResourceAsset>> getAssets(String store, String dir, String token) async {
    final resp = await _http.get(
        _uri('/api/resources/$store/directories/$dir'), headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as List)
          .map((e) => ResourceAsset.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<ResourceAsset> uploadAsset(
      String store, String dir, Uint8List bytes, String filename, String mimeType, String token,
      {String? nameOverride}) async {
    final uri = _uri('/api/resources/$store/directories/$dir');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename,
          contentType: http.MediaType.parse(mimeType.isNotEmpty ? mimeType : 'application/octet-stream')));
    if (nameOverride != null) request.fields['name'] = nameOverride;
    final streamed = await _http.send(request);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final rid = (body['resourceId'] as num).toInt();
      return ResourceAsset(
        id: 0, // upload response has no resource_assets.id
        resourceId: rid,
        name: body['name'] as String,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        sha256: body['sha256'] as String,
      );
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> deleteAsset(String store, String dir, String name, String token) async {
    final resp = await _http.delete(
        _uri('/api/resources/$store/directories/$dir/$name'), headers: _headers(token: token));
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> moveAsset(
      String store, String dir, String name, String targetDir, String token) async {
    final resp = await _http.patch(
      _uri('/api/resources/$store/directories/$dir/$name/move'),
      headers: _headers(token: token),
      body: jsonEncode({'targetDir': targetDir}),
    );
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> renameAsset(
      String store, String dir, String name, String newName, String token) async {
    final resp = await _http.patch(
      _uri('/api/resources/$store/directories/$dir/$name/rename'),
      headers: _headers(token: token),
      body: jsonEncode({'newName': newName}),
    );
    if (resp.statusCode == 200) return;
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Landing page ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getLandingPage(String pageKey, String? token, {int? storeId}) async {
    final query = storeId != null ? '?storeId=$storeId' : '';
    final resp = await _http.get(_uri('/api/landing/$pageKey$query'), headers: _headers(token: token));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getProductsSales(
    String token, {
    int? storeId,
    int? categoryId,
    int? productId,
    String? from,
    String? to,
    int page = 0,
    int size = 10,
  }) async {
    final qp = <String, String>{
      'page': '$page',
      'size': '$size',
      if (storeId    != null) 'storeId':    '$storeId',
      if (categoryId != null) 'categoryId': '$categoryId',
      if (productId  != null) 'productId':  '$productId',
      if (from != null) 'from': from,
      if (to   != null) 'to':   to,
    };
    final uri = _uri('/api/admin/reports/products-sales').replace(queryParameters: qp);
    final resp = await _http.get(uri, headers: _headers(token: token));
    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw ApiException(resp.statusCode, _extractMessage(resp));
  }
}
