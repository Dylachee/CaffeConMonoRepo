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

  static String restaurantSlug = 'sissy-bar';

  /// Restaurant-qualified REST root. Auth and the platform control plane use
  /// [globalApiRoot]; every operational endpoint uses this root.
  static String get globalApiRoot => '$_base/api';
  static String get apiRoot => '$globalApiRoot/restaurants/$restaurantSlug';

  /// Authenticated WebSocket URL for the staff realtime feed.
  static Uri staffSocket(String token) {
    final wsBase = _base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return Uri.parse(
        '$wsBase/ws/restaurants/$restaurantSlug/staff/?token=$token');
  }

  // REST endpoints.
  static Uri authToken() => Uri.parse('$globalApiRoot/auth/token/');
  static Uri platformRestaurants() =>
      Uri.parse('$globalApiRoot/platform/restaurants/');
  static Uri bootstrap() => Uri.parse('$apiRoot/staff/bootstrap/');
  static Uri stats() => Uri.parse('$apiRoot/staff/stats/');
  static Uri orderHistory() => Uri.parse('$apiRoot/staff/order-history/');
  static Uri stationHistory(String station, {String? date}) =>
      Uri.parse('$apiRoot/staff/station-history/').replace(queryParameters: {
        'station': station,
        if (date != null) 'date': date,
      });
  static Uri tableHistory(String tableId, {String? date}) =>
      Uri.parse('$apiRoot/staff/table-history/').replace(queryParameters: {
        'table': tableId,
        if (date != null) 'date': date,
      });
  static Uri tableBill(String tableId) =>
      Uri.parse('$apiRoot/staff/table-bill/').replace(queryParameters: {
        'table': tableId,
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
  static Uri menuSnapshot() => Uri.parse('$apiRoot/staff/menu-snapshot/');
  static Uri toggleMenuItemPopular(String id) =>
      Uri.parse('$apiRoot/menu-items/$id/toggle-popular/');
  static Uri menuCategories() => Uri.parse('$apiRoot/menu-categories/');
  static Uri menuCategory(String id) =>
      Uri.parse('$apiRoot/menu-categories/$id/');
  static Uri tables() => Uri.parse('$apiRoot/tables/');
  static Uri takeOverTable(String id) =>
      Uri.parse('$apiRoot/tables/$id/takeover/');
  static Uri orderItem(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/');
  static Uri markItemReady(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/mark-ready/');
  static Uri toggleItemDone(String itemId) =>
      Uri.parse('$apiRoot/order-items/$itemId/toggle-done/');
  static Uri attentionSignals() => Uri.parse('$apiRoot/attention-signals/');
  static Uri ackAttention(String id) =>
      Uri.parse('$apiRoot/attention-signals/$id/ack/');

  // Content: venue social feed + storefront (SMM / content capability).
  static Uri staffFeed() => Uri.parse('$apiRoot/staff/feed/');
  static Uri staffFeedPost(int id) => Uri.parse('$apiRoot/staff/feed/$id/');
  static Uri staffFeedPin(int id) => Uri.parse('$apiRoot/staff/feed/$id/pin/');
  static Uri staffFeedUnpin(int id) =>
      Uri.parse('$apiRoot/staff/feed/$id/unpin/');
  static Uri staffFeedHide(int id) =>
      Uri.parse('$apiRoot/staff/feed/$id/hide/');
  static Uri staffVenue() => Uri.parse('$apiRoot/staff/venue/');
  static Uri staffVenueImage(String kind) =>
      Uri.parse('$apiRoot/staff/venue/$kind/');

  // Alerts: shift toggle, push subscriptions, escalation flags.
  static Uri staffShift() => Uri.parse('$apiRoot/staff/shift/');
  static Uri pushSubscriptions() =>
      Uri.parse('$apiRoot/staff/push-subscriptions/');
  static Uri escalateSignal(String id) =>
      Uri.parse('$apiRoot/attention-signals/$id/escalate/');
  static Uri escalateOrder(String id) =>
      Uri.parse('$apiRoot/orders/$id/escalate/');

  // Staff chat (persistent, threaded) + tasks (chat bubbles = planner rows).
  static Uri chatMessages({String? channel, int? cursor, int? limit}) =>
      Uri.parse('$apiRoot/staff/chat/messages/').replace(queryParameters: {
        if (channel != null) 'channel': channel,
        if (cursor != null) 'cursor': '$cursor',
        if (limit != null) 'limit': '$limit',
      });
  static Uri chatSend() => Uri.parse('$apiRoot/staff/chat/messages/');
  static Uri chatThread(int id) => Uri.parse('$apiRoot/staff/chat/thread/$id/');
  static Uri chatRead() => Uri.parse('$apiRoot/staff/chat/read/');
  static Uri staffTasks({String? date}) =>
      Uri.parse('$apiRoot/staff/tasks/').replace(queryParameters: {
        if (date != null) 'date': date,
      });
  static Uri staffTask(int id) => Uri.parse('$apiRoot/staff/tasks/$id/');
  static Uri staffTaskDone(int id) =>
      Uri.parse('$apiRoot/staff/tasks/$id/done/');
  static Uri staffTaskTake(int id) =>
      Uri.parse('$apiRoot/staff/tasks/$id/take/');
  static Uri staffTaskLeave(int id) =>
      Uri.parse('$apiRoot/staff/tasks/$id/leave/');
  static Uri staffTaskThread(int id) =>
      Uri.parse('$apiRoot/staff/tasks/$id/thread/');

  // Coupons: campaigns (content capability) + issue/redeem (discount).
  static Uri couponCampaigns() =>
      Uri.parse('$apiRoot/staff/coupons/campaigns/');
  static Uri couponCampaign(int id) =>
      Uri.parse('$apiRoot/staff/coupons/campaigns/$id/');
  static Uri couponIssue() => Uri.parse('$apiRoot/staff/coupons/issue/');
  static Uri couponRedeemPreview() =>
      Uri.parse('$apiRoot/staff/coupons/redeem-preview/');
  static Uri couponRedeem() => Uri.parse('$apiRoot/staff/coupons/redeem/');
  static Uri couponVoid(int id) =>
      Uri.parse('$apiRoot/staff/coupons/$id/void-redemption/');
}
