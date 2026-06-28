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
    final res =
        await _send(() => _http.get(ApiConfig.bootstrap(), headers: _headers()));
    return BootstrapDto.fromJson(_decodeMap(res));
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

  /// Patch an order's status (e.g. 'ready', 'completed').
  Future<OrderDto> updateOrderStatus(String orderId, String status) async {
    final res = await _send(() => _http.patch(
          ApiConfig.order(orderId),
          headers: _headers(),
          body: jsonEncode({'status': status}),
        ));
    return OrderDto.fromDrf(_decodeMap(res));
  }

  /// Mark a single order item ready (kitchen/bar -> waiter).
  Future<void> markItemReady(String itemId) =>
      _send(() => _http.post(ApiConfig.markItemReady(itemId), headers: _headers()));

  /// Toggle "delivered to guest" for an item.
  Future<void> toggleItemDone(String itemId) =>
      _send(() => _http.post(ApiConfig.toggleItemDone(itemId), headers: _headers()));

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
      throw ApiException(
          res.statusCode, 'Expected a JSON object, got ${decoded.runtimeType}.');
    } on FormatException catch (e) {
      throw ApiException(res.statusCode, 'Invalid JSON from server: ${e.message}');
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
