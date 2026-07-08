import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'dtos.dart';

/// Thrown for any non-success backend response or transport failure.
/// `statusCode == 0` means the request never reached the server.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  bool get isNetwork => statusCode == 0;
  bool get isAuth => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// REST client for the CafeConnect Django hub.
///
/// Stateless except for the auth token obtained via [login]; the client then
/// attaches `Authorization: Token <token>` to authenticated requests. Errors
/// are never swallowed — every failure throws [ApiException] with context.
class CafeApiClient {
  CafeApiClient({http.Client? httpClient, Duration? timeout})
      : _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 12);

  final http.Client _http;
  final Duration _timeout;
  String? _token;

  String? get token => _token;
  bool get isAuthenticated => _token != null;
  void setToken(String? token) => _token = token;

  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (auth && _token != null) 'Authorization': 'Token $_token',
      };

  /// Authenticate and cache the DRF token. Returns the token on success.
  Future<String> login(String username, String password) async {
    final res = await _send(() => _http.post(
          ApiConfig.authToken(),
          headers: _headers(auth: false),
          body: jsonEncode({'username': username, 'password': password}),
        ));
    final body = _decodeMap(res);
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const ApiException(0, 'Login succeeded but no token was returned.');
    }
    _token = token;
    return token;
  }

  /// Hydrate the staff app: tables, menu, open orders and preferences.
  Future<BootstrapDto> bootstrap() async {
    final res = await _send(
        () => _http.get(ApiConfig.bootstrap(), headers: _headers()));
    return BootstrapDto.fromJson(_decodeMap(res));
  }

  /// Manager dashboard analytics, aggregated from the full order history.
  Future<StatsDto> stats() async {
    final res =
        await _send(() => _http.get(ApiConfig.stats(), headers: _headers()));
    return StatsDto.fromJson(_decodeMap(res));
  }

  /// Manager order history, including closed/paid orders.
  Future<List<OrderHistoryDto>> orderHistory() async {
    final res = await _send(
        () => _http.get(ApiConfig.orderHistory(), headers: _headers()));
    final body = _decodeMap(res);
    final raw = (body['orders'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => OrderHistoryDto.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Create an order. `items` = [{menu_item_id:int, quantity:int, notes:[...]}].
  /// The server auto-splits kitchen/bar by each item's station and broadcasts
  /// `order.created` on the realtime feed.
  Future<OrderDto> createOrder({
    required int tableId,
    required List<Map<String, dynamic>> items,
    String guestName = '',
    String notes = '',
  }) async {
    final res = await _send(() => _http.post(
          ApiConfig.orders(),
          headers: _headers(),
          body: jsonEncode({
            'table_id': tableId,
            'guest_name': guestName,
            'notes': notes,
            'items': items,
          }),
        ));
    return OrderDto.fromDrf(_decodeMap(res));
  }

  /// Manager/admin action: create a staff login account. `role` is the hub
  /// wire value ('waiter' | 'kitchen' | 'bar' | 'manager'). Returns the created
  /// employee payload.
  Future<Map<String, dynamic>> createStaffAccount({
    required String name,
    required String firstName,
    required String lastName,
    required String username,
    required String password,
    required String role,
  }) async {
    final res = await _send(() => _http.post(
          ApiConfig.staffAccounts(),
          headers: _headers(),
          body: jsonEncode({
            'name': name,
            'first_name': firstName,
            'last_name': lastName,
            'username': username,
            'password': password,
            'role': role,
          }),
        ));
    return _decodeMap(res);
  }

  /// Manager/admin: the full staff roster with their capability flags.
  Future<List<EmployeeDto>> employees() async {
    final res = await _send(
        () => _http.get(ApiConfig.employees(), headers: _headers()));
    final decoded = jsonDecode(res.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map
            ? (decoded['results'] as List? ?? const [])
            : const []);
    return list
        .whereType<Map>()
        .map((e) => EmployeeDto.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Manager/admin: grant/revoke a staff member's capability flags.
  /// `body` keys are any of can_wait / can_bar / can_kitchen / can_manage_menu.
  Future<EmployeeDto> updateEmployee(
      String id, Map<String, dynamic> body) async {
    final res = await _send(() => _http.patch(
          ApiConfig.employee(id),
          headers: _headers(),
          body: jsonEncode(body),
        ));
    return EmployeeDto.fromJson(_decodeMap(res));
  }

  /// Patch an order's status (e.g. 'ready', 'completed').
  Future<OrderDto> updateOrderStatus(String orderId, String status) async {
    final res = await _send(() => _http.patch(
          ApiConfig.order(orderId),
          headers: _headers(),
          body: jsonEncode({'status': status}),
        ));
    return OrderDto.fromDrf(_decodeMap(res));
  }

  /// Waiter/manager approves a pending guest order: awaiting -> new, and the
  /// kitchen/bar see it for the first time.
  Future<OrderDto> confirmOrder(String orderId) async {
    final res = await _send(
        () => _http.post(ApiConfig.confirmOrder(orderId), headers: _headers()));
    return OrderDto.fromDrf(_decodeMap(res));
  }

  /// Waiter/manager declines a pending guest order (cancels it).
  Future<void> rejectOrder(String orderId) => _send(
      () => _http.post(ApiConfig.rejectOrder(orderId), headers: _headers()));

  /// An order's audit trail (who confirmed / marked ready / delivered / …).
  Future<List<OrderEventDto>> orderEvents(String orderId) async {
    final res = await _send(
        () => _http.get(ApiConfig.orderEvents(orderId), headers: _headers()));
    final decoded = jsonDecode(res.body);
    final list = decoded is List ? decoded : const [];
    return list
        .whereType<Map>()
        .map((e) => OrderEventDto.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Mark a single order item ready (kitchen/bar -> waiter).
  Future<void> markItemReady(String itemId) => _send(
      () => _http.post(ApiConfig.markItemReady(itemId), headers: _headers()));

  /// Toggle "delivered to guest" for an item.
  Future<void> toggleItemDone(String itemId) => _send(
      () => _http.post(ApiConfig.toggleItemDone(itemId), headers: _headers()));

  /// Delete a single order item (waiter/manager only). The server recalculates
  /// the order (cancelling it if this was the last item) and broadcasts
  /// `order.updated` on the realtime feed.
  Future<void> deleteOrderItem(String itemId) => _send(
      () => _http.delete(ApiConfig.orderItem(itemId), headers: _headers()));

  /// Acknowledge a guest attention signal ("Acknowledge"). Server-side this also
  /// flips a waiting table to occupied and broadcasts `table.updated`.
  Future<void> ackAttention(String signalId) => _send(
      () => _http.post(ApiConfig.ackAttention(signalId), headers: _headers()));

  /// Set a menu item's availability (stop-list on/off).
  Future<void> updateMenuAvailability(String id, bool available) async {
    await _send(() => _http.patch(
          Uri.parse('${ApiConfig.apiRoot}/menu-items/$id/'),
          headers: _headers(),
          body: jsonEncode({'is_available': available}),
        ));
  }

  /// Patch a table's status (Django value, e.g. 'free', 'occupied').
  Future<void> updateTableStatus(String id, String status) async {
    await _send(() => _http.patch(
          Uri.parse('${ApiConfig.apiRoot}/tables/$id/'),
          headers: _headers(),
          body: jsonEncode({'status': status}),
        ));
  }

  void close() => _http.close();

  // --- internals -----------------------------------------------------------

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on Exception catch (e) {
      // Transport-level failure (offline, DNS, timeout, connection refused).
      throw ApiException(0, 'Network error: $e');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw ApiException(res.statusCode, _errorMessage(res));
  }

  Map<String, dynamic> _decodeMap(http.Response res) {
    if (res.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw ApiException(res.statusCode,
          'Expected a JSON object, got ${decoded.runtimeType}.');
    } on FormatException catch (e) {
      throw ApiException(
          res.statusCode, 'Invalid JSON from server: ${e.message}');
    }
  }

  String _errorMessage(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded.isNotEmpty) {
        // DRF errors: {"detail": "..."} or {"field": ["msg", ...]}.
        final detail = decoded['detail'];
        if (detail is String) return detail;
        return decoded.entries
            .map((e) =>
                '${e.key}: ${e.value is List ? (e.value as List).join(", ") : e.value}')
            .join('; ');
      }
    } catch (_) {
      // fall through to raw body
    }
    final body = res.body.trim();
    return body.isEmpty ? 'HTTP ${res.statusCode}' : body;
  }
}
