import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/utils.dart';
import '../data/cafe_api_client.dart';
import '../data/dtos.dart';
import '../data/realtime_client.dart';
import '../models/models.dart';

class CafeState extends ChangeNotifier {
  final _api = MockCafeApi();
  // --- Backend integration (CafeConnect Django hub) ---
  final CafeApiClient _remoteApi = CafeApiClient();
  StaffRealtimeClient? _realtime;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  bool backendConnected = false;
  bool backendConnecting = false;
  String? backendError;
  String? _lastUser;
  String? _lastPass;
  Box get _box => Hive.box('cafeconnect');
  final List<AppUser> users = [];
  final List<CafeTable> tables = [];
  final List<MenuItem> menu = [];
  final List<CafeOrder> orders = [];
  final List<AppUser> staff = [];
  final List<ChatGroup> groups = [];
  final List<ChatMessage> messages = [];
  final Map<String, List<CartLine>> tableChecks = {};
  final List<Map<String, dynamic>> _pendingQueue = [];
  int get pendingQueueCount => _pendingQueue.length;
  final syncSuccess = ValueNotifier<bool>(false);

  AppUser? currentUser;
  CafeTable? currentTable;
  ChatGroup? currentGroup;
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
  String activeUserName = 'Елена Соколова';

  void setSetting<T>(String key, T value, Function(T) apply) {
    apply(value);
    _box.put(key, value);
    notifyListeners();
  }

  Timer? _retryTimer;

  void refresh() => notifyListeners();

  Future<void> boot() async {
    // --- Seed users & staff (these are config, not user-editable, re-seed always) ---
    users
      ..clear()
      ..addAll(_api.seedUsers());
    staff
      ..clear()
      ..addAll(users);

    // --- Menu: load from Hive if present, else seed ---
    final rawMenu = _box.get('menu') as String?;
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
    final rawTables = _box.get('tables') as String?;
    if (rawTables != null) {
      final list = jsonDecode(rawTables) as List;
      tables
        ..clear()
        ..addAll(
            list.map((e) => CafeTable.fromJson(e as Map<String, dynamic>)));
      // Restore checks (tableChecks) for each table
      for (final t in tables) {
        final rawCheck = _box.get('check_${t.id}') as String?;
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
    final rawMessages = _box.get('chatMessages') as String?;
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
    final rawQueue = _box.get('pendingQueue') as String?;
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

    tablesPerRow = _box.get('tablesPerRow') as int? ?? 3;
    showGestureHints = _box.get('showGestureHints') as bool? ?? true;
    currencySymbol = _box.get('currencySymbol') as String? ?? r'$';
    currencyPrefix = _box.get('currencyPrefix') as bool? ?? false;
    use24hClock = _box.get('use24hClock') as bool? ?? true;
    textScale = (_box.get('textScale') as num?)?.toDouble() ?? 1.0;
    hapticsEnabled = _box.get('hapticsEnabled') as bool? ?? true;
    soundVolume = (_box.get('soundVolume') as num?)?.toDouble() ?? 0.6;
    activeUserName = _box.get('activeUserName') as String? ?? 'Елена Соколова';
    soundEnabled = _box.get('soundEnabled') as bool? ?? true;

    _retryTimer = Timer.periodic(5.seconds, (_) => retryQueuedOrders());
    currentUser = users.firstOrNull;
    notifyListeners();

    // Auto-connect, in priority order:
    //   1. a token saved from a previous successful login on this device
    //      (survives PWA restarts — this is what keeps the app "живым"
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
    _box.put('tables', jsonEncode(tables.map((t) => t.toJson()).toList()));
    for (final t in tables) {
      final check = tableChecks[t.id];
      if (check != null) {
        _box.put(
            'check_${t.id}', jsonEncode(check.map((l) => l.toJson()).toList()));
      }
    }
  }

  void _saveMenu() =>
      _box.put('menu', jsonEncode(menu.map((m) => m.toJson()).toList()));

  /// Persist chat history (bounded so Hive doesn't grow without limit).
  static const _maxStoredMessages = 500;
  void _saveMessages() {
    final recent = messages.length > _maxStoredMessages
        ? messages.sublist(messages.length - _maxStoredMessages)
        : messages;
    _box.put(
        'chatMessages', jsonEncode(recent.map((m) => m.toJson()).toList()));
  }

  String _nextMessageId() =>
      'm${DateTime.now().microsecondsSinceEpoch}';

  void setGuestCount(String tableId, int count) {
    final table = tables.firstWhereOrNull((t) => t.id == tableId);
    if (table == null) return;
    table.guestCount = count < 1 ? 1 : count;
    HapticFeedback.selectionClick();
    _saveTables();
    notifyListeners();
  }

  void toggleItemDone(CafeTable table, CartLine line) {
    line.done = !line.done;
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
    _retryTimer?.cancel();
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _remoteApi.close();
    super.dispose();
  }

  List<String> get categories =>
      ['Все', ...menu.map((m) => m.category).toSet()];

  List<CartLine> tableCart(String tableId) =>
      tableChecks.putIfAbsent(tableId, () => []);

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
  /// the category guess ("Напитки"/"Кофе") was why beer never reached the
  /// bar feed. With [onlyFor] set, only that station's lines are sent.
  ///
  /// Returns the last created order, or null when there was nothing to send
  /// (callers must tell the waiter instead of failing silently).
  Future<CafeOrder?> submitOrder({String? tableId, FeedType? onlyFor}) async {
    final table = tables.firstWhereOrNull(
        (t) => t.id == (tableId ?? currentTable?.id ?? ''));
    if (table == null) return null;
    // When connected, send to the hub; realtime echoes it back to all devices.
    if (backendConnected) return _submitOrderRemote(table, onlyFor);

    final source = tableCart(table.id);
    final toSend = source.where((l) => !l.sent).where((l) {
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
        l.sent = true;
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
  /// Kitchen and bar lines go as two separate orders so each order has a
  /// single station_scope — a "mixed" order used to disappear from the bar.
  Future<CafeOrder?> _submitOrderRemote(
      CafeTable table, FeedType? onlyFor) async {
    final source = tableCart(table.id);
    final toSend = source.where((l) => !l.sent).where((l) {
      if (onlyFor == null) return true;
      return (onlyFor == FeedType.bar) == l.isBar;
    }).toList();
    if (toSend.isEmpty) return null;

    CafeOrder? last;
    for (final lines in [
      toSend.where((l) => !l.isBar).toList(),
      toSend.where((l) => l.isBar).toList(),
    ]) {
      if (lines.isEmpty) continue;
      final dto = await createRemoteOrder(tableId: table.id, lines: lines);
      if (dto == null) {
        // Backend rejected/unreachable; these lines stay unsent and the
        // error is surfaced via backendError. Already-sent lines keep sent.
        notifyListeners();
        continue;
      }
      for (final l in lines) {
        l.sent = true;
      }
      final order = _orderFromDto(dto);
      _upsertLocalOrder(order);
      last = order;
    }
    if (last == null) return null;

    // The waiter sent this order himself — the table is occupied, not waiting.
    table.status = TableStatus.occupied;
    table.currentOrderId = last.id;
    _saveTables();
    HapticFeedback.mediumImpact();
    notifyListeners();
    return last;
  }

  CafeOrder _makeOrder(CafeTable table, List<CartLine> lines, FeedType feed) {
    return CafeOrder(
      // Time-based id: length-based ids collided with server ids and with
      // each other after orders were removed/re-synced.
      id: 'L${DateTime.now().millisecondsSinceEpoch}${feed.index}',
      tableId: table.id,
      items: lines,
      status: OrderStatus.cooking,
      createdAt: DateTime.now(),
      splitTo: feed,
    );
  }

  void _savePendingQueue() =>
      _box.put('pendingQueue', jsonEncode(_pendingQueue));

  void discussInChat(CafeOrder order, ChatGroup group, String comment) {
    final table = tables.firstWhereOrNull((t) => t.id == order.tableId);
    final text =
        '#discuss Заказ Стол${table?.number.toString().padLeft(2, '0') ?? '??'}:${order.items.map((e) => '${e.quantity}x${e.item.name}').join(', ')}\n\n$comment';
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
        '#forward Стол${table.number.toString().padLeft(2, '0')} ·${statusLabel(table.status)}\n\n$comment';
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

  void addSystemMessage(CafeOrder order) {
    final group = groups.firstWhereOrNull((g) => g.type == order.splitTo);
    if (group == null) return;
    messages.add(ChatMessage(
      id: _nextMessageId(),
      groupId: group.id,
      senderId: 'system',
      text:
          '#orders Новый заказ #${order.id}:${order.items.map((e) => '${e.quantity}x${e.item.name}').join(', ')}',
      tags: const ['#orders'],
      timestamp: DateTime.now(),
      kind: MessageKind.orderCard,
      refId: order.id,
    ));
    _saveMessages();
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
    _box.delete('pendingQueue');
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
    _box.delete('check_${table.id}'); // don't leak the orphaned check in Hive
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

  void createStaff(String name, UserRole role) {
    final user = AppUser('u${users.length + 1}', name, role, 'Смена активна');
    users.add(user);
    notifyListeners();
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

  void markReady(CafeOrder order) {
    final previous = order.status;
    order.status = order.status == OrderStatus.ready
        ? OrderStatus.completed
        : OrderStatus.ready;
    HapticFeedback.mediumImpact();
    notifyListeners();
    if (backendConnected) _pushOrderStatus(order, previous);
  }

  Future<void> _pushOrderStatus(CafeOrder order, OrderStatus rollback) async {
    final wire = switch (order.status) {
      OrderStatus.ready => 'ready',
      OrderStatus.completed => 'completed',
      OrderStatus.cooking => 'cooking',
      OrderStatus.accepted => 'pending',
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
  /// build-time credentials. Used by Settings → "Переподключить".
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
    backendError = 'Нет данных входа. Введите логин и пароль ниже.';
    notifyListeners();
    return false;
  }

  void _applyBootstrap(BootstrapDto data) {
    if (data.menu.isNotEmpty) {
      menu
        ..clear()
        ..addAll(data.menu.map(_menuFromDto));
      _saveMenu();
    }
    if (data.tables.isNotEmpty) {
      tables
        ..clear()
        ..addAll(data.tables.map(_tableFromDto));
      _saveTables();
    }
    orders
      ..clear()
      ..addAll(data.orders.map(_orderFromDto));
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
      case RealtimeEventType.orderUpdated:
        final dto = event.order;
        if (dto != null) _upsertOrderFromDto(dto);
        break;
      case RealtimeEventType.tableUpdated:
        _applyTableUpdate(event.table);
        break;
      case RealtimeEventType.attentionCreated:
        _applyAttention(event.attention, acked: false);
        break;
      case RealtimeEventType.attentionAcked:
        _applyAttention(event.attention, acked: true);
        break;
      case RealtimeEventType.connectionReady:
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
    table.openedAt =
        dto.openedAt == null ? null : DateTime.tryParse(dto.openedAt!);
    if (table.status == TableStatus.free) {
      table.currentOrderId = null;
      tableChecks[table.id]?.clear();
    }
    _saveTables();
    notifyListeners();
  }

  void _upsertOrderFromDto(OrderDto dto) => _upsertLocalOrder(_orderFromDto(dto));

  void _upsertLocalOrder(CafeOrder order) {
    final index = orders.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      orders[index] = order;
    } else {
      orders.add(order);
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

  /// Stop realtime + clear the token (return to local-only mode).
  Future<void> disconnectBackend() async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;
    await _realtime?.dispose();
    _realtime = null;
    backendConnected = false;
    _remoteApi.setToken(null);
    _box.delete('apiToken');
    _box.delete('apiUser');
    notifyListeners();
  }

  // --- DTO -> domain mappers -------------------------------------------------

  MenuItem _menuFromDto(MenuItemDto d) => MenuItem(
        id: d.id,
        name: d.name,
        description: d.description,
        price: d.price,
        category: d.category,
        imageUrl: d.imageUrl,
        tags: d.tags,
        prepTime: d.prepTime,
        available: d.available,
        promo: d.promo,
        composition: d.composition,
        allergens: d.allergens,
        station: d.station,
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
    if (d.openedAt != null) table.openedAt = DateTime.tryParse(d.openedAt!);
    // Carry over an unacked guest signal so the badge (and the ability to
    // "Принять" it) survives an app restart.
    table.attention = d.ack ? null : d.attention;
    table.lastSignalId = d.ack ? null : d.attentionSignalId;
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
        lockedPrice: it.price > 0 ? it.price : null,
      );
    }).toList();
    return CafeOrder(
      id: d.id,
      tableId: d.tableId,
      items: lines,
      status: _orderStatusFromName(d.status),
      // Server timestamp, not "now": otherwise every bootstrap/WS echo reset
      // the kitchen timer of an existing order back to 00:00.
      createdAt: d.createdAt == null
          ? DateTime.now()
          : (DateTime.tryParse(d.createdAt!)?.toLocal() ?? DateTime.now()),
      splitTo: d.station == 'bar' ? FeedType.bar : FeedType.kitchen,
    );
  }

  MenuItem _placeholderMenuItem(OrderItemDto it) => MenuItem(
        id: it.dishId,
        name: it.name.isEmpty ? 'Позиция' : it.name,
        description: '',
        price: it.price,
        category: it.station == 'bar' ? 'Напитки' : 'Кухня',
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
        AppUser('admin', 'Администратор', UserRole.admin, 'В системе'),
        AppUser('manager', 'Алекс Ривера', UserRole.manager, 'Онлайн'),
        AppUser('waiter', 'Елена Соколова', UserRole.waiter, 'На смене'),
        AppUser('cook', 'Марко Чен', UserRole.cook, 'На кухне'),
        AppUser('bar', 'Сара Дженкинс', UserRole.bartender, 'За баром'),
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
            name: 'Флэт уайт',
            description: 'Шёлковый эспрессо с мягким молоком.',
            price: 4.50,
            category: 'Кофе',
            imageUrl:
                'https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=400',
            tags: ['Dairy'],
            prepTime: 4,
            promo: true,
            composition: 'Эспрессо, молоко 3.2%, микропена.',
            allergens: ['Dairy'],
            station: 'bar'),
        MenuItem(
            id: 'm2',
            name: 'Круассан',
            description: 'Тёплый хрустящий круассан.',
            price: 3.80,
            category: 'Выпечка',
            imageUrl:
                'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=400',
            tags: ['Gluten'],
            prepTime: 3,
            composition: 'Мука, сливочное масло, сахар, дрожжи.',
            allergens: ['Gluten', 'Eggs']),
        MenuItem(
            id: 'm3',
            name: 'Бенедикт',
            description: 'Яйца пашот с голландским соусом.',
            price: 18.50,
            category: 'Завтраки',
            imageUrl:
                'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=400',
            tags: ['Eggs'],
            prepTime: 14,
            promo: true,
            composition: 'Яйца, бриошь, бекон, голландский соус.',
            allergens: ['Eggs', 'Gluten', 'Dairy']),
        MenuItem(
            id: 'm4',
            name: 'Авокадо тост',
            description: 'Заквасочный хлеб и авокадо.',
            price: 12.00,
            category: 'Завтраки',
            imageUrl:
                'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=400',
            tags: ['Vegan'],
            prepTime: 8,
            composition: 'Заквасочный хлеб, авокадо, семена, чили.',
            allergens: ['Gluten']),
        MenuItem(
            id: 'm5',
            name: 'Колд брю',
            description: 'Кофе холодной экстракции.',
            price: 5.20,
            category: 'Кофе',
            imageUrl:
                'https://images.unsplash.com/photo-1517701604599-bb29b565090c?w=400',
            tags: ['Vegan'],
            prepTime: 2,
            composition: 'Кофе холодной заварки 12 часов.',
            station: 'bar'),
        MenuItem(
            id: 'm6',
            name: 'Лимонад',
            description: 'Домашний лимонад с базиликом.',
            price: 4.90,
            category: 'Напитки',
            imageUrl:
                'https://images.unsplash.com/photo-1621263764928-df1444c5e859?w=400',
            tags: ['Vegan'],
            prepTime: 3,
            composition: 'Лимонный сок, сахарный сироп, базилик, газировка.',
            station: 'bar'),
      ];

  List<ChatGroup> seedGroups(List<AppUser> staff) => [
        ChatGroup('g1', 'Общий чат', null, staff.map((s) => s.id).toList(),
            pinned: true),
        ChatGroup(
            'g2',
            'Кухня',
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
            'Бар',
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
