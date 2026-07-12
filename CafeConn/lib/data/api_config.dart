/// Central configuration for talking to the CafeConnect Django hub.
///
/// The base URL is injected at build time so one binary can target the Android
/// emulator, a physical device over Wi-Fi, or a desktop run without a code edit:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
///
/// Defaults to the Android emulator host alias (10.0.2.2), which maps to the
/// developer machine's localhost.
/// Web detection without importing Flutter (keeps this file pure Dart and
/// unit-testable). On the web 0 and 0.0 are the same JS number — this is
/// exactly how flutter/foundation defines kIsWeb.
const bool _isWeb = identical(0, 0.0);

class ApiConfig {
  const ApiConfig._();

  static const String _defined = String.fromEnvironment('API_BASE_URL');

  /// Backend origin, e.g. http://192.168.1.42:8000 (no trailing slash).
  ///
  /// Resolution order:
  ///   1. --dart-define=API_BASE_URL (explicit override always wins);
  ///   2. on web: the page's own origin — the staff PWA is served by the
  ///      Django hub itself at /staff/, so "where the page came from" IS the
  ///      backend. This makes the web build immune to the bar's Wi-Fi
  ///      handing out a new IP: no rebuild needed when the address changes;
  ///   3. Android-emulator host alias as the dev fallback.
  static String get baseUrl {
    if (_defined.isNotEmpty) return _defined;
    if (_isWeb) return Uri.base.origin;
    return 'http://10.0.2.2:8000';
  }

  static String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  /// REST root, e.g. http://192.168.1.42:8000/api
  static String get apiRoot => '$_base/api';

  /// Authenticated WebSocket URL for the staff realtime feed.
  static Uri staffSocket(String token) {
    final wsBase = _base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return Uri.parse('$wsBase/ws/staff/?token=$token');
  }

  // REST endpoints.
  static Uri authToken() => Uri.parse('$apiRoot/auth/token/');
  static Uri bootstrap() => Uri.parse('$apiRoot/staff/bootstrap/');
  static Uri stats() => Uri.parse('$apiRoot/staff/stats/');
  static Uri orderHistory() => Uri.parse('$apiRoot/staff/order-history/');
  static Uri tableHistory(String tableId, {String? date}) =>
      Uri.parse('$apiRoot/staff/table-history/').replace(queryParameters: {
        'table': tableId,
        if (date != null) 'date': date,
      });
  static Uri staffAccounts() => Uri.parse('$apiRoot/staff/accounts/');
  static Uri employees() => Uri.parse('$apiRoot/employees/');
  static Uri employee(String id) => Uri.parse('$apiRoot/employees/$id/');
  static Uri employeeCredentials(String id) =>
      Uri.parse('$apiRoot/employees/$id/credentials/');
  static Uri orders() => Uri.parse('$apiRoot/orders/');
  static Uri order(String id) => Uri.parse('$apiRoot/orders/$id/');
  static Uri confirmOrder(String id) =>
      Uri.parse('$apiRoot/orders/$id/confirm/');
  static Uri rejectOrder(String id) => Uri.parse('$apiRoot/orders/$id/reject/');
  static Uri orderEvents(String id) => Uri.parse('$apiRoot/orders/$id/events/');
  static Uri menuItems() => Uri.parse('$apiRoot/menu-items/');
  static Uri toggleMenuItemPopular(String id) =>
      Uri.parse('$apiRoot/menu-items/$id/toggle-popular/');
  static Uri menuFamilies() => Uri.parse('$apiRoot/menu-families/');
  static Uri menuFamily(String id) => Uri.parse('$apiRoot/menu-families/$id/');
  static Uri tables() => Uri.parse('$apiRoot/tables/');
  static Uri orderItem(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/');
  static Uri markItemReady(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/mark-ready/');
  static Uri toggleItemDone(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/toggle-done/');
  static Uri attentionSignals() => Uri.parse('$apiRoot/attention-signals/');
  static Uri ackAttention(String id) =>
      Uri.parse('$apiRoot/attention-signals/$id/ack/');
}
