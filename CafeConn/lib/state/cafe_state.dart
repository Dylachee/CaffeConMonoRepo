import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/alerts/alert_platform.dart';
import '../core/alerts/alert_service.dart';
import '../core/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/utils.dart';
import '../data/cafe_api_client.dart';
import '../data/api_config.dart';
import '../data/dtos.dart';
import '../data/realtime_client.dart';
import '../models/models.dart';

/// Result of [CafeState.loadTableHistory]: the orders for one day plus the
/// list of days (newest first) that have orders, so the screen can page back.
class TableHistoryResult {
  final String?
      date; // ISO yyyy-MM-dd being shown (null when the table has none)
  final List<String> dates; // distinct days with orders, newest first
  final List<CafeOrder> orders; // orders for [date], newest first
  const TableHistoryResult({
    required this.date,
    required this.dates,
    required this.orders,
  });
}

class CafeState extends ChangeNotifier with WidgetsBindingObserver {
  final _api = MockCafeApi();
  // --- Backend integration (CafeConnect Django hub) ---
  final CafeApiClient _remoteApi = CafeApiClient();
  StaffRealtimeClient? _realtime;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  bool backendConnected = false;
  bool backendConnecting = false;
  String? backendError;
  // Auto-sync guards: catch up on state the realtime socket missed while it
  // was down, so a waiter never has to hit "Reconnect" by hand.
  bool _realtimeEverConnected = false;
  bool _resyncing = false;
  Timer? _syncTimer;

  /// Manager dashboard analytics from the hub (aggregated over the full order
  /// history). Null when not yet loaded, offline, or the backend predates the
  /// stats endpoint — the panel then falls back to live client-side numbers.
  StatsDto? stats;
  bool statsLoading = false;
  List<OrderHistoryDto> orderHistory = [];
  bool orderHistoryLoading = false;
  List<Map<String, dynamic>> stationHistory = [];
  bool stationHistoryLoading = false;
  final Map<String, Map<String, dynamic>> tableBills = {};
  String? _lastUser;
  String? _lastPass;
  Box get _box => Hive.box('cafeconnect');
  String _tenantKey(String key) => '${ApiConfig.restaurantSlug}:$key';
  final List<AppUser> users = [];
  final List<CafeTable> tables = [];
  final List<MenuItem> menu = [];
  final List<CafeOrder> orders = [];
  // Freed/paid orders kept only for each table's "Storico ordini" — never
  // active, never counted in the current-visit total. Capped so it can't grow.
  final List<CafeOrder> archivedOrders = [];
  static const _archiveCap = 60;
  final List<AppUser> staff = [];
  final List<ChatGroup> groups = [];
  final List<ChatMessage> messages = [];
  final Map<String, List<CartLine>> tableChecks = {};
  // Tables with a send in flight. A draft is only marked `sent` after the
  // network round-trip, so a double-tap used to fire the same draft as a fresh
  // order each time; this blocks a re-entrant submit until the first finishes.
  final Set<String> _submittingTables = {};
  bool isSubmitting([String? tableId]) =>
      _submittingTables.contains(tableId ?? currentTable?.id ?? '');
  final List<Map<String, dynamic>> _pendingQueue = [];
  int get pendingQueueCount => _pendingQueue.length;
  final syncSuccess = ValueNotifier<bool>(false);

  AppUser? currentUser;
  CafeTable? currentTable;
  ChatGroup? currentGroup;

  /// Effective role of the signed-in staff member. Comes from the hub's
  /// bootstrap (Employee.role); in local demo mode it stays admin so every
  /// screen is reachable. Persisted so a PWA restart with a saved token
  /// doesn't flash manager tabs at a cook before the bootstrap answers.
  UserRole currentRole = UserRole.admin;

  /// UI language (EN/IT). Mirrored into [L.lang]; every mutation notifies.
  AppLang appLang = AppLang.it;

  // ---- Alerts: shift state + escalation ladder ---------------------------
  /// The escalation ladder (L1 chime → L2 repeat → L3 escalate). Owns the
  /// browser glue (tones, vibration, OS banners, push, wake lock).
  final AlertService alertService =
      AlertService(platform: createAlertPlatform());
  AlertPlatform get alertPlatform => alertService.platform;

  /// Employee.is_on_shift for THIS account. Alerts and web pushes only fire
  /// on on-shift devices; persisted so a reload keeps the shift running.
  bool isOnShift = false;
  List<String> shiftAreas = [];
  List<String> lastShiftAreas = [];

  RestaurantDto? activeRestaurant;
  List<RestaurantDto> availableRestaurants = [];
  List<RestaurantDto> portfolioRestaurants = [];
  bool portfolioLoading = false;
  bool isPlatformOwner = false;

  /// Per-device quiet mode: ladders keep tracking (banners stay), but no
  /// sound/vibration/OS banners.
  bool alertsQuiet = false;

  /// Web Push availability from the hub (VAPID keys configured) + the
  /// applicationServerKey for pushManager.subscribe().
  bool pushEnabled = false;
  String pushPublicKey = '';
  bool _alertListenerAttached = false;

  bool online = true;
  bool noConnectionDismissed = false;
  bool soundEnabled = true;
  ThemeMode themeMode = ThemeMode.light;

  int tablesPerRow = 3;
  bool showGestureHints = true;
  String currencySymbol = r'$';
  bool currencyPrefix = false;
  bool use24hClock = true;
  double textScale = 1.0;
  bool hapticsEnabled = true;
  double soundVolume = 0.6;
  bool offlineModeSimulated = false;
  String activeUserName = 'Elena Sokolova';
  int? activeEmployeeId;

  void setSetting<Value>(String key, Value value, Function(Value) apply) {
    apply(value);
    _box.put(key, value);
    notifyListeners();
  }

  Timer? _retryTimer;

  void refresh() => notifyListeners();

  // ---- Capability-based visibility -------------------------------------
  // Effective capabilities from the hub (currentUser.capabilities), so a
  // manager can grant a waiter the bar (and vice-versa). Default all-true so
  // local/demo mode and older hubs stay fully functional; refreshed on every
  // bootstrap via [_applyCapabilities].
  bool capWait = true;
  bool capBar = true;
  bool capKitchen = true;
  bool capMenu = true;
  bool capManage = true;
  bool capContent = true;
  bool capDiscount = true;
  bool capCouponRedeem = true;
  bool capReports = true;

  // A "pure station" worker has no waiter capability — floor actions are
  // hidden for them, exactly as before, but a waiter+bar person now keeps both.
  bool get isStationRole => !capWait;
  bool get canSeeTables => capWait;
  bool get canSeePanel => capManage;
  bool get canSeeManage =>
      capManage || capMenu || capContent || capDiscount || capReports;
  bool get canDeliverOrders => capWait;
  bool get canManageMenu => capMenu;

  /// Content section (guest feed + storefront): SMM role, granted
  /// can_content, or manager/admin.
  bool get canSeeContent => capContent;

  /// Coupons: issuing/redeeming needs `discount`; the Campaigns tab inside
  /// the area needs `content`. The area shows up for either.
  bool get canSeeCoupons => capDiscount || capContent || capCouponRedeem;

  /// Whether this person works orders at all (floor or a station). A pure
  /// SMM/content account has none of these — orders, menu and tables stay
  /// hidden for them.
  bool get worksOrders => capWait || capBar || capKitchen;

  /// Feed zone lock. Floor staff (waiter capability) see every zone; a person
  /// who only covers one station is locked to it; someone covering both bar
  /// and kitchen sees both (no lock).
  FeedType? get lockedZone {
    if (capWait) return null;
    if (capBar && !capKitchen) return FeedType.bar;
    if (capKitchen && !capBar) return FeedType.kitchen;
    return null;
  }

  void _applyCapabilities(Map<String, dynamic> caps, UserRole role) {
    if (caps.isNotEmpty) {
      capWait = caps['wait'] == true;
      capBar = caps['bar'] == true;
      capKitchen = caps['kitchen'] == true;
      capMenu = caps['menu'] == true;
      capManage = caps['manage'] == true;
      // Older hubs omit `content`: derive it from the role so an SMM account
      // is never locked out of its only section.
      capContent = caps.containsKey('content')
          ? caps['content'] == true
          : (capManage || role == UserRole.smm);
      // Older hubs omit `discount`: only bosses had it implicitly.
      capDiscount =
          caps.containsKey('discount') ? caps['discount'] == true : capManage;
      capCouponRedeem = caps.containsKey('coupon_redeem')
          ? caps['coupon_redeem'] == true
          : capWait;
      capReports =
          caps.containsKey('reports') ? caps['reports'] == true : capManage;
      return;
    }
    // Older hub without capabilities: derive them from the role.
    final boss = role == UserRole.manager || role == UserRole.admin;
    capWait = boss || role == UserRole.waiter;
    capBar = boss || role == UserRole.bartender;
    capKitchen = boss || role == UserRole.cook;
    capMenu = boss;
    capManage = boss;
    capContent = boss || role == UserRole.smm;
    capDiscount = boss;
    capCouponRedeem = capWait;
    capReports = boss;
  }

  void _resetCapabilities() {
    capWait = capBar = capKitchen = capMenu = capManage =
        capContent = capDiscount = capCouponRedeem = capReports = true;
  }

  void setLanguage(AppLang value) {
    appLang = value;
    L.lang = value;
    _box.put('appLang', value.index);
    notifyListeners();
  }

  Future<void> boot() async {
    // Wake the socket + pull fresh data whenever the app comes back to the
    // foreground (phone unlocked, tab refocused) — the #1 desync cause.
    WidgetsBinding.instance.addObserver(this);
    ApiConfig.restaurantSlug =
        _box.get('restaurantSlug') as String? ?? 'sissy-bar';

    // --- Alert ladder configuration (fires only on-shift, outside quiet) ---
    isOnShift = _box.get('isOnShift') as bool? ?? false;
    alertsQuiet = _box.get('alertsQuiet') as bool? ?? false;
    alertService.isEnabled =
        () => backendConnected && isOnShift && !alertsQuiet;
    alertService.volume = () => soundVolume;
    alertService.onEscalate = _escalateRemote;
    alertService.osBannerText = (alert) => switch (alert.kind) {
          AlertKind.call => (L.guestCalling, L.tableN(alert.tableNumber)),
          AlertKind.bill => (L.guestBill, L.tableN(alert.tableNumber)),
          AlertKind.order => (L.guestOrder, L.tableN(alert.tableNumber)),
        };
    // Repaint the shell (banner list, app-bar pulse) on ladder changes.
    // boot() can run again (reset to demo) — attach exactly once.
    if (!_alertListenerAttached) {
      _alertListenerAttached = true;
      alertService.addListener(notifyListeners);
    }
    // Safety net for a silently half-dead socket: periodically catch up.
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (backendConnected) _ensureLiveAndResync();
    });
    // --- Seed users & staff (these are config, not user-editable, re-seed always) ---
    users
      ..clear()
      ..addAll(_api.seedUsers());
    staff
      ..clear()
      ..addAll(users);

    // --- Menu: load from Hive if present, else seed ---
    final rawMenu = _box.get(_tenantKey('menu')) as String? ??
        (ApiConfig.restaurantSlug == 'sissy-bar'
            ? _box.get('menu') as String?
            : null);
    if (rawMenu != null) {
      final list = jsonDecode(rawMenu) as List;
      menu
        ..clear()
        ..addAll(list.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)));
    } else {
      menu
        ..clear()
        ..addAll(_api.seedMenu());
      _saveMenu();
    }

    // --- Tables: load from Hive if present, else seed ---
    final rawTables = _box.get(_tenantKey('tables')) as String? ??
        (ApiConfig.restaurantSlug == 'sissy-bar'
            ? _box.get('tables') as String?
            : null);
    if (rawTables != null) {
      final list = jsonDecode(rawTables) as List;
      tables
        ..clear()
        ..addAll(
            list.map((e) => CafeTable.fromJson(e as Map<String, dynamic>)));
      // Restore checks (tableChecks) for each table
      for (final t in tables) {
        final rawCheck = _box.get(_tenantKey('check_${t.id}')) as String?;
        if (rawCheck != null) {
          final lines = jsonDecode(rawCheck) as List;
          tableChecks[t.id] = lines.map((e) {
            final m = e as Map<String, dynamic>;
            final item = menu.firstWhere((mi) => mi.id == m['itemId'],
                orElse: () => menu.first);
            return CartLine(
                item: item,
                quantity: m['quantity'] as int,
                modifiers: m['modifiers'] as String,
                sent: m['sent'] as bool,
                ready: m['ready'] as bool? ?? false,
                done: m['done'] as bool? ?? false);
          }).toList();
        }
      }
    } else {
      tables
        ..clear()
        ..addAll(_api.seedTables());
      _saveTables();
    }

    // --- Chats: groups are static config (re-seed), messages are real user
    // data — restore them from Hive. Seeding fake "demo" messages here was
    // the bug that wiped the kitchen chat on every app start.
    groups
      ..clear()
      ..addAll(_api.seedGroups(staff));
    messages.clear();
    final rawMessages = _box.get(_tenantKey('chatMessages')) as String?;
    if (rawMessages != null) {
      try {
        final list = jsonDecode(rawMessages) as List;
        messages.addAll(
            list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('boot: failed to restore chat messages: $e');
      }
    }

    // --- Offline order queue: restore orders typed while offline ---
    final rawQueue = _box.get(_tenantKey('pendingQueue')) as String?;
    if (rawQueue != null) {
      try {
        final list = jsonDecode(rawQueue) as List;
        _pendingQueue.addAll(list.cast<Map<String, dynamic>>());
      } catch (e) {
        debugPrint('boot: failed to restore pending queue: $e');
      }
    }

    // --- Settings ---
    final cachedTheme = _box.get('theme') as int?;
    if (cachedTheme != null) themeMode = ThemeMode.values[cachedTheme];

    final cachedLang = _box.get('appLang') as int?;
    if (cachedLang != null &&
        cachedLang >= 0 &&
        cachedLang < AppLang.values.length) {
      appLang = AppLang.values[cachedLang];
    }
    L.lang = appLang;

    final cachedRole = _box.get('currentRole') as int?;
    if (cachedRole != null &&
        cachedRole >= 0 &&
        cachedRole < UserRole.values.length) {
      currentRole = UserRole.values[cachedRole];
    }

    tablesPerRow = _box.get('tablesPerRow') as int? ?? 3;
    showGestureHints = _box.get('showGestureHints') as bool? ?? true;
    currencySymbol = _box.get('currencySymbol') as String? ?? r'$';
    currencyPrefix = _box.get('currencyPrefix') as bool? ?? false;
    use24hClock = _box.get('use24hClock') as bool? ?? true;
    textScale = (_box.get('textScale') as num?)?.toDouble() ?? 1.0;
    hapticsEnabled = _box.get('hapticsEnabled') as bool? ?? true;
    soundVolume = (_box.get('soundVolume') as num?)?.toDouble() ?? 0.6;
    activeUserName = _box.get('activeUserName') as String? ?? 'Elena Sokolova';
    soundEnabled = _box.get('soundEnabled') as bool? ?? true;

    _retryTimer = Timer.periodic(5.seconds, (_) => retryQueuedOrders());
    currentUser = users.firstOrNull;
    notifyListeners();

    // Auto-connect, in priority order:
    //   1. a token saved from a previous successful login on this device
    //      (survives PWA restarts and keeps the app live
    //      after the browser is closed);
    //   2. build-time credentials (--dart-define, dev builds only — never
    //      bake real staff passwords into a public web build).
    final savedToken = _box.get('apiToken') as String?;
    const autoUser = String.fromEnvironment('API_USERNAME');
    const autoPass = String.fromEnvironment('API_PASSWORD');
    if (savedToken != null && savedToken.isNotEmpty) {
      connectWithToken(savedToken);
    } else if (autoUser.isNotEmpty && autoPass.isNotEmpty) {
      connectBackend(username: autoUser, password: autoPass);
    }
  }

  void _saveTables() {
    _box.put(_tenantKey('tables'),
        jsonEncode(tables.map((t) => t.toJson()).toList()));
    for (final t in tables) {
      final check = tableChecks[t.id];
      if (check != null) {
        _box.put(_tenantKey('check_${t.id}'),
            jsonEncode(check.map((l) => l.toJson()).toList()));
      }
    }
  }

  void _saveMenu() => _box.put(
      _tenantKey('menu'), jsonEncode(menu.map((m) => m.toJson()).toList()));

  /// Persist chat history (bounded so Hive doesn't grow without limit).
  static const _maxStoredMessages = 500;
  void _saveMessages() {
    final recent = messages.length > _maxStoredMessages
        ? messages.sublist(messages.length - _maxStoredMessages)
        : messages;
    _box.put(_tenantKey('chatMessages'),
        jsonEncode(recent.map((m) => m.toJson()).toList()));
  }

  String _nextMessageId() => 'm${DateTime.now().microsecondsSinceEpoch}';

  void setGuestCount(String tableId, int count) {
    final table = tables.firstWhereOrNull((t) => t.id == tableId);
    if (table == null) return;
    table.guestCount = count < 1 ? 1 : count;
    HapticFeedback.selectionClick();
    _saveTables();
    notifyListeners();
  }

  void addItemNote(CartLine line, String note) {
    final notes = line.modifiers
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (!notes.contains(note)) notes.add(note);
    line.modifiers = notes.join(', ');
    _saveTables();
    notifyListeners();
  }

  void removeItemNote(CartLine line, String note) {
    final notes = line.modifiers
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != note)
        .toList();
    line.modifiers = notes.join(', ');
    _saveTables();
    notifyListeners();
  }

  void ackAttention(CafeTable table) {
    final signalId = table.lastSignalId;
    table.attention = null;
    table.lastSignalId = null;
    // Waiter accepted the call: the guests are no longer "waiting".
    if (table.status == TableStatus.waiting) {
      table.status = TableStatus.occupied;
    }
    HapticFeedback.selectionClick();
    _saveTables();
    notifyListeners();
    // Push the ack to the hub (it clears the badge on every other device and
    // flips waiting -> occupied server-side). Previously this was local-only —
    // the badge kept blinking everywhere else. Fire-and-forget with error
    // surfacing, never blocks the UI.
    if (backendConnected && signalId != null) {
      _pushAttentionAck(signalId);
    }
  }

  Future<void> _pushAttentionAck(String signalId) async {
    try {
      await _remoteApi.ackAttention(signalId);
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('ackAttention push failed: $e');
      notifyListeners();
    }
  }

  void addNote(CafeTable table, String note) {
    table.notes = [...table.notes, note];
    _saveTables();
    notifyListeners();
  }

  void removeNote(CafeTable table, int index) {
    table.notes.removeAt(index);
    table.notes = [...table.notes];
    _saveTables();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _remoteApi.close();
    alertService.dispose();
    super.dispose();
  }

  // Coalesce bursts of mutations (realtime batches, per-item loops like
  // "deliver all ready") into a single rebuild per microtask instead of one
  // full-screen rebuild per notifyListeners() call. The UI still updates in
  // the same frame; screens that watch the state just rebuild once.
  bool _notifyScheduled = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) super.notifyListeners();
    });
  }

  List<String> get categoryNames =>
      ['All', ...menu.map((m) => m.category).toSet()];

  List<MenuItem> sortedMenuItems(Iterable<MenuItem> items) => items.toList()
    ..sort((a, b) {
      if (a.available != b.available) return a.available ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

  /// Display label for a raw category key ('All' + menu categories):
  /// raw values stay stable for filtering, only the label is localized.
  String categoryDisplay(String raw) {
    if (raw == 'All') return L.all;
    return menu.firstWhereOrNull((m) => m.category == raw)?.displayCategory ??
        raw;
  }

  List<CartLine> tableCart(String tableId) =>
      tableChecks.putIfAbsent(tableId, () => []);

  /// Everything to show for a table wherever it's summarised (grid card,
  /// quick-check): the SENT items are read from the shared server [orders]
  /// list, the not-yet-sent DRAFT lines from this device's local check.
  ///
  /// This is the fix for "another waiter's table shows 0": the local check
  /// only ever holds what *this* device typed, so a table opened on another
  /// device looked empty. [orders] is the same for every device, so reading
  /// sent items from there makes every table's contents visible to everyone.
  /// Offline (no server orders yet) it falls back to the local sent lines, so
  /// the single-device / mock path is unchanged.
  List<CartLine> tableDisplayLines(String tableId) {
    final serverItems = orders
        .where((o) => o.tableId == tableId)
        .expand((o) => o.items)
        .toList();
    final local = tableCart(tableId);
    final sent = serverItems.isNotEmpty
        ? serverItems
        : local.where((l) => l.sent).toList();
    final drafts = local.where((l) => !l.sent);
    return [...sent, ...drafts];
  }

  double tableDisplayTotal(String tableId) =>
      tableDisplayLines(tableId).fold(0.0, (s, l) => s + l.total);

  /// A table's day-by-day history. Online it comes from the hub (any staff can
  /// see any table, any day); offline it's grouped from the orders this device
  /// holds. Returns null on a backend error so the screen can offer a retry.
  Future<TableHistoryResult?> loadTableHistory(String tableId,
      {String? date}) async {
    if (backendConnected) {
      try {
        final dto = await _remoteApi.tableHistory(tableId, date: date);
        return TableHistoryResult(
          date: dto.date,
          dates: dto.dates,
          orders: dto.orders.map(_orderFromDto).toList(),
        );
      } catch (_) {
        return null;
      }
    }
    final all = [
      ...orders.where((o) => o.tableId == tableId),
      ...archivedOrders.where((o) => o.tableId == tableId),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final byDay = <String, List<CafeOrder>>{};
    for (final o in all) {
      byDay.putIfAbsent(_dayKey(o.createdAt), () => []).add(o);
    }
    final dates = byDay.keys.toList();
    final want = (date != null && byDay.containsKey(date))
        ? date
        : (dates.isEmpty ? null : dates.first);
    return TableHistoryResult(
      date: want,
      dates: dates,
      orders: want == null ? const [] : byDay[want]!,
    );
  }

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  void addToCart(MenuItem item, int quantity, String modifiers,
      {String? tableId}) {
    if (tableId == null) return;
    final lines = tableCart(tableId);
    // Merge only with a not-yet-sent line: a sent line already lives on the
    // kitchen/bar screen and must not be silently mutated.
    final existing = lines.firstWhereOrNull((line) =>
        !line.sent && line.item.id == item.id && line.modifiers == modifiers);
    if (existing == null) {
      lines.add(CartLine(item: item, quantity: quantity, modifiers: modifiers));
    } else {
      existing.quantity += quantity;
    }
    HapticFeedback.selectionClick();
    _saveTables();
    notifyListeners();
  }

  void changeQuantity(CartLine line, int delta, {String? tableId}) {
    if (line.sent) return; // already on the station screen — don't mutate
    line.quantity = max(1, line.quantity + delta);
    HapticFeedback.selectionClick();
    _saveTables();
    notifyListeners();
  }

  void deleteLine(CartLine line, {String? tableId}) {
    if (tableId == null) return;
    tableCart(tableId).remove(line);
    HapticFeedback.mediumImpact();
    _saveTables();
    notifyListeners();
  }

  /// Send the table's unsent check lines to the stations.
  ///
  /// Splitting is by MenuItem.station (kitchen/bar), NOT by category name —
  /// the category guess ("Drinks"/"Coffee") was why beer never reached the
  /// bar feed. With [onlyFor] set, only that station's lines are sent.
  ///
  /// Returns the last created order, or null when there was nothing to send
  /// (callers must tell the waiter instead of failing silently).
  Future<CafeOrder?> submitOrder({String? tableId, FeedType? onlyFor}) async {
    final table = tables
        .firstWhereOrNull((t) => t.id == (tableId ?? currentTable?.id ?? ''));
    if (table == null) return null;
    // Re-entrancy guard: ignore taps while this table's send is in flight, so a
    // double-tap can't send the same draft as several orders.
    if (_submittingTables.contains(table.id)) return null;
    _submittingTables.add(table.id);
    notifyListeners();
    try {
      return await _submitOrderImpl(table, onlyFor,
          requestId: _newOrderRequestId(table.id));
    } finally {
      _submittingTables.remove(table.id);
      notifyListeners();
    }
  }

  /// Send exactly the lines confirmed in the precheck sheet.
  ///
  /// This bypasses the table's local draft cart. That cart can contain stale
  /// unsent rows after a failed/partial send, so the precheck path must not
  /// read from it when the waiter has just reviewed a specific snapshot.
  Future<CafeOrder?> submitOrderLines({
    required String tableId,
    required List<CartLine> lines,
    required String requestId,
  }) async {
    final table = tables.firstWhereOrNull((t) => t.id == tableId);
    if (table == null || lines.isEmpty) return null;
    if (_submittingTables.contains(table.id)) return null;
    _submittingTables.add(table.id);
    notifyListeners();
    try {
      return await _submitOrderImpl(table, null,
          draftLines: lines, requestId: requestId);
    } finally {
      _submittingTables.remove(table.id);
      notifyListeners();
    }
  }

  Future<CafeOrder?> _submitOrderImpl(CafeTable table, FeedType? onlyFor,
      {List<CartLine>? draftLines, required String requestId}) async {
    // When connected, send to the hub; realtime echoes it back to all devices.
    if (backendConnected) {
      return _submitOrderRemote(table, onlyFor,
          draftLines: draftLines, requestId: requestId);
    }

    final source = draftLines ?? tableCart(table.id).where((l) => !l.sent);
    final toSend = source.where((l) {
      if (onlyFor == null) return true;
      return (onlyFor == FeedType.bar) == l.isBar;
    }).toList();
    if (toSend.isEmpty) return null;

    final food = toSend.where((l) => !l.isBar).toList();
    final drinks = toSend.where((l) => l.isBar).toList();

    final List<CafeOrder> newOrders = [];
    for (final (lines, feed) in [
      (food, FeedType.kitchen),
      (drinks, FeedType.bar)
    ]) {
      if (lines.isEmpty) continue;
      newOrders.add(_makeOrder(
          table,
          lines
              .map((l) => CartLine(
                  item: l.item,
                  quantity: l.quantity,
                  modifiers: l.modifiers,
                  sent: true,
                  lockedPrice: l.lockedPrice))
              .toList(),
          feed));
      for (final l in lines) {
        if (draftLines == null) l.sent = true;
      }
    }

    if (!online) {
      _pendingQueue
          .addAll(newOrders.map((o) => {'type': 'order', 'data': o.toJson()}));
      _savePendingQueue();
    } else {
      orders.addAll(newOrders);
    }

    table.status = TableStatus.occupied;
    table.currentOrderId = newOrders.last.id;
    for (final o in newOrders) {
      addSystemMessage(o);
    }

    HapticFeedback.mediumImpact();
    _saveTables();
    notifyListeners();
    return newOrders.last;
  }

  /// Online order path: create on the hub, then reflect the server orders
  /// locally (idempotent by id, so the WebSocket echo won't duplicate them).
  /// One Send is one atomic server order. Station feeds filter its lines.
  Future<CafeOrder?> _submitOrderRemote(CafeTable table, FeedType? onlyFor,
      {List<CartLine>? draftLines, required String requestId}) async {
    final source = draftLines ?? tableCart(table.id).where((l) => !l.sent);
    final toSend = source.where((l) {
      if (onlyFor == null) return true;
      return (onlyFor == FeedType.bar) == l.isBar;
    }).toList();
    if (toSend.isEmpty) return null;

    final dto = await createRemoteOrder(
        tableId: table.id, lines: toSend, requestId: requestId);
    if (dto == null) return null;
    for (final line in toSend) {
      if (draftLines == null) line.sent = true;
    }
    final order = _orderFromDto(dto);
    _upsertLocalOrder(order);

    // The waiter sent this order himself — the table is occupied, not waiting.
    table.status = TableStatus.occupied;
    table.currentOrderId = order.id;
    _saveTables();
    HapticFeedback.mediumImpact();
    notifyListeners();
    return order;
  }

  String _newOrderRequestId(String tableId) =>
      '$tableId-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  CafeOrder _makeOrder(CafeTable table, List<CartLine> lines, FeedType feed) {
    return CafeOrder(
      // Time-based id: length-based ids collided with server ids and with
      // each other after orders were removed/re-synced.
      id: 'L${DateTime.now().millisecondsSinceEpoch}${feed.index}',
      tableId: table.id,
      tableNumber: table.number,
      items: lines,
      status: OrderStatus.cooking,
      createdAt: DateTime.now(),
      splitTo: feed,
    );
  }

  void _savePendingQueue() =>
      _box.put(_tenantKey('pendingQueue'), jsonEncode(_pendingQueue));

  /// Server channel for a legacy local chat group (names match 1:1).
  String _channelForGroup(ChatGroup group) => switch (group.type) {
        FeedType.kitchen => 'kitchen',
        FeedType.bar => 'bar',
        null => 'general',
      };

  void discussInChat(CafeOrder order, ChatGroup group, String comment) {
    final table = tables.firstWhereOrNull((t) => t.id == order.tableId);
    final text =
        '#discuss Order Table${table?.number.toString().padLeft(2, '0') ?? '??'}:${order.items.map((e) => '${e.quantity}x${e.item.name}').join(', ')}\n\n$comment';
    // Connected: the real (server) chat is the one staff read now.
    if (backendConnected) {
      sendChat(channel: _channelForGroup(group), body: text);
      return;
    }
    messages.add(ChatMessage(
      id: _nextMessageId(),
      groupId: group.id,
      senderId: currentUser?.id ?? 'system',
      text: text,
      tags: const ['#discuss'],
      timestamp: DateTime.now(),
      own: true,
    ));
    _saveMessages();
    notifyListeners();
  }

  void forwardTable(CafeTable table, ChatGroup group, String comment) {
    final text =
        '#forward Table${table.number.toString().padLeft(2, '0')} ·${statusLabel(table.status)}\n\n$comment';
    if (backendConnected) {
      sendChat(channel: _channelForGroup(group), body: text);
      return;
    }
    messages.add(ChatMessage(
      id: _nextMessageId(),
      groupId: group.id,
      senderId: currentUser?.id ?? 'system',
      text: text,
      tags: const ['#forward'],
      timestamp: DateTime.now(),
      kind: MessageKind.tableCard,
      refId: table.id,
    ));
    _saveMessages();
    notifyListeners();
  }

  /// Post a "new order" receipt card into the chats. It lands in the General
  /// chat (everyone) AND the relevant station chat (kitchen or bar), so the
  /// team sees every order come in. Idempotent: calling it again for the same
  /// order (e.g. a realtime echo) does not duplicate the card.
  void addSystemMessage(CafeOrder order) {
    // General chat (type == null) + this order's station chat.
    final targets =
        groups.where((g) => g.type == null || g.type == order.splitTo).toList();
    if (targets.isEmpty) return;
    final summary =
        order.items.map((e) => '${e.quantity}x${e.item.name}').join(', ');
    var added = false;
    for (final group in targets) {
      // Skip if this order already has a card in this group.
      final already = messages.any((m) =>
          m.groupId == group.id &&
          m.kind == MessageKind.orderCard &&
          m.refId == order.id);
      if (already) continue;
      messages.add(ChatMessage(
        id: _nextMessageId(),
        groupId: group.id,
        senderId: 'system',
        text: '#orders New order #${order.id}:$summary',
        tags: const ['#orders'],
        timestamp: DateTime.now(),
        kind: MessageKind.orderCard,
        refId: order.id,
      ));
      added = true;
    }
    if (added) _saveMessages();
  }

  void toggleOnline() {
    online = !online;
    noConnectionDismissed = false;
    notifyListeners();
  }

  void retryQueuedOrders() {
    if (!online || _pendingQueue.isEmpty) return;
    for (final item in _pendingQueue) {
      if (item['type'] == 'order') {
        try {
          final order =
              CafeOrder.fromJson(item['data'] as Map<String, dynamic>, menu);
          _upsertLocalOrder(order);
        } catch (e) {
          debugPrint('retryQueuedOrders: dropped malformed entry: $e');
        }
      }
    }
    _pendingQueue.clear();
    _box.delete(_tenantKey('pendingQueue'));
    syncSuccess.value = true;
    notifyListeners();
  }

  void closeTable(CafeTable table) => setTableStatus(table, TableStatus.free);

  /// Single entry point for changing a table's status from the staff UI.
  /// Applies locally right away (optimistic) and pushes to the hub; the hub
  /// broadcasts `table.updated` so every other device follows in ~1s.
  void setTableStatus(CafeTable table, TableStatus status) {
    final previous = table.status;
    table.status = status;
    if (status == TableStatus.free) {
      table.currentOrderId = null;
      table.guestCount = 0;
      table.attention = null;
      table.lastSignalId = null;
      tableChecks[table.id]?.clear();
      // Clearing the table ARCHIVES its orders into history — it does not
      // delete them. They move out of the active list (so the total/feed are
      // clean) and into `archivedOrders`, where the table's "Storico ordini"
      // still shows them. The hub marks them PAID; the next sync agrees.
      final freed = orders.where((o) => o.tableId == table.id).toList();
      orders.removeWhere((o) => o.tableId == table.id);
      for (final o in freed) {
        o.status = OrderStatus.completed;
      }
      archivedOrders.insertAll(0, freed);
      if (archivedOrders.length > _archiveCap) {
        archivedOrders.removeRange(_archiveCap, archivedOrders.length);
      }
    }
    HapticFeedback.selectionClick();
    _saveTables();
    notifyListeners();
    if (backendConnected && status != previous) {
      _pushTableStatus(table, status.name, previous);
    }
  }

  Future<void> _pushTableStatus(
      CafeTable table, String wire, TableStatus rollback) async {
    try {
      await _remoteApi.updateTableStatus(table.id, wire);
    } on ApiException catch (e) {
      table.status = rollback; // optimistic rollback
      backendError = e.message;
      debugPrint('closeTable push failed: $e');
      notifyListeners();
    }
  }

  void toggleAvailability(MenuItem item) {
    item.available = !item.available;
    HapticFeedback.selectionClick();
    _saveMenu();
    notifyListeners();
    if (backendConnected) _pushAvailability(item);
  }

  Future<void> _pushAvailability(MenuItem item) async {
    try {
      await _remoteApi.updateMenuAvailability(item.id, item.available);
    } on ApiException catch (e) {
      item.available = !item.available; // rollback
      backendError = e.message;
      debugPrint('toggleAvailability push failed: $e');
      _saveMenu();
      notifyListeners();
    }
  }

  /// Owner-defined menu categories from the hub (names + colors are the
  /// owner's data; the hardcoded palette is only the offline fallback).
  final List<CafeCategory> menuCategories = [];

  CafeCategory? categoryFor(MenuItem m) {
    if (m.categoryId.isNotEmpty) {
      final category =
          menuCategories.firstWhereOrNull((c) => c.id == m.categoryId);
      if (category != null) return category;
    }
    final key = MenuCategories.of(m.category, isBar: m.isBar).toLowerCase();
    return menuCategories.firstWhereOrNull((c) => c.key == key);
  }

  Color categoryColorFor(MenuItem m) =>
      categoryFor(m)?.color ?? AppColors.categoryColor(m.canonicalCategory);

  Color categoryColorForName(String category) {
    final legacy = MenuCategories.of(category, isBar: false);
    return menuCategories
            .firstWhereOrNull((c) => c.key == legacy.toLowerCase())
            ?.color ??
        AppColors.categoryColor(legacy);
  }

  List<CafeCategory> menuCategoriesWithItems({bool availableOnly = false}) {
    final usedIds = <String>{};
    for (final item in menu) {
      if (availableOnly && !item.available) continue;
      final category = categoryFor(item);
      if (category != null) usedIds.add(category.id);
    }
    return menuCategories
        .where((category) => usedIds.contains(category.id))
        .toList(growable: false);
  }

  bool itemInCategory(MenuItem m, String value) {
    final category = categoryFor(m);
    if (category != null) return category.id == value || category.name == value;
    return m.canonicalCategory == value || m.category == value;
  }

  /// Manager: rename/recolor a category. Optimistic local apply after the hub
  /// confirms; returns null on success, an error message otherwise.
  Future<String?> updateMenuCategory(String id,
      {String? name, String? color}) async {
    try {
      await _remoteApi.updateMenuCategory(id, {
        if (name != null && name.isNotEmpty) 'name': name,
        if (color != null && color.isNotEmpty) 'color': color,
      });
      final category = menuCategories.firstWhereOrNull((x) => x.id == id);
      if (category != null) {
        if (name != null && name.isNotEmpty) category.name = name;
        if (color != null && color.isNotEmpty) {
          category.color = CafeCategory.parseHex(color, category.color);
        }
      }
      await refreshMenu();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('updateMenuCategory failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  Future<String?> createMenuCategory(
      {required String name, String? color}) async {
    try {
      await _remoteApi.createMenuCategory({
        'name': name,
        if (color != null && color.isNotEmpty) 'color': color,
      });
      await refreshMenu();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('createMenuCategory failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  Future<String?> deleteMenuCategory(String id) async {
    try {
      await _remoteApi.deleteMenuCategory(id);
      menuCategories.removeWhere((category) => category.id == id);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('deleteMenuCategory failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  /// Pin/unpin an item on the waiter Popular shelf (hold a tile). Optimistic:
  /// flips the tag locally, pushes to the hub, rolls back on failure. Open to
  /// any staff — pinning a bestseller is floor work, not menu management.
  void togglePopular(MenuItem item) {
    if (item.isPopular) {
      item.tags.remove('popular');
    } else {
      item.tags.add('popular');
    }
    HapticFeedback.selectionClick();
    _saveMenu();
    notifyListeners();
    if (backendConnected) _pushPopular(item);
  }

  Future<void> _pushPopular(MenuItem item) async {
    try {
      await _remoteApi.toggleMenuItemPopular(item.id);
    } on ApiException catch (e) {
      if (item.isPopular) {
        item.tags.remove('popular'); // rollback
      } else {
        item.tags.add('popular');
      }
      backendError = e.message;
      debugPrint('togglePopular push failed: $e');
      _saveMenu();
      notifyListeners();
    }
  }

  void addTable(int number, Color color) {
    // Unique id even after deletions ("t${length+1}" collided with an
    // existing id as soon as any table had been removed).
    final id = 't${DateTime.now().millisecondsSinceEpoch}';
    tables.add(CafeTable(id, number, color, TableStatus.free, 0));
    _saveTables();
    notifyListeners();
  }

  void editTable(CafeTable table, int number, Color color) {
    final index = tables.indexWhere((t) => t.id == table.id);
    if (index != -1) {
      tables[index] = CafeTable(
          table.id, number, color, table.status, table.guestCount,
          currentOrderId: table.currentOrderId, notes: table.notes);
      _saveTables();
      notifyListeners();
    }
  }

  void deleteTable(CafeTable table) {
    tables.remove(table);
    tableChecks.remove(table.id);
    _box.delete(_tenantKey('check_${table.id}'));
    _saveTables();
    notifyListeners();
  }

  /// Create or update a menu item from the management form and persist it.
  /// (The form used to mutate `state.menu` directly and never saved.)
  void upsertMenuItem(MenuItem item) {
    final index = menu.indexWhere((m) => m.id == item.id);
    if (index >= 0) {
      menu[index] = item;
    } else {
      menu.add(item);
    }
    _saveMenu();
    notifyListeners();
  }

  /// Panel save: apply locally AND persist to the hub (upsertMenuItem alone
  /// was local-only — panel edits silently never reached the server). Returns
  /// null on success, an error message otherwise; on success the menu is
  /// re-pulled so server-side ids/labels are canonical.
  Future<String?> saveMenuItem(MenuItem item, {required bool isNew}) async {
    upsertMenuItem(item); // optimistic — the panel reflects the edit at once
    if (!backendConnected) return null;
    final fields = <String, dynamic>{
      'name': item.name,
      'description': item.description,
      'price': item.price.toStringAsFixed(2),
      'category': item.categoryId,
      'station': item.station.isEmpty ? 'kitchen' : item.station,
      'tags': item.tags,
      'show_in_guest_menu': item.tags.contains('client'),
      'is_available': item.available,
      'is_promoted': item.promo,
      'preparation_minutes': item.prepTime,
    };
    try {
      if (isNew) {
        await _remoteApi.createMenuItem(fields);
      } else {
        await _remoteApi.updateMenuItem(item.id, fields);
      }
      await refreshMenu();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('saveMenuItem push failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  Future<String?> copyMenuSnapshot() async {
    if (!backendConnected) return L.connectToManage;
    try {
      final snapshot = await _remoteApi.menuSnapshot();
      await Clipboard.setData(ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(snapshot)));
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> deleteMenuItem(MenuItem item) async {
    try {
      if (backendConnected) {
        await _remoteApi.deleteMenuItem(item.id);
      }
      menu.removeWhere((m) => m.id == item.id);
      _saveMenu();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      debugPrint('deleteMenuItem failed: $e');
      return e.message;
    }
  }

  void createStaff(String name, UserRole role) {
    final user = AppUser('u${users.length + 1}', name, role, 'Shift active');
    users.add(user);
    notifyListeners();
  }

  /// Manager/admin action: create a real login account on the hub (username +
  /// password + role). Returns null on success, or an error message to show
  /// the manager. Requires a live backend connection — a local-only account
  /// couldn't actually log in.
  Future<String?> createStaffAccount({
    required String name,
    required String firstName,
    required String lastName,
    required String username,
    required String password,
    required UserRole role,
  }) async {
    if (!backendConnected) {
      return L.accountNeedsConnection;
    }
    try {
      final created = await _remoteApi.createStaffAccount(
        name: name,
        firstName: firstName,
        lastName: lastName,
        username: username,
        password: password,
        role: roleToWire(role),
      );
      final id = created['id']?.toString() ?? 'u${users.length + 1}';
      users.add(AppUser(id, name, role, 'Shift active', online: false));
      await refreshStaffAccounts();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      debugPrint('createStaffAccount failed: $e');
      return e.message;
    }
  }

  void sendMessage(String text, {bool voice = false}) {
    if (currentGroup == null || text.trim().isEmpty) return;
    final tags = RegExp(r'#[\wа-яА-Я]+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
    messages.add(ChatMessage(
      id: _nextMessageId(),
      groupId: currentGroup!.id,
      senderId: currentUser?.id ?? 'me',
      text: text,
      tags: tags,
      timestamp: DateTime.now(),
      own: true,
      voice: voice,
    ));
    _saveMessages();
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  void react(ChatMessage message, String reaction) {
    message.reactions = [...message.reactions, reaction];
    _saveMessages();
    notifyListeners();
  }

  /// Station action (cook/bartender): start preparation. Readiness is tracked
  /// per order item, because mixed kitchen/bar orders must not become ready
  /// until every station has finished its own items.
  void advanceStationStatus(CafeOrder order) {
    final previous = order.status;
    final next = order.status == OrderStatus.accepted
        ? OrderStatus.cooking
        : order.status;
    if (next == previous) return;
    order.status = next;
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (backendConnected) _pushOrderStatus(order, previous);
  }

  /// Station action: mark only this station's items ready. A mixed order is
  /// ready only after both kitchen and bar items are ready.
  Future<void> markStationItemsReady(CafeOrder order, FeedType zone) async {
    final lines = order.itemsFor(zone).where((line) => !line.ready).toList();
    if (lines.isEmpty) return;
    final previous = order.status;
    for (final line in lines) {
      line.ready = true;
    }
    _syncLocalOrderStatus(order);
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (backendConnected) {
      await _pushItemsReady(order, lines, previous);
    }
  }

  /// Station or floor action: mark one item prepared (ready) without changing
  /// the other items on the ticket.
  Future<void> markOrderItemReady(CafeOrder order, CartLine line) async {
    if (line.ready || line.done) return;
    final previous = order.status;
    line.ready = true;
    _syncLocalOrderStatus(order);
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (backendConnected) {
      await _pushItemsReady(order, [line], previous);
    }
  }

  /// Waiter/manager action: deliver one ready item, not the whole order.
  Future<void> toggleOrderItemDelivered(CafeOrder order, CartLine line) async {
    if (!line.ready && !line.done) return;
    final previousStatus = order.status;
    final previousDone = line.done;
    final previousReady = line.ready;
    line.done = !line.done;
    if (line.done) line.ready = true;
    _syncLocalOrderStatus(order);
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (backendConnected && line.orderItemId != null) {
      await _pushItemDone(
          order, line, previousDone, previousReady, previousStatus);
    }
  }

  /// Waiter/manager action: delete one sent item from a live order.
  /// Optimistic — removes it locally, then pushes the delete; the hub
  /// recalculates the order (cancelling it if this was the last item) and
  /// echoes the change back. Restores the item on backend failure.
  Future<void> deleteOrderItem(CafeOrder order, CartLine line) async {
    final index = order.items.indexOf(line);
    if (index < 0) return;
    final previousStatus = order.status;
    order.items.removeAt(index);
    final orderRemoved = order.items.isEmpty;
    if (orderRemoved) {
      orders.remove(order);
    } else {
      _syncLocalOrderStatus(order);
    }
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (backendConnected && line.orderItemId != null) {
      try {
        await _remoteApi.deleteOrderItem(line.orderItemId!);
      } on ApiException catch (e) {
        if (orderRemoved && !orders.contains(order)) orders.add(order);
        order.items.insert(index.clamp(0, order.items.length), line);
        order.status = previousStatus;
        backendError = e.message;
        debugPrint('deleteOrderItem push failed: $e');
        notifyListeners();
      }
    }
  }

  // --- guest-order approval -------------------------------------------------

  /// Guest orders waiting for a waiter to approve them, newest first. Drives
  /// the "Pending approval" inbox. Station roles never approve, so it's empty
  /// for them.
  List<CafeOrder> get pendingApprovalOrders {
    if (isStationRole) return const [];
    final pending = orders
        .where((o) => o.status == OrderStatus.awaiting)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return pending;
  }

  /// Waiter/manager approves a pending guest order: it moves into the normal
  /// kitchen/bar pipeline (awaiting -> accepted). Optimistic, with rollback.
  Future<String?> confirmGuestOrder(CafeOrder order) async {
    if (order.status != OrderStatus.awaiting) return null;
    order.status = OrderStatus.accepted;
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (!backendConnected) return null;
    try {
      await _remoteApi.confirmOrder(order.id);
      return null;
    } on ApiException catch (e) {
      order.status = OrderStatus.awaiting;
      backendError = e.message;
      debugPrint('confirmGuestOrder failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  /// Waiter/manager rejects a pending guest order: it is cancelled and dropped
  /// from the local list. Optimistic, with rollback.
  Future<String?> rejectGuestOrder(CafeOrder order) async {
    if (order.status != OrderStatus.awaiting) return null;
    orders.remove(order);
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (!backendConnected) return null;
    try {
      await _remoteApi.rejectOrder(order.id);
      return null;
    } on ApiException catch (e) {
      if (!orders.contains(order)) orders.add(order);
      backendError = e.message;
      debugPrint('rejectGuestOrder failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  /// Count of items across a table's active orders that are ready but not yet
  /// delivered — drives the "Deliver all ready (n)" button.
  int readyToDeliverCount(String tableId) {
    var n = 0;
    for (final order in orders.where((o) => o.tableId == tableId)) {
      for (final line in order.items) {
        if (line.ready && !line.done) n++;
      }
    }
    return n;
  }

  /// Waiter/manager action: deliver the ready-but-undelivered items in [lines]
  /// (a single order, optionally narrowed to one station's items in the feed).
  /// Runs per item so each goes through the item-level path.
  Future<void> deliverReadyLines(CafeOrder order, List<CartLine> lines) async {
    final pending = lines.where((l) => l.ready && !l.done).toList();
    for (final line in pending) {
      await toggleOrderItemDelivered(order, line);
    }
  }

  /// Waiter/manager action: deliver every ready item on this table at once.
  /// Runs one-by-one (per item) so each delivery goes through the same
  /// item-level path — the order only completes once its last item is served.
  Future<void> deliverAllReadyForTable(String tableId) async {
    // Snapshot first: toggleOrderItemDelivered mutates state as it goes.
    final pending = <(CafeOrder, CartLine)>[];
    for (final order in orders.where((o) => o.tableId == tableId)) {
      for (final line in order.items) {
        if (line.ready && !line.done) pending.add((order, line));
      }
    }
    for (final (order, line) in pending) {
      await toggleOrderItemDelivered(order, line);
    }
  }

  void _syncLocalOrderStatus(CafeOrder order) {
    if (order.items.isEmpty) return;
    // A pending guest order stays awaiting until a waiter confirms it — item
    // readiness must never silently push it into the kitchen/bar pipeline.
    if (order.status == OrderStatus.awaiting) return;
    if (order.items.every((line) => line.done)) {
      order.status = OrderStatus.completed;
    } else if (order.items.every((line) => line.ready)) {
      order.status = OrderStatus.ready;
    } else if (order.items.any((line) => line.ready) ||
        order.status == OrderStatus.cooking) {
      order.status = OrderStatus.cooking;
    } else {
      order.status = OrderStatus.accepted;
    }
  }

  Future<void> _pushItemsReady(
      CafeOrder order, List<CartLine> lines, OrderStatus rollback) async {
    try {
      for (final line in lines) {
        final id = line.orderItemId;
        if (id != null) await _remoteApi.markItemReady(id);
      }
    } on ApiException catch (e) {
      for (final line in lines) {
        line.ready = false;
      }
      order.status = rollback;
      backendError = e.message;
      debugPrint('markItemReady push failed: $e');
      notifyListeners();
    }
  }

  Future<void> _pushItemDone(CafeOrder order, CartLine line, bool rollbackDone,
      bool rollbackReady, OrderStatus rollbackStatus) async {
    try {
      await _remoteApi.toggleItemDone(line.orderItemId!);
    } on ApiException catch (e) {
      line.done = rollbackDone;
      line.ready = rollbackReady;
      order.status = rollbackStatus;
      backendError = e.message;
      debugPrint('toggleItemDone push failed: $e');
      notifyListeners();
    }
  }

  Future<void> _pushOrderStatus(CafeOrder order, OrderStatus rollback) async {
    final wire = switch (order.status) {
      OrderStatus.ready => 'ready',
      OrderStatus.completed => 'completed',
      OrderStatus.cooking => 'cooking',
      OrderStatus.accepted => 'new',
      // Awaiting orders are moved via confirm/reject, never this status push.
      OrderStatus.awaiting => 'awaiting',
    };
    try {
      await _remoteApi.updateOrderStatus(order.id, wire);
    } on ApiException catch (e) {
      order.status = rollback; // optimistic rollback
      backendError = e.message;
      debugPrint('markReady push failed: $e');
      notifyListeners();
    }
  }

  Future<void> resetToDemo() async {
    await _box.clear();
    tableChecks.clear();
    await boot();
  }

  // ===================== Backend integration (Django hub) =====================
  //
  // The app boots fully local (Hive demo) so it always works offline. Calling
  // [connectBackend] swaps in live data from the CafeConnect hub and subscribes
  // to realtime order/attention events. Failures fall back to local mode and
  // never throw to the UI (Vision: optimistic, never blocks on a spinner).

  /// Authenticate, hydrate live data, and open the realtime feed.
  /// Returns true on success; on failure keeps the local demo and returns false.
  Future<bool> connectBackend({
    required String username,
    required String password,
  }) async {
    _lastUser = username;
    _lastPass = password;
    backendConnecting = true;
    notifyListeners();
    try {
      final token = await _remoteApi.login(username, password);
      final data = await _remoteApi.bootstrap();
      _applyBootstrap(data);

      online = true;
      backendConnected = true;
      backendConnecting = false;
      backendError = null;
      // Persist the DRF token (not the password) so the app reconnects by
      // itself after a PWA restart instead of silently falling back to demo.
      _box.put('apiToken', token);
      _box.put('apiUser', username);

      await _openRealtime(token);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      backendConnected = false;
      backendConnecting = false;
      backendError = e.message;
      online = false;
      debugPrint('connectBackend failed: $e');
      notifyListeners();
      return false;
    } catch (e, st) {
      backendConnected = false;
      backendConnecting = false;
      backendError = 'Unexpected error: $e';
      online = false;
      debugPrint('connectBackend unexpected: $e\n$st');
      notifyListeners();
      return false;
    }
  }

  /// Connect using a previously issued DRF token (saved in Hive after a
  /// successful login). On an auth error the stale token is dropped so the
  /// Settings login form reappears.
  Future<bool> connectWithToken(String token) async {
    backendConnecting = true;
    notifyListeners();
    try {
      _remoteApi.setToken(token);
      final data = await _remoteApi.bootstrap();
      _applyBootstrap(data);

      online = true;
      backendConnected = true;
      backendConnecting = false;
      backendError = null;

      await _openRealtime(token);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _remoteApi.setToken(null);
      if (e.isAuth) {
        _box.delete('apiToken'); // token revoked/expired — ask for login again
      }
      backendConnected = false;
      backendConnecting = false;
      backendError = e.message;
      debugPrint('connectWithToken failed: $e');
      notifyListeners();
      return false;
    } catch (e, st) {
      _remoteApi.setToken(null);
      backendConnected = false;
      backendConnecting = false;
      backendError = 'Unexpected error: $e';
      debugPrint('connectWithToken unexpected: $e\n$st');
      notifyListeners();
      return false;
    }
  }

  /// Re-run the connection using the saved token, in-memory credentials or
  /// build-time credentials. Used by Settings → "Reconnect".
  Future<bool> reconnect() async {
    final user = _lastUser ?? const String.fromEnvironment('API_USERNAME');
    final pass = _lastPass ?? const String.fromEnvironment('API_PASSWORD');
    if (user.isNotEmpty && pass.isNotEmpty) {
      return connectBackend(username: user, password: pass);
    }
    final savedToken = _box.get('apiToken') as String?;
    if (savedToken != null && savedToken.isNotEmpty) {
      return connectWithToken(savedToken);
    }
    backendError = 'No login data. Enter username and password below.';
    notifyListeners();
    return false;
  }

  void _applyBootstrap(BootstrapDto data) {
    activeRestaurant = data.restaurant;
    availableRestaurants = data.availableRestaurants;
    isPlatformOwner = data.isPlatformOwner;
    if (data.restaurant != null) {
      ApiConfig.restaurantSlug = data.restaurant!.slug;
      _box.put('restaurantSlug', data.restaurant!.slug);
      currencySymbol =
          data.restaurant!.currency == 'EUR' ? '€' : data.restaurant!.currency;
    }
    final user = data.currentUser;
    if (user != null) {
      activeEmployeeId = int.tryParse(user.employeeId ?? '');
      if (user.role.isNotEmpty) {
        currentRole = roleFromWire(user.role);
        _box.put('currentRole', currentRole.index);
      }
      _applyCapabilities(user.capabilities, currentRole);
      if (user.name.isNotEmpty) {
        activeUserName = user.name;
        _box.put('activeUserName', user.name);
      }
      // The hub is the source of truth for the shift state.
      isOnShift = user.isOnShift;
      shiftAreas = user.shiftAreas;
      lastShiftAreas = user.lastShiftAreas;
      _box.put('isOnShift', isOnShift);
    }
    pushEnabled = data.pushEnabled;
    pushPublicKey = data.pushPublicKey;
    menu
      ..clear()
      ..addAll(data.menu.map(_menuFromDto));
    _saveMenu();
    menuCategories
      ..clear()
      ..addAll(data.categories.map((category) => CafeCategory(
            id: category.id,
            key: category.key,
            name: category.name,
            color: CafeCategory.parseHex(category.color, AppColors.famFood),
          )));
    tables
      ..clear()
      ..addAll(data.tables.map(_tableFromDto));
    _saveTables();
    orders
      ..clear()
      ..addAll(data.orders.map(_orderFromDto));
    archivedOrders
      ..clear()
      ..addAll(data.history.map(_orderFromDto));
    // Ladders for anything already pending (a device that just came on shift
    // must not sit silent next to a waiting guest); stale alerts resolve.
    _syncAlertsFromState();
    // Unread chat badges (fire-and-forget; the WS keeps them live after).
    refreshChatRead();
  }

  // ---- Alerts: ladder wiring ------------------------------------------------

  int _tableNumberFor(String tableId) =>
      tables.firstWhereOrNull((t) => t.id == tableId)?.number ?? 0;

  /// Floor staff (waiter capability) handle guest calls and approve guest
  /// orders — pure station devices stay out of this alert path entirely.
  bool get _alertsApply => capWait;

  bool _isMyTable(CafeTable? table) =>
      table == null ||
      table.waiterId == null ||
      table.waiterId == activeEmployeeId?.toString() ||
      table.attentionEscalated;

  /// Reconcile the ladder with current state: start alerts for every unacked
  /// call/bill and AWAITING order, resolve alerts whose source is gone.
  void _syncAlertsFromState() {
    if (!_alertsApply) return;
    final liveIds = <String>{};
    for (final table in tables) {
      // 'arrived' is informational — only call/bill ring the ladder.
      if (table.attention != null &&
          table.attention != 'arrived' &&
          table.lastSignalId != null &&
          _isMyTable(table)) {
        final id = 'attention-${table.lastSignalId}';
        liveIds.add(id);
        alertService.trigger(
          id: id,
          kind: table.attention == 'bill' ? AlertKind.bill : AlertKind.call,
          tableNumber: table.number,
          escalatedShared: table.attentionEscalated,
        );
      }
    }
    for (final order in orders) {
      if (order.status != OrderStatus.awaiting) continue;
      final table = tables.firstWhereOrNull((t) => t.id == order.tableId);
      if (table != null && !_isMyTable(table) && !order.alertEscalated) {
        continue;
      }
      final id = 'order-${order.id}';
      liveIds.add(id);
      alertService.trigger(
        id: id,
        kind: AlertKind.order,
        tableNumber: _tableNumberFor(order.tableId),
        escalatedShared: order.alertEscalated,
      );
    }
    for (final alert in alertService.active) {
      if (!liveIds.contains(alert.id)) alertService.resolve(alert.id);
    }
  }

  /// L3 reached on this device: flag it server-side (idempotent) so every
  /// on-shift device highlights the event. 409 = already handled — fine.
  Future<void> _escalateRemote(ActiveAlert alert) async {
    final pk = alert.id.split('-').last;
    try {
      if (alert.kind == AlertKind.order) {
        await _remoteApi.escalateOrder(pk);
      } else {
        await _remoteApi.escalateSignal(pk);
      }
    } on ApiException catch (e) {
      debugPrint('escalate failed: $e');
    }
  }

  /// The in-app banner's Accept. For a call/bill it IS the domain action
  /// (ack the signal — the hub broadcasts and every device silences). For a
  /// guest order Accept only navigates: the order is handled by confirm or
  /// reject, which resolve the alert everywhere via order.updated.
  Future<void> acceptAlert(ActiveAlert alert) async {
    if (alert.kind == AlertKind.order) return;
    alertService.resolve(alert.id);
    final pk = alert.id.split('-').last;
    try {
      await _remoteApi.ackAttention(pk);
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('acceptAlert ack failed: $e');
      notifyListeners();
    }
  }

  Future<String?> takeOverTable(CafeTable table) async {
    if (!backendConnected) return L.connectToManage;
    try {
      final dto = await _remoteApi.takeOverTable(table.id);
      _applyTableUpdate(dto);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      backendError = error.message;
      notifyListeners();
      return error.message;
    }
  }

  /// The "On shift" toggle: one gesture unlocks audio + notifications, flips
  /// the hub flag, and manages the Web-Push subscription. Returns null on
  /// success or a message for the UI.
  Future<String?> setOnShift(bool on,
      {List<String>? areas, bool force = false}) async {
    if (!backendConnected) return L.connectToManage;
    try {
      var osNotificationsGranted = false;
      if (on) {
        // Inside the tap: permission prompt + silent clip + 1ms vibration —
        // the legal unlock for AudioContext, notifications and vibration.
        osNotificationsGranted = await alertPlatform.unlock();
      }
      final shift = await _remoteApi.setShift(on, areas: areas, force: force);
      isOnShift = shift.on;
      shiftAreas = shift.areas;
      lastShiftAreas = shift.preset;
      _box.put('isOnShift', isOnShift);
      if (on) {
        if (pushEnabled && osNotificationsGranted) {
          final subscription = await alertPlatform.subscribePush(pushPublicKey);
          if (subscription != null) {
            try {
              await _remoteApi.pushSubscribe(
                endpoint: subscription.endpoint,
                p256dh: subscription.p256dh,
                auth: subscription.auth,
              );
            } on ApiException catch (e) {
              debugPrint('push subscribe failed: $e');
            }
          }
        }
        _syncAlertsFromState(); // pending guests start alerting immediately
      } else {
        alertService.silenceAll();
        final endpoint = await alertPlatform.unsubscribePush();
        if (endpoint != null) {
          try {
            await _remoteApi.pushUnsubscribe(endpoint);
          } on ApiException catch (e) {
            debugPrint('push unsubscribe failed: $e');
          }
        }
      }
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      notifyListeners();
      return e.message;
    }
  }

  Future<String?> switchRestaurant(RestaurantDto restaurant) async {
    if (activeRestaurant?.slug == restaurant.slug) return null;
    ApiConfig.restaurantSlug = restaurant.slug;
    _box.put('restaurantSlug', restaurant.slug);
    alertService.silenceAll();
    chatByChannel.clear();
    chatUnread.clear();
    tableChecks.clear();
    _pendingQueue.clear();
    tables.clear();
    menu.clear();
    menuCategories.clear();
    orders.clear();
    archivedOrders.clear();
    notifyListeners();
    final token = _remoteApi.token;
    if (token == null) return L.connectToManage;
    return await connectWithToken(token) ? null : backendError;
  }

  Future<String?> createRestaurant(String name, String slug) async {
    try {
      final restaurant =
          await _remoteApi.createRestaurant(name: name, slug: slug);
      availableRestaurants = [...availableRestaurants, restaurant]
        ..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      notifyListeners();
      return e.message;
    }
  }

  Future<void> refreshPortfolio() async {
    if (!isPlatformOwner || portfolioLoading) return;
    portfolioLoading = true;
    notifyListeners();
    try {
      portfolioRestaurants = await _remoteApi.platformRestaurants();
    } on ApiException catch (error) {
      backendError = error.message;
    } finally {
      portfolioLoading = false;
      notifyListeners();
    }
  }

  void setAlertsQuiet(bool quiet) {
    alertsQuiet = quiet;
    _box.put('alertsQuiet', quiet);
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && backendConnected) {
      _ensureLiveAndResync();
    }
  }

  /// Re-open the realtime socket if it died while we were away, then pull the
  /// authoritative state so nothing is stale.
  Future<void> _ensureLiveAndResync() async {
    final token = _remoteApi.token;
    if (token == null) return;
    if (_realtime == null || !_realtime!.isConnected) {
      await _openRealtime(token);
    }
    await _resyncFromServer();
  }

  /// Pull the current state from the hub and re-apply it — catches up after
  /// the socket dropped (backgrounding, a Render blip, a flaky network).
  Future<void> _resyncFromServer() async {
    if (!backendConnected || _resyncing) return;
    _resyncing = true;
    try {
      final data = await _remoteApi.bootstrap();
      _applyBootstrap(data);
      backendError = null;
      notifyListeners();
    } on ApiException catch (e) {
      debugPrint('resync failed: $e'); // keep last-known state; retry next tick
    } finally {
      _resyncing = false;
    }
  }

  Future<void> _openRealtime(String token) async {
    await _realtimeSub?.cancel();
    await _realtime?.dispose();
    final client = StaffRealtimeClient();
    _realtime = client;
    _realtimeSub = client.events.listen(_onRealtimeEvent);
    await client.connect(token);
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    switch (event.type) {
      case RealtimeEventType.orderCreated:
        final createdDto = event.order;
        if (createdDto != null) {
          _upsertOrderFromDto(createdDto);
          if (capWait) unawaited(refreshTableBill(createdDto.tableId));
          // A fresh guest order starts the escalation ladder (L1 chime +
          // banner) on every on-shift floor device. The ladder replaces the
          // old bare heavyImpact buzz.
          if (_alertsApply &&
              _orderStatusFromName(createdDto.status) == OrderStatus.awaiting &&
              _isMyTable(tables.firstWhereOrNull(
                  (table) => table.id == createdDto.tableId))) {
            alertService.trigger(
              id: 'order-${createdDto.id}',
              kind: AlertKind.order,
              tableNumber: _tableNumberFor(createdDto.tableId),
            );
          }
        }
        break;
      case RealtimeEventType.orderUpdated:
        final dto = event.order;
        if (dto != null) {
          _upsertOrderFromDto(dto);
          if (capWait) unawaited(refreshTableBill(dto.tableId));
          // Left AWAITING (confirmed/rejected anywhere): the alert is
          // handled — silence this device and close its OS banner.
          if (_orderStatusFromName(dto.status) != OrderStatus.awaiting) {
            alertService.resolve('order-${dto.id}');
          }
        }
        break;
      case RealtimeEventType.orderEscalated:
        final dto = event.order;
        if (dto != null) {
          _upsertOrderFromDto(dto);
          if (_alertsApply &&
              _orderStatusFromName(dto.status) == OrderStatus.awaiting) {
            alertService.markEscalated(
              id: 'order-${dto.id}',
              kind: AlertKind.order,
              tableNumber: _tableNumberFor(dto.tableId),
            );
          }
        }
        break;
      case RealtimeEventType.tableUpdated:
        _applyTableUpdate(event.table);
        break;
      case RealtimeEventType.attentionCreated:
        _applyAttention(event.attention, acked: false);
        final signal = event.attention;
        if (signal != null && _alertsApply && signal.signalType != 'arrived') {
          final table = tables.firstWhereOrNull((t) => t.id == signal.tableId);
          if (table != null && !_isMyTable(table)) break;
          alertService.trigger(
            id: 'attention-${signal.id}',
            kind: signal.signalType == 'bill_request'
                ? AlertKind.bill
                : AlertKind.call,
            tableNumber: _tableNumberFor(signal.tableId),
          );
        }
        break;
      case RealtimeEventType.attentionAcked:
        _applyAttention(event.attention, acked: true);
        // First handler (or the guest cancelling) clears every device.
        if (event.attention != null) {
          alertService.resolve('attention-${event.attention!.id}');
        }
        break;
      case RealtimeEventType.attentionEscalated:
        final escalated = event.attention;
        if (escalated != null && _alertsApply && !escalated.ack) {
          alertService.markEscalated(
            id: 'attention-${escalated.id}',
            kind: escalated.signalType == 'bill_request'
                ? AlertKind.bill
                : AlertKind.call,
            tableNumber: _tableNumberFor(escalated.tableId),
          );
        }
        break;
      case RealtimeEventType.chatMessage:
      case RealtimeEventType.chatUpdated:
        if (event.chatMessage != null) _applyChatMessage(event.chatMessage!);
        break;
      case RealtimeEventType.taskUpdated:
        if (event.task != null) _applyTaskUpdate(event.task!);
        break;
      case RealtimeEventType.connectionReady:
        // Every reconnect: pull current state so events missed while the
        // socket was down don't leave this device stale. Skip the first
        // connect — the initial bootstrap already loaded everything.
        if (_realtimeEverConnected) {
          _resyncFromServer();
        }
        _realtimeEverConnected = true;
        break;
      case RealtimeEventType.unknown:
        break;
    }
  }

  /// Server is the source of truth for table state: apply `table.updated`
  /// (status change, freed table, acked signal — from any device or the
  /// guest page) to the matching tile.
  void _applyTableUpdate(TableDto? dto) {
    if (dto == null) return;
    final table = tables.firstWhereOrNull((t) => t.id == dto.id);
    if (table == null) return;
    table.status = _tableStatusFromName(dto.status);
    table.guestCount = dto.guestCount;
    table.attention = dto.ack ? null : dto.attention;
    if (table.attention == null) table.lastSignalId = null;
    if (dto.waiter.isNotEmpty) table.waiterName = dto.waiter;
    table.waiterId = dto.waiterId;
    table.openedAt =
        dto.openedAt == null ? null : DateTime.tryParse(dto.openedAt!);
    if (table.status == TableStatus.free) {
      table.currentOrderId = null;
      tableChecks[table.id]?.clear();
      // The hub archived this visit's orders (PAID) — drop the local copies
      // so the history disappears everywhere at the same time.
      orders.removeWhere((o) => o.tableId == table.id);
    }
    _saveTables();
    notifyListeners();
  }

  void _upsertOrderFromDto(OrderDto dto) =>
      _upsertLocalOrder(_orderFromDto(dto));

  void _upsertLocalOrder(CafeOrder order) {
    final index = orders.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      orders[index] = order;
    } else {
      orders.add(order);
      // A brand-new order (created here, echoed from the hub, or replayed from
      // the offline queue) drops a receipt card into General + its station
      // chat. addSystemMessage is idempotent, so the realtime echo of an order
      // we just created locally won't post it twice.
      addSystemMessage(order);
    }
    // Note: no local table-status inference here — the hub broadcasts
    // `table.updated` alongside every order event, so guessing locally would
    // only fight the server state.
    notifyListeners();
  }

  /// Apply a guest attention signal to the matching table tile.
  void _applyAttention(AttentionDto? signal, {required bool acked}) {
    if (signal == null) return;
    final table = tables.firstWhereOrNull((t) => t.id == signal.tableId);
    if (table == null) return;
    if (acked) {
      table.attention = null;
      table.lastSignalId = null;
    } else {
      table.attention = switch (signal.signalType) {
        'call_waiter' => 'call',
        'bill_request' => 'bill',
        'arrived' => 'arrived',
        _ => null,
      };
      table.lastSignalId = signal.id;
      HapticFeedback.mediumImpact();
    }
    _saveTables();
    notifyListeners();
  }

  /// Push a new order to the hub. On success the hub broadcasts `order.created`,
  /// which [_onRealtimeEvent] upserts — so we do not also add it locally here,
  /// to avoid duplicates. Wire this into the precheck "send" button when
  /// [backendConnected] is true (the local [submitOrder] remains the offline path).
  Future<OrderDto?> createRemoteOrder({
    required String tableId,
    required List<CartLine> lines,
    required String requestId,
    String notes = '',
  }) async {
    if (!backendConnected) return null;
    final tableIdInt = int.tryParse(tableId);
    if (tableIdInt == null) {
      debugPrint('createRemoteOrder: non-numeric tableId "$tableId"');
      return null;
    }
    try {
      return await _remoteApi.createOrder(
        tableId: tableIdInt,
        clientRequestId: requestId,
        notes: notes,
        items: lines
            .map((l) => {
                  'menu_item_id': int.tryParse(l.item.id) ?? l.item.id,
                  'quantity': l.quantity,
                  'notes': l.modifiers.isEmpty ? <String>[] : [l.modifiers],
                })
            .toList(),
      );
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('createRemoteOrder failed: $e');
      notifyListeners();
      return null;
    }
  }

  // --- Content: venue social feed + storefront -------------------------------
  // Loaded lazily when the Content section opens. Every mutation surfaces the
  // hub's error message verbatim (returns it to the caller) — nothing is
  // swallowed silently.

  List<SocialPostDto> feedPosts = [];
  int feedPinnedLimit = 3;
  bool feedLoading = false;
  VenueSettingsDto? venueSettings;
  List<ThemePresetDto> themePresets = [];
  bool venueLoading = false;

  int get pinnedPostCount => feedPosts.where((p) => p.isPinned).length;

  Future<String?> refreshContentFeed() async {
    if (!backendConnected) return L.connectToManage;
    feedLoading = true;
    notifyListeners();
    try {
      final dto = await _remoteApi.staffFeed();
      feedPosts = dto.posts;
      feedPinnedLimit = dto.pinnedLimit;
      return null;
    } on ApiException catch (e) {
      debugPrint('refreshContentFeed failed: $e');
      return e.message;
    } finally {
      feedLoading = false;
      notifyListeners();
    }
  }

  /// Create a post from a pasted URL. Returns null on success or the hub's
  /// error message (invalid link, duplicate, …) to show verbatim.
  Future<String?> addFeedPost(String url) async {
    if (!backendConnected) return L.connectToManage;
    try {
      await _remoteApi.createFeedPost(url);
      return refreshContentFeed();
    } on ApiException catch (e) {
      debugPrint('addFeedPost failed: $e');
      return e.message;
    }
  }

  void _replaceFeedPost(SocialPostDto updated) {
    final i = feedPosts.indexWhere((p) => p.id == updated.id);
    if (i >= 0) feedPosts[i] = updated;
    notifyListeners();
  }

  /// Pin/unpin. Exceeding the pinned limit is the hub's 409 — its message is
  /// returned for the UI to show as-is.
  Future<String?> setFeedPostPinned(SocialPostDto post, bool pinned) async {
    try {
      final updated = pinned
          ? await _remoteApi.pinFeedPost(post.id)
          : await _remoteApi.unpinFeedPost(post.id);
      _replaceFeedPost(updated);
      // Order (pinned first) comes from the hub — refresh keeps it canonical.
      return refreshContentFeed();
    } on ApiException catch (e) {
      debugPrint('setFeedPostPinned failed: $e');
      return e.message;
    }
  }

  Future<String?> toggleFeedPostHidden(SocialPostDto post) async {
    try {
      _replaceFeedPost(await _remoteApi.toggleFeedPostHidden(post.id));
      return null;
    } on ApiException catch (e) {
      debugPrint('toggleFeedPostHidden failed: $e');
      return e.message;
    }
  }

  Future<String?> deleteFeedPost(SocialPostDto post) async {
    try {
      await _remoteApi.deleteFeedPost(post.id);
      feedPosts.removeWhere((p) => p.id == post.id);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      debugPrint('deleteFeedPost failed: $e');
      return e.message;
    }
  }

  Future<String?> refreshVenueSettings() async {
    if (!backendConnected) return L.connectToManage;
    venueLoading = true;
    notifyListeners();
    try {
      final payload = await _remoteApi.venueSettings();
      venueSettings = payload.venue;
      themePresets = payload.presets;
      return null;
    } on ApiException catch (e) {
      debugPrint('refreshVenueSettings failed: $e');
      return e.message;
    } finally {
      venueLoading = false;
      notifyListeners();
    }
  }

  /// PATCH storefront fields (DRF wire names). Returns null on success or the
  /// hub's validation message (bad HEX, unknown block, …) verbatim.
  Future<String?> saveVenueSettings(Map<String, dynamic> fields) async {
    if (!backendConnected) return L.connectToManage;
    try {
      final payload = await _remoteApi.updateVenueSettings(fields);
      venueSettings = payload.venue;
      themePresets = payload.presets;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      debugPrint('saveVenueSettings failed: $e');
      return e.message;
    }
  }

  /// Upload or remove ([bytes] == null) the venue logo/cover.
  Future<String?> setVenueImage(String kind,
      {List<int>? bytes, String filename = 'image.jpg'}) async {
    if (!backendConnected) return L.connectToManage;
    try {
      final payload = bytes == null
          ? await _remoteApi.deleteVenueImage(kind)
          : await _remoteApi.uploadVenueImage(kind, bytes, filename);
      venueSettings = payload.venue;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      debugPrint('setVenueImage failed: $e');
      return e.message;
    }
  }

  // --- Coupons: campaigns, issue, redeem -------------------------------------
  // Same contract as the content section: every mutation returns null on
  // success or the hub's error message verbatim for the UI to show.

  List<CouponCampaignDto> couponCampaigns = [];
  bool couponCampaignsLoading = false;

  /// Active campaigns only — what the Issue screen offers.
  List<CouponCampaignDto> get issuableCampaigns =>
      couponCampaigns.where((c) => c.isActive).toList();

  Future<String?> refreshCouponCampaigns() async {
    if (!backendConnected) return L.connectToManage;
    couponCampaignsLoading = true;
    notifyListeners();
    try {
      couponCampaigns = await _remoteApi.couponCampaigns();
      return null;
    } on ApiException catch (e) {
      debugPrint('refreshCouponCampaigns failed: $e');
      return e.message;
    } finally {
      couponCampaignsLoading = false;
      notifyListeners();
    }
  }

  Future<String?> saveCouponCampaign(Map<String, dynamic> fields,
      {int? id}) async {
    if (!backendConnected) return L.connectToManage;
    try {
      if (id == null) {
        await _remoteApi.createCouponCampaign(fields);
      } else {
        await _remoteApi.updateCouponCampaign(id, fields);
      }
      return refreshCouponCampaigns();
    } on ApiException catch (e) {
      debugPrint('saveCouponCampaign failed: $e');
      return e.message;
    }
  }

  /// Signed claim link for the fullscreen issue QR. Returns (result, error) —
  /// exactly one of the two is non-null.
  Future<(CouponIssueDto?, String?)> issueCoupon(int campaignId) async {
    if (!backendConnected) return (null, L.connectToManage);
    try {
      return (await _remoteApi.issueCoupon(campaignId), null);
    } on ApiException catch (e) {
      debugPrint('issueCoupon failed: $e');
      return (null, e.message);
    }
  }

  /// Look up a scanned/typed coupon for the confirmation sheet.
  Future<(CouponPreviewDto?, String?)> couponPreview(
      {String? token, String? code}) async {
    if (!backendConnected) return (null, L.connectToManage);
    try {
      return (
        await _remoteApi.couponRedeemPreview(token: token, code: code),
        null
      );
    } on ApiException catch (e) {
      debugPrint('couponPreview failed: $e');
      return (null, e.message);
    }
  }

  /// Redeem. The hub broadcasts order.updated for an attached order, so the
  /// discount line appears on every device via the realtime path.
  Future<(StaffCouponDto?, String?)> redeemCoupon(
      {String? token, String? code, String? orderId}) async {
    if (!backendConnected) return (null, L.connectToManage);
    try {
      final coupon = await _remoteApi.redeemCoupon(
          token: token, code: code, orderId: orderId);
      return (coupon, null);
    } on ApiException catch (e) {
      debugPrint('redeemCoupon failed: $e');
      return (null, e.message);
    }
  }

  // --- Staff chat (server-backed) + tasks ------------------------------------
  // The chat screens read ONLY this server state when connected; the legacy
  // local chat models remain for the offline demo shell.

  List<String> get chatChannels => [
        'general',
        if (capWait) 'floor',
        if (capKitchen) 'kitchen',
        if (capBar) 'bar',
      ];
  final Map<String, List<ChatMessageDto>> chatByChannel = {};
  final Map<String, int?> _chatCursors = {};
  final Map<String, bool> chatHasMore = {};
  Map<String, int> chatUnread = {};
  bool chatLoading = false;

  /// The channel currently open on screen — its messages auto-mark read and
  /// never bump the unread badge.
  String? activeChatChannel;

  List<ChatMessageDto> chatMessages(String channel) =>
      chatByChannel[channel] ?? const [];

  int get chatUnreadTotal =>
      chatUnread.values.fold(0, (sum, value) => sum + value);

  Future<void> refreshChatRead() async {
    if (!backendConnected) return;
    try {
      final state = await _remoteApi.chatReadState();
      chatUnread = state.unread;
      notifyListeners();
    } on ApiException catch (e) {
      debugPrint('refreshChatRead failed: $e');
    }
  }

  /// Open a channel: first page on first open, mark read, stop badge bumps.
  Future<String?> openChatChannel(String channel) async {
    activeChatChannel = channel;
    if (!backendConnected) return L.connectToManage;
    if (chatMessages(channel).isEmpty) {
      chatLoading = true;
      notifyListeners();
      try {
        final page = await _remoteApi.chatHistory(channel);
        chatByChannel[channel] = page.messages;
        _chatCursors[channel] = page.nextCursor;
        chatHasMore[channel] = page.hasMore;
      } on ApiException catch (e) {
        debugPrint('openChatChannel failed: $e');
        return e.message;
      } finally {
        chatLoading = false;
        notifyListeners();
      }
    }
    _markActiveChannelRead();
    return null;
  }

  void closeChatChannel() {
    activeChatChannel = null;
  }

  Future<String?> loadOlderChat(String channel) async {
    final cursor = _chatCursors[channel];
    if (!backendConnected || cursor == null) return null;
    try {
      final page = await _remoteApi.chatHistory(channel, cursor: cursor);
      chatByChannel[channel] = [...chatMessages(channel), ...page.messages];
      _chatCursors[channel] = page.nextCursor;
      chatHasMore[channel] = page.hasMore;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      debugPrint('loadOlderChat failed: $e');
      return e.message;
    }
  }

  /// Send text or a slash command; the bot's answer arrives as `result` and
  /// via the WS echo (idempotent upsert by id).
  Future<String?> sendChat({
    required String channel,
    required String body,
    int? replyTo,
  }) async {
    if (!backendConnected) return L.connectToManage;
    try {
      final sent = await _remoteApi.sendChatMessage(
          channel: channel, body: body, replyTo: replyTo);
      _applyChatMessage(sent.message);
      if (sent.result != null) _applyChatMessage(sent.result!);
      _markActiveChannelRead();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      notifyListeners();
      return e.message;
    }
  }

  void _markActiveChannelRead() {
    final channel = activeChatChannel;
    if (channel == null || !backendConnected) return;
    final newest = chatMessages(channel).firstOrNull;
    chatUnread[channel] = 0;
    notifyListeners();
    if (newest != null) {
      _remoteApi.markChatRead(channel, newest.id).catchError((Object e) {
        debugPrint('markChatRead failed: $e');
      });
    }
  }

  /// Upsert one message into its channel list (newest first). Bumps the
  /// unread badge for background channels and lets bot nudges chime at L1.
  void _applyChatMessage(ChatMessageDto message) {
    final list = [...chatMessages(message.channel)];
    final index = list.indexWhere((m) => m.id == message.id);
    final isNew = index < 0;
    if (isNew) {
      list.insert(0, message);
      list.sort((a, b) => b.id.compareTo(a.id));
    } else {
      list[index] = message;
    }
    chatByChannel[message.channel] = list;

    if (isNew) {
      final ownName = activeUserName;
      final fromSelf = !message.isBot && message.authorName == ownName;
      if (message.channel == activeChatChannel) {
        _markActiveChannelRead();
      } else if (!fromSelf) {
        chatUnread[message.channel] = (chatUnread[message.channel] ?? 0) + 1;
      }
      // Bot nudges/reminders ride alert LEVEL 1 ONLY: one soft chime, no
      // ladder, no banner — they must never feel like a guest call.
      if (message.isBot &&
          message.kind == 'system' &&
          alertService.isEnabled()) {
        alertPlatform.playTone(AlertTone.ready, soundVolume);
      }
    }
    notifyListeners();
  }

  /// task.updated: refresh the task inside every bubble + the planner lists.
  void _applyTaskUpdate(StaffTaskDto task) {
    for (final channel in chatByChannel.keys) {
      final list = chatByChannel[channel]!;
      for (var i = 0; i < list.length; i++) {
        if (list[i].task?.id == task.id) list[i] = list[i].withTask(task);
      }
    }
    final plannerIndex = plannerTasks.indexWhere((t) => t.id == task.id);
    if (plannerIndex >= 0) {
      plannerTasks[plannerIndex] = task;
    }
    notifyListeners();
  }

  // --- Planner ---------------------------------------------------------------

  List<StaffTaskDto> plannerTasks = [];
  List<StaffTaskDto> plannerRules = [];
  List<TaskAssigneeDto> taskAssignees = [];
  String? plannerDate; // ISO yyyy-MM-dd currently shown
  bool plannerLoading = false;

  Future<String?> refreshPlanner({String? date}) async {
    if (!backendConnected) return L.connectToManage;
    plannerLoading = true;
    notifyListeners();
    try {
      final result = await _remoteApi.tasksForDay(date: date);
      plannerTasks = result.tasks;
      plannerRules = result.rules;
      taskAssignees = result.assignees;
      plannerDate = date;
      return null;
    } on ApiException catch (e) {
      debugPrint('refreshPlanner failed: $e');
      return e.message;
    } finally {
      plannerLoading = false;
      notifyListeners();
    }
  }

  /// Planner quick-add — the same syntax as /task. The new task's bubble is
  /// posted to general by the hub (single source of truth).
  Future<String?> plannerQuickAdd(String input) async {
    if (!backendConnected) return L.connectToManage;
    try {
      await _remoteApi.quickAddTask(input);
      return refreshPlanner(date: plannerDate);
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> plannerCreateDaily(String input, DateTime day) async {
    if (!backendConnected) return L.connectToManage;
    var title = input.trim();
    if (title.isEmpty) return L.nothingToSend;
    int? assigneeId;
    for (final assignee in taskAssignees) {
      final marker = '@${assignee.name}';
      if (title.toLowerCase().contains(marker.toLowerCase())) {
        assigneeId = assignee.id;
        title = title
            .replaceFirst(
                RegExp(RegExp.escape(marker), caseSensitive: false), '')
            .trim();
        break;
      }
    }
    final timeMatch =
        RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(title);
    var hour = 9;
    var minute = 0;
    if (timeMatch != null) {
      hour = int.parse(timeMatch.group(1)!);
      minute = int.parse(timeMatch.group(2)!);
      title = title.replaceFirst(timeMatch.group(0)!, '').trim();
    }
    final due = DateTime(day.year, day.month, day.day, hour, minute);
    try {
      await _remoteApi.createTask({
        'title': title,
        'recurrence': 'daily',
        'recurrence_enabled': true,
        'due_at': due.toIso8601String(),
        if (assigneeId != null) 'assignee': assigneeId,
      });
      return refreshPlanner(date: plannerDate);
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> setPlannerRuleEnabled(StaffTaskDto rule, bool enabled) async {
    try {
      await _remoteApi.updateTask(rule.id, {'recurrence_enabled': enabled});
      return refreshPlanner(date: plannerDate);
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> deletePlannerRule(StaffTaskDto rule) async {
    try {
      await _remoteApi.cancelTask(rule.id);
      return refreshPlanner(date: plannerDate);
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> refreshStationHistory(FeedType zone) async {
    if (!backendConnected) return L.connectToManage;
    stationHistoryLoading = true;
    notifyListeners();
    try {
      stationHistory = await _remoteApi
          .stationHistory(zone == FeedType.kitchen ? 'kitchen' : 'bar');
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      stationHistoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshTableBill(String tableId) async {
    if (!backendConnected || !capWait) return;
    try {
      tableBills[tableId] = await _remoteApi.tableBill(tableId);
      notifyListeners();
    } on ApiException catch (e) {
      debugPrint('refreshTableBill failed: $e');
    }
  }

  /// A task's chat thread (bubble + replies) for the planner deep-link.
  Future<({ChatMessageDto? message, List<ChatMessageDto> replies})?>
      fetchTaskThread(int taskId) async {
    if (!backendConnected) return null;
    try {
      return await _remoteApi.taskThread(taskId);
    } on ApiException catch (e) {
      debugPrint('fetchTaskThread failed: $e');
      return null;
    }
  }

  /// The big Done checkbox — everywhere (bubble, planner). Errors verbatim.
  Future<String?> setTaskDone(StaffTaskDto task, bool done) async {
    if (!backendConnected) return L.connectToManage;
    _applyTaskUpdate(task.copyWith(
      status: done ? 'done' : 'in_progress',
      doneByName: done ? activeUserName : null,
      doneAt: done ? DateTime.now().toUtc().toIso8601String() : null,
      clearDone: !done,
    ));
    try {
      final updated = await _remoteApi.setTaskDone(task.id, done: done);
      _applyTaskUpdate(updated);
      return null;
    } on ApiException catch (e) {
      _applyTaskUpdate(task);
      return e.message;
    }
  }

  Future<String?> takeTask(StaffTaskDto task) async {
    if (!backendConnected) return L.connectToManage;
    _applyTaskUpdate(task.copyWith(
      assigneeId: activeEmployeeId,
      assigneeName: activeUserName,
      status: 'in_progress',
    ));
    try {
      _applyTaskUpdate(await _remoteApi.takeTask(task.id));
      return null;
    } on ApiException catch (e) {
      _applyTaskUpdate(task);
      return e.message;
    }
  }

  Future<String?> leaveTask(StaffTaskDto task, {String note = ''}) async {
    if (!backendConnected) return L.connectToManage;
    _applyTaskUpdate(task.copyWith(
      clearAssignee: true,
      status: 'available',
      clearDone: true,
    ));
    try {
      _applyTaskUpdate(await _remoteApi.leaveTask(task.id, note: note));
      return null;
    } on ApiException catch (e) {
      _applyTaskUpdate(task);
      return e.message;
    }
  }

  Future<String?> updateTask(
      StaffTaskDto task, Map<String, dynamic> fields) async {
    if (!backendConnected) return L.connectToManage;
    try {
      _applyTaskUpdate(await _remoteApi.updateTask(task.id, fields));
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  Future<String?> cancelTask(StaffTaskDto task) async {
    if (!backendConnected) return L.connectToManage;
    try {
      _applyTaskUpdate(await _remoteApi.cancelTask(task.id));
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  /// Pull the manager dashboard analytics. Safe to call from the panel's
  /// initState: no-ops offline, and a missing endpoint (older backend) just
  /// leaves [stats] null so the panel shows its live client-side numbers.
  // Real staff roster (manager access panel). Only fetched when connected.
  List<EmployeeDto> staffAccounts = [];
  bool staffAccountsLoading = false;

  Future<void> refreshStaffAccounts() async {
    if (!backendConnected) {
      staffAccounts = [];
      notifyListeners();
      return;
    }
    staffAccountsLoading = true;
    notifyListeners();
    try {
      staffAccounts = await _remoteApi.employees();
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('refreshStaffAccounts failed: $e');
    } finally {
      staffAccountsLoading = false;
      notifyListeners();
    }
  }

  /// Pull the current menu from the hub so item ids are fresh. After a
  /// server-side menu change (an item removed or deduped) a cached id would
  /// 400 on send — "Invalid primary key". Also drops any *unsent* cart line
  /// pointing at an item that no longer exists, so a table can't get stuck.
  Future<void> refreshMenu() async {
    if (!backendConnected) return;
    try {
      final data = await _remoteApi.bootstrap();
      if (data.menu.isEmpty && data.categories.isEmpty) return;
      if (data.menu.isNotEmpty) {
        menu
          ..clear()
          ..addAll(data.menu.map(_menuFromDto));
        _saveMenu();
      }
      menuCategories
        ..clear()
        ..addAll(data.categories.map((category) => CafeCategory(
              id: category.id,
              key: category.key,
              name: category.name,
              color: CafeCategory.parseHex(category.color, AppColors.famFood),
            )));
      final liveIds = menu.map((m) => m.id).toSet();
      var pruned = false;
      for (final lines in tableChecks.values) {
        final before = lines.length;
        lines.removeWhere((l) => !l.sent && !liveIds.contains(l.item.id));
        if (lines.length != before) pruned = true;
      }
      if (pruned) _saveTables();
      notifyListeners();
    } on ApiException catch (e) {
      debugPrint('refreshMenu failed: $e');
    }
  }

  /// Grant/revoke one capability for a staff member (manager action).
  /// Returns null on success or an error message.
  Future<String?> setEmployeeCapability(
      String id, String field, bool value) async {
    try {
      final updated = await _remoteApi.updateEmployee(id, {field: value});
      final i = staffAccounts.indexWhere((e) => e.id == id);
      if (i >= 0) staffAccounts[i] = updated;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('setEmployeeCapability failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  /// Manager: update a member's profile (name / role). Returns null on
  /// success, an error message otherwise.
  Future<String?> updateStaffProfile(String id,
      {String? name, String? role}) async {
    try {
      final updated = await _remoteApi.updateEmployee(id, {
        if (name != null && name.isNotEmpty) 'name': name,
        if (role != null && role.isNotEmpty) 'role': role,
      });
      final i = staffAccounts.indexWhere((e) => e.id == id);
      if (i >= 0) staffAccounts[i] = updated;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('updateStaffProfile failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  /// Manager: change a member's login (username and/or a new password).
  Future<String?> setStaffCredentials(String id,
      {String? username, String? password}) async {
    try {
      await _remoteApi.setEmployeeCredentials(id,
          username: username, password: password);
      await refreshStaffAccounts();
      return null;
    } on ApiException catch (e) {
      backendError = e.message;
      debugPrint('setStaffCredentials failed: $e');
      notifyListeners();
      return e.message;
    }
  }

  /// Fetch an order's audit trail (who did what). Empty offline / on error.
  Future<List<OrderEventDto>> orderActivity(String orderId) async {
    if (!backendConnected) return const [];
    try {
      return await _remoteApi.orderEvents(orderId);
    } on ApiException catch (e) {
      debugPrint('orderActivity failed: $e');
      return const [];
    }
  }

  Future<void> refreshStats() async {
    if (!backendConnected) {
      stats = null;
      notifyListeners();
      return;
    }
    statsLoading = true;
    notifyListeners();
    try {
      stats = await _remoteApi.stats();
    } on ApiException catch (e) {
      stats = null;
      debugPrint('refreshStats failed: $e');
    } finally {
      statsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshOrderHistory() async {
    if (!backendConnected) {
      orderHistory = [];
      notifyListeners();
      return;
    }
    orderHistoryLoading = true;
    notifyListeners();
    try {
      orderHistory = await _remoteApi.orderHistory();
    } on ApiException catch (e) {
      orderHistory = [];
      debugPrint('refreshOrderHistory failed: $e');
    } finally {
      orderHistoryLoading = false;
      notifyListeners();
    }
  }

  /// Stop realtime + clear the token (return to local-only mode).
  Future<void> disconnectBackend() async {
    alertService.silenceAll();
    await _realtimeSub?.cancel();
    _realtimeSub = null;
    await _realtime?.dispose();
    _realtime = null;
    backendConnected = false;
    _remoteApi.setToken(null);
    _box.delete('apiToken');
    _box.delete('apiUser');
    // Back to local demo — no logged-in employee, no role restrictions.
    currentRole = UserRole.admin;
    _resetCapabilities();
    _box.delete('currentRole');
    notifyListeners();
  }

  // --- DTO -> domain mappers -------------------------------------------------

  MenuItem _menuFromDto(MenuItemDto d) => MenuItem(
        id: d.id,
        name: d.name,
        nameIt: d.nameIt,
        description: d.description,
        descriptionIt: d.descriptionIt,
        price: d.price,
        category: d.category,
        categoryIt: d.categoryIt,
        imageUrl: d.imageUrl,
        tags: d.tags,
        prepTime: d.prepTime,
        available: d.available,
        promo: d.promo,
        composition: d.composition,
        allergens: d.allergens,
        station: d.station,
        categoryId: d.categoryId,
      );

  CafeTable _tableFromDto(TableDto d) {
    final table = CafeTable(
      d.id,
      d.number,
      AppTheme.cta,
      _tableStatusFromName(d.status),
      d.guestCount,
      currentOrderId: d.currentOrderId,
      notes: const [],
    );
    table.waiterName = d.waiter.isEmpty ? '—' : d.waiter;
    table.waiterId = d.waiterId;
    if (d.openedAt != null) table.openedAt = DateTime.tryParse(d.openedAt!);
    // Carry over an unacked guest signal so the badge (and the ability to
    // acknowledge it) survives an app restart.
    table.attention = d.ack ? null : d.attention;
    table.lastSignalId = d.ack ? null : d.attentionSignalId;
    table.attentionEscalated = d.ack ? false : d.attentionEscalated;
    return table;
  }

  CafeOrder _orderFromDto(OrderDto d) {
    final lines = d.items.map((it) {
      final item = menu.firstWhere(
        (m) => m.id == it.dishId,
        orElse: () => _placeholderMenuItem(it),
      );
      return CartLine(
        item: item,
        quantity: it.qty,
        modifiers: it.notes.join(', '),
        sent: true,
        ready: it.ready,
        done: it.done,
        orderItemId: it.id,
        lockedPrice: it.price > 0 ? it.price : null,
      );
    }).toList();
    return CafeOrder(
      id: d.id,
      tableId: d.tableId,
      tableNumber: d.tableNumber,
      items: lines,
      discountAmount: d.discountAmount,
      couponCode: d.couponCode,
      waiterId: d.waiterId,
      waiterName: d.waiterName,
      status: _orderStatusFromName(d.status),
      // Server timestamp, not "now": otherwise every bootstrap/WS echo reset
      // the kitchen timer of an existing order back to 00:00.
      createdAt: d.createdAt == null
          ? DateTime.now()
          : (DateTime.tryParse(d.createdAt!)?.toLocal() ?? DateTime.now()),
      acceptedAt: d.acceptedAt == null
          ? null
          : DateTime.tryParse(d.acceptedAt!)?.toLocal(),
      note: d.note,
      splitTo: d.station == 'bar' ? FeedType.bar : FeedType.kitchen,
    )..alertEscalated = d.alertEscalated;
  }

  MenuItem _placeholderMenuItem(OrderItemDto it) => MenuItem(
        id: it.dishId,
        name: it.name.isEmpty ? 'Item' : it.name,
        description: '',
        price: it.price,
        category: it.station == 'bar' ? 'Drinks' : 'Kitchen',
        imageUrl: '',
        tags: const [],
        prepTime: 5,
        station: it.station,
      );

  TableStatus _tableStatusFromName(String name) {
    switch (name) {
      case 'occupied':
      case 'ready': // legacy wire value from pre-simplification builds
        return TableStatus.occupied;
      case 'waiting':
      case 'awaitingPayment': // legacy
      case 'late': // legacy
      case 'newOrder': // legacy
        return TableStatus.waiting;
      case 'free':
      default:
        return TableStatus.free;
    }
  }

  OrderStatus _orderStatusFromName(String name) {
    switch (name) {
      case 'awaiting':
        return OrderStatus.awaiting;
      case 'cooking':
        return OrderStatus.cooking;
      case 'ready':
        return OrderStatus.ready;
      case 'completed':
        return OrderStatus.completed;
      case 'accepted':
      default:
        return OrderStatus.accepted;
    }
  }
}

class MockCafeApi {
  List<AppUser> seedUsers() => [
        AppUser('admin', 'Administrator', UserRole.admin, 'In system'),
        AppUser('manager', 'Alex Rivera', UserRole.manager, 'Online'),
        AppUser('waiter', 'Elena Sokolova', UserRole.waiter, 'On shift'),
        AppUser('cook', 'Marco Chen', UserRole.cook, 'In kitchen'),
        AppUser('bar', 'Sara Jenkins', UserRole.bartender, 'At the bar'),
      ];

  /// Offline demo floor: mirrors the real bar (30 tables), everything free.
  /// The tables screen shows an explicit demo banner until the app is logged
  /// in to the hub, so this can no longer be mistaken for live data.
  List<CafeTable> seedTables() => List.generate(
        30,
        (i) => CafeTable('t${i + 1}', i + 1, AppTheme.cta, TableStatus.free, 0),
      );

  List<MenuItem> seedMenu() => [
        MenuItem(
            id: 'm1',
            name: 'Flat white',
            description: 'Silky espresso with soft milk.',
            price: 4.50,
            category: 'Coffee',
            imageUrl:
                'https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=400',
            tags: ['Dairy'],
            prepTime: 4,
            promo: true,
            composition: 'Espresso, 3.2% milk, microfoam.',
            allergens: ['Dairy'],
            station: 'bar'),
        MenuItem(
            id: 'm2',
            name: 'Croissant',
            description: 'Warm crispy croissant.',
            price: 3.80,
            category: 'Bakery',
            imageUrl:
                'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=400',
            tags: ['Gluten'],
            prepTime: 3,
            composition: 'Flour, butter, sugar, yeast.',
            allergens: ['Gluten', 'Eggs']),
        MenuItem(
            id: 'm3',
            name: 'Benedict',
            description: 'Poached eggs with hollandaise sauce.',
            price: 18.50,
            category: 'Breakfast',
            imageUrl:
                'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=400',
            tags: ['Eggs'],
            prepTime: 14,
            promo: true,
            composition: 'Eggs, brioche, bacon, hollandaise sauce.',
            allergens: ['Eggs', 'Gluten', 'Dairy']),
        MenuItem(
            id: 'm4',
            name: 'Avocado toast',
            description: 'Sourdough bread and avocado.',
            price: 12.00,
            category: 'Breakfast',
            imageUrl:
                'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=400',
            tags: ['Vegan'],
            prepTime: 8,
            composition: 'Sourdough bread, avocado, seeds, chili.',
            allergens: ['Gluten']),
        MenuItem(
            id: 'm5',
            name: 'Cold brew',
            description: 'Cold-extraction coffee.',
            price: 5.20,
            category: 'Coffee',
            imageUrl:
                'https://images.unsplash.com/photo-1517701604599-bb29b565090c?w=400',
            tags: ['Vegan'],
            prepTime: 2,
            composition: '12-hour cold brew coffee.',
            station: 'bar'),
        MenuItem(
            id: 'm6',
            name: 'Lemonade',
            description: 'Homemade lemonade with basil.',
            price: 4.90,
            category: 'Drinks',
            imageUrl:
                'https://images.unsplash.com/photo-1621263764928-df1444c5e859?w=400',
            tags: ['Vegan'],
            prepTime: 3,
            composition: 'Lemon juice, sugar syrup, basil, soda.',
            station: 'bar'),
      ];

  List<ChatGroup> seedGroups(List<AppUser> staff) => [
        ChatGroup('g1', 'General chat', null, staff.map((s) => s.id).toList(),
            pinned: true),
        ChatGroup(
            'g2',
            'Kitchen',
            FeedType.kitchen,
            staff
                .where((s) =>
                    s.role == UserRole.cook ||
                    s.role == UserRole.manager ||
                    s.role == UserRole.admin)
                .map((s) => s.id)
                .toList(),
            pinned: true),
        ChatGroup(
            'g3',
            'Bar',
            FeedType.bar,
            staff
                .where((s) =>
                    s.role == UserRole.bartender ||
                    s.role == UserRole.manager ||
                    s.role == UserRole.admin)
                .map((s) => s.id)
                .toList()),
      ];
  // Note: no seedMessages — fake "simulated" chat traffic used to overwrite
  // the real (persisted) history on every app start.
}
