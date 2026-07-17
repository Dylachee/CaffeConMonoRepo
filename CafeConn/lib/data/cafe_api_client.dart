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

  /// One table's history for a day (default: newest day with orders), plus the
  /// list of days that have orders so the UI can page day-by-day.
  Future<TableHistoryDto> tableHistory(String tableId, {String? date}) async {
    final res = await _send(() => _http
        .get(ApiConfig.tableHistory(tableId, date: date), headers: _headers()));
    return TableHistoryDto.fromJson(_decodeMap(res));
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

  /// Manager: change a staff member's login (username and/or new password;
  /// blank/absent fields stay unchanged).
  Future<void> setEmployeeCredentials(String id,
          {String? username, String? password}) =>
      _send(() => _http.post(
            ApiConfig.employeeCredentials(id),
            headers: _headers(),
            body: jsonEncode({
              if (username != null && username.isNotEmpty) 'username': username,
              if (password != null && password.isNotEmpty) 'password': password,
            }),
          ));

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
  /// Any staff: pin/unpin an item on the waiter Popular shelf.
  Future<void> toggleMenuItemPopular(String id) => _send(() =>
      _http.post(ApiConfig.toggleMenuItemPopular(id), headers: _headers()));

  /// Manager: rename/recolor a menu category ({'name': …, 'color': '#RRGGBB'}).
  Future<void> updateMenuCategory(String id, Map<String, dynamic> fields) =>
      _send(() => _http.patch(ApiConfig.menuCategory(id),
          headers: _headers(), body: jsonEncode(fields)));

  /// Manager: create a POS/menu category.
  Future<void> createMenuCategory(Map<String, dynamic> fields) =>
      _send(() => _http.post(ApiConfig.menuCategories(),
          headers: _headers(), body: jsonEncode(fields)));

  /// Manager: delete an unused POS/menu category.
  Future<void> deleteMenuCategory(String id) => _send(
      () => _http.delete(ApiConfig.menuCategory(id), headers: _headers()));

  /// Manager: create a menu item on the hub. `fields` uses the DRF wire names
  /// (name, description, price, category, station, tags, is_available,
  /// is_promoted, preparation_minutes).
  Future<void> createMenuItem(Map<String, dynamic> fields) =>
      _send(() => _http.post(ApiConfig.menuItems(),
          headers: _headers(), body: jsonEncode(fields)));

  /// Manager: update any menu-item fields on the hub (same wire names).
  Future<void> updateMenuItem(String id, Map<String, dynamic> fields) =>
      _send(() => _http.patch(Uri.parse('${ApiConfig.apiRoot}/menu-items/$id/'),
          headers: _headers(), body: jsonEncode(fields)));

  Future<void> updateMenuAvailability(String id, bool available) async {
    await _send(() => _http.patch(
          Uri.parse('${ApiConfig.apiRoot}/menu-items/$id/'),
          headers: _headers(),
          body: jsonEncode({'is_available': available}),
        ));
  }

  /// Manager/admin: remove a menu item from active menus. The hub deletes it
  /// when possible, or archives it if historic order rows still reference it.
  Future<void> deleteMenuItem(String id) async {
    await _send(() => _http.delete(
          Uri.parse('${ApiConfig.apiRoot}/menu-items/$id/'),
          headers: _headers(),
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

  // --- Content: venue social feed + storefront ------------------------------

  /// The staff feed (hidden posts included, pinned first) + pinned limit.
  Future<StaffFeedDto> staffFeed() async {
    final res = await _send(
        () => _http.get(ApiConfig.staffFeed(), headers: _headers()));
    return StaffFeedDto.fromJson(_decodeMap(res));
  }

  /// Create a feed post from a pasted URL. The hub validates the domain and
  /// answers 400 with a human-readable message for anything else.
  Future<SocialPostDto> createFeedPost(String url) async {
    final res = await _send(() => _http.post(
          ApiConfig.staffFeed(),
          headers: _headers(),
          body: jsonEncode({'url': url}),
        ));
    return SocialPostDto.fromJson(_decodeMap(res));
  }

  /// Pin a post to the top of the guest feed (409 when the limit is reached).
  Future<SocialPostDto> pinFeedPost(int id) async {
    final res = await _send(
        () => _http.post(ApiConfig.staffFeedPin(id), headers: _headers()));
    return SocialPostDto.fromJson(_decodeMap(res));
  }

  Future<SocialPostDto> unpinFeedPost(int id) async {
    final res = await _send(
        () => _http.post(ApiConfig.staffFeedUnpin(id), headers: _headers()));
    return SocialPostDto.fromJson(_decodeMap(res));
  }

  /// Toggle a post's guest visibility.
  Future<SocialPostDto> toggleFeedPostHidden(int id) async {
    final res = await _send(
        () => _http.post(ApiConfig.staffFeedHide(id), headers: _headers()));
    return SocialPostDto.fromJson(_decodeMap(res));
  }

  Future<void> deleteFeedPost(int id) => _send(
      () => _http.delete(ApiConfig.staffFeedPost(id), headers: _headers()));

  /// Venue storefront settings + built-in theme presets.
  Future<VenuePayloadDto> venueSettings() async {
    final res = await _send(
        () => _http.get(ApiConfig.staffVenue(), headers: _headers()));
    return VenuePayloadDto.fromJson(_decodeMap(res));
  }

  /// Patch storefront fields (DRF wire names: name, tagline_it, color_bg, …).
  Future<VenuePayloadDto> updateVenueSettings(
      Map<String, dynamic> fields) async {
    final res = await _send(() => _http.patch(
          ApiConfig.staffVenue(),
          headers: _headers(),
          body: jsonEncode(fields),
        ));
    return VenuePayloadDto.fromJson(_decodeMap(res));
  }

  /// Upload the venue logo/cover ([kind] is 'logo' or 'cover') as multipart.
  /// The hub validates type/size and resizes with Pillow.
  Future<VenuePayloadDto> uploadVenueImage(
      String kind, List<int> bytes, String filename) async {
    final request =
        http.MultipartRequest('POST', ApiConfig.staffVenueImage(kind));
    if (_token != null) request.headers['Authorization'] = 'Token $_token';
    request.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: filename));
    final res = await _send(() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
    return VenuePayloadDto.fromJson(_decodeMap(res));
  }

  /// Remove the venue logo/cover.
  Future<VenuePayloadDto> deleteVenueImage(String kind) async {
    final res = await _send(() =>
        _http.delete(ApiConfig.staffVenueImage(kind), headers: _headers()));
    return VenuePayloadDto.fromJson(_decodeMap(res));
  }

  // --- Staff chat + tasks -----------------------------------------------------

  /// One channel's history page, newest first. Pass [cursor] (the previous
  /// page's nextCursor) to walk back in time.
  Future<({List<ChatMessageDto> messages, int? nextCursor, bool hasMore})>
      chatHistory(String channel, {int? cursor, int limit = 30}) async {
    final res = await _send(() => _http.get(
        ApiConfig.chatMessages(channel: channel, cursor: cursor, limit: limit),
        headers: _headers()));
    final body = _decodeMap(res);
    return (
      messages: ((body['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ChatMessageDto.fromJson(e.cast<String, dynamic>()))
          .toList(),
      nextCursor: body['nextCursor'] == null
          ? null
          : int.tryParse(body['nextCursor'].toString()),
      hasMore: body['hasMore'] == true,
    );
  }

  /// Send text or a slash command. The command's bot answer (task bubble or
  /// readable error) comes back as `result`; both also arrive via WS.
  Future<({ChatMessageDto message, ChatMessageDto? result})> sendChatMessage({
    required String channel,
    required String body,
    int? replyTo,
  }) async {
    final res = await _send(() => _http.post(ApiConfig.chatSend(),
        headers: _headers(),
        body: jsonEncode({
          'channel': channel,
          'body': body,
          if (replyTo != null) 'reply_to': replyTo,
        })));
    final decoded = _decodeMap(res);
    return (
      message: ChatMessageDto.fromJson(
          ((decoded['message'] as Map?) ?? const {}).cast<String, dynamic>()),
      result: decoded['result'] is Map
          ? ChatMessageDto.fromJson(
              (decoded['result'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  /// A message and its thread replies, oldest first.
  Future<({ChatMessageDto? message, List<ChatMessageDto> replies})> chatThread(
      int messageId) async {
    final res = await _send(
        () => _http.get(ApiConfig.chatThread(messageId), headers: _headers()));
    final body = _decodeMap(res);
    return (
      message: body['message'] is Map
          ? ChatMessageDto.fromJson(
              (body['message'] as Map).cast<String, dynamic>())
          : null,
      replies: ((body['replies'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ChatMessageDto.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  /// Unread counts + read marks per channel.
  Future<({Map<String, int> unread, Map<String, int> marks})>
      chatReadState() async {
    final res =
        await _send(() => _http.get(ApiConfig.chatRead(), headers: _headers()));
    final body = _decodeMap(res);
    Map<String, int> asIntMap(dynamic value) => value is Map
        ? value.map((k, v) =>
            MapEntry(k.toString(), int.tryParse(v.toString()) ?? 0))
        : <String, int>{};
    return (unread: asIntMap(body['unread']), marks: asIntMap(body['marks']));
  }

  /// Move the read high-water mark (server keeps it monotonic).
  Future<void> markChatRead(String channel, int lastReadMessageId) =>
      _send(() => _http.post(ApiConfig.chatRead(),
          headers: _headers(),
          body: jsonEncode({
            'channel': channel,
            'last_read_message_id': lastReadMessageId,
          })));

  /// The planner's day view: tasks + (for manage) recurrence rules.
  Future<({List<StaffTaskDto> tasks, List<StaffTaskDto> rules})> tasksForDay(
      {String? date}) async {
    final res = await _send(
        () => _http.get(ApiConfig.staffTasks(date: date), headers: _headers()));
    final body = _decodeMap(res);
    List<StaffTaskDto> parse(dynamic value) => ((value as List?) ?? const [])
        .whereType<Map>()
        .map((e) => StaffTaskDto.fromJson(e.cast<String, dynamic>()))
        .toList();
    return (tasks: parse(body['tasks']), rules: parse(body['rules']));
  }

  /// Planner quick-add — the same syntax as /task ("title @name 21:30").
  Future<StaffTaskDto> quickAddTask(String input) async {
    final res = await _send(() => _http.post(ApiConfig.staffTasks(),
        headers: _headers(), body: jsonEncode({'input': input})));
    return StaffTaskDto.fromJson(
        ((_decodeMap(res)['task'] as Map?) ?? const {}).cast<String, dynamic>());
  }

  /// The big Done checkbox. [done] false reopens (permission-gated).
  Future<StaffTaskDto> setTaskDone(int taskId, {bool done = true}) async {
    final res = await _send(() => _http.post(ApiConfig.staffTaskDone(taskId),
        headers: _headers(), body: jsonEncode({'done': done})));
    return StaffTaskDto.fromJson(
        ((_decodeMap(res)['task'] as Map?) ?? const {}).cast<String, dynamic>());
  }

  /// The task's chat thread (bubble + replies) for the planner deep-link.
  Future<({ChatMessageDto? message, List<ChatMessageDto> replies})> taskThread(
      int taskId) async {
    final res = await _send(() =>
        _http.get(ApiConfig.staffTaskThread(taskId), headers: _headers()));
    final body = _decodeMap(res);
    return (
      message: body['message'] is Map
          ? ChatMessageDto.fromJson(
              (body['message'] as Map).cast<String, dynamic>())
          : null,
      replies: ((body['replies'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ChatMessageDto.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  // --- Alerts: shift, push subscriptions, escalation -------------------------

  /// Self-service shift toggle — alerts and pushes only reach on-shift staff.
  Future<bool> setShift(bool on) async {
    final res = await _send(() => _http.post(ApiConfig.staffShift(),
        headers: _headers(), body: jsonEncode({'on': on})));
    return _decodeMap(res)['on'] == true;
  }

  /// Register this browser's Web-Push subscription with the hub.
  Future<void> pushSubscribe(
          {required String endpoint,
          required String p256dh,
          required String auth}) =>
      _send(() => _http.post(ApiConfig.pushSubscriptions(),
          headers: _headers(),
          body: jsonEncode({
            'endpoint': endpoint,
            'keys': {'p256dh': p256dh, 'auth': auth},
          })));

  /// Remove this browser's subscription (shift-off).
  Future<void> pushUnsubscribe(String endpoint) =>
      _send(() => _http.delete(ApiConfig.pushSubscriptions(),
          headers: _headers(), body: jsonEncode({'endpoint': endpoint})));

  /// Alert ladder L3: flag an unhandled guest signal/order server-side so
  /// every on-shift device highlights it. Idempotent on the hub.
  Future<void> escalateSignal(String id) => _send(
      () => _http.post(ApiConfig.escalateSignal(id), headers: _headers()));

  Future<void> escalateOrder(String id) => _send(
      () => _http.post(ApiConfig.escalateOrder(id), headers: _headers()));

  // --- Coupons: campaigns, issue, redeem ------------------------------------

  /// Campaigns with counters. Requires the content (or manage) capability.
  Future<List<CouponCampaignDto>> couponCampaigns() async {
    final res = await _send(
        () => _http.get(ApiConfig.couponCampaigns(), headers: _headers()));
    final raw = (_decodeMap(res)['campaigns'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => CouponCampaignDto.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Create a campaign (DRF wire names: title, title_it, discount_type, …).
  Future<CouponCampaignDto> createCouponCampaign(
      Map<String, dynamic> fields) async {
    final res = await _send(() => _http.post(ApiConfig.couponCampaigns(),
        headers: _headers(), body: jsonEncode(fields)));
    return CouponCampaignDto.fromJson(_decodeMap(res));
  }

  Future<CouponCampaignDto> updateCouponCampaign(
      int id, Map<String, dynamic> fields) async {
    final res = await _send(() => _http.patch(ApiConfig.couponCampaign(id),
        headers: _headers(), body: jsonEncode(fields)));
    return CouponCampaignDto.fromJson(_decodeMap(res));
  }

  /// Signed claim link for a fullscreen QR. Requires the discount capability.
  Future<CouponIssueDto> issueCoupon(int campaignId) async {
    final res = await _send(() => _http.post(ApiConfig.couponIssue(),
        headers: _headers(), body: jsonEncode({'campaign': campaignId})));
    return CouponIssueDto.fromJson(_decodeMap(res));
  }

  /// Look up a scanned token / typed code before the confirmation sheet.
  Future<CouponPreviewDto> couponRedeemPreview(
      {String? token, String? code, String? orderId}) async {
    final res = await _send(() => _http.post(
          ApiConfig.couponRedeemPreview(),
          headers: _headers(),
          body: jsonEncode({
            if (token != null && token.isNotEmpty) 'token': token,
            if (code != null && code.isNotEmpty) 'code': code,
            if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
          }),
        ));
    return CouponPreviewDto.fromJson(_decodeMap(res));
  }

  /// Redeem, optionally binding the coupon (and its discount snapshot) to an
  /// open order. Returns the updated coupon; the hub broadcasts order.updated.
  Future<StaffCouponDto> redeemCoupon(
      {String? token, String? code, String? orderId}) async {
    final res = await _send(() => _http.post(
          ApiConfig.couponRedeem(),
          headers: _headers(),
          body: jsonEncode({
            if (token != null && token.isNotEmpty) 'token': token,
            if (code != null && code.isNotEmpty) 'code': code,
            if (orderId != null && orderId.isNotEmpty) 'order_id': orderId,
          }),
        ));
    return StaffCouponDto.fromJson(
        ((_decodeMap(res)['coupon'] as Map?) ?? const {})
            .cast<String, dynamic>());
  }

  /// Manager: return a cancelled order's redeemed coupon to active.
  Future<StaffCouponDto> voidCouponRedemption(int couponId) async {
    final res = await _send(
        () => _http.post(ApiConfig.couponVoid(couponId), headers: _headers()));
    return StaffCouponDto.fromJson(
        ((_decodeMap(res)['coupon'] as Map?) ?? const {})
            .cast<String, dynamic>());
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
    // A proxy/error page (Render 502/503 while waking up) returns HTML — don't
    // dump a whole document into the UI; show a short, human message instead.
    if (body.isEmpty || body.startsWith('<')) {
      return 'Server busy (HTTP ${res.statusCode}) — retrying…';
    }
    return body;
  }
}
