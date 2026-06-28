/// Central configuration for talking to the CafeConnect Django hub.
///
/// The base URL is injected at build time so one binary can target the Android
/// emulator, a physical device over Wi-Fi, or a desktop run without a code edit:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
///
/// Defaults to the Android emulator host alias (10.0.2.2), which maps to the
/// developer machine's localhost.
class ApiConfig {
  const ApiConfig._();

  /// Backend origin, e.g. http://192.168.1.42:8000 (no trailing slash).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static String get _base =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  /// REST root, e.g. http://192.168.1.42:8000/api
  static String get apiRoot => '$_base/api';

  /// Authenticated WebSocket URL for the staff realtime feed.
  static Uri staffSocket(String token) {
    final wsBase =
        _base.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    return Uri.parse('$wsBase/ws/staff/?token=$token');
  }

  // REST endpoints.
  static Uri authToken() => Uri.parse('$apiRoot/auth/token/');
  static Uri bootstrap() => Uri.parse('$apiRoot/staff/bootstrap/');
  static Uri orders() => Uri.parse('$apiRoot/orders/');
  static Uri order(String id) => Uri.parse('$apiRoot/orders/$id/');
  static Uri menuItems() => Uri.parse('$apiRoot/menu-items/');
  static Uri tables() => Uri.parse('$apiRoot/tables/');
  static Uri markItemReady(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/mark-ready/');
  static Uri toggleItemDone(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/toggle-done/');
  static Uri attentionSignals() => Uri.parse('$apiRoot/attention-signals/');
  static Uri ackAttention(String id) =>
      Uri.parse('$apiRoot/attention-signals/$id/ack/');
}
