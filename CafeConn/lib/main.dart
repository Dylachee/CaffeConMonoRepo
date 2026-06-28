import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'data/api_config.dart';
import 'data/cafe_api_client.dart';
import 'data/dtos.dart';
import 'data/realtime_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Hive.initFlutter();
  await Hive.openBox('cafeconnect');
  runApp(const CafeConnectApp());
}

class CafeConnectApp extends StatefulWidget {
  const CafeConnectApp({super.key});
  @override
  State<CafeConnectApp> createState() => _CafeConnectAppState();
}

class _CafeConnectAppState extends State<CafeConnectApp> {
  late final CafeState _cafeState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _cafeState = CafeState()..boot();
    _router = GoRouter(
      refreshListenable: _cafeState,
      initialLocation: '/tables',
      routes: [
        GoRoute(
            path: '/tables',
            builder: (_, __) => const MainShellScreen()),
        GoRoute(
            path: '/table-details',
            builder: (_, __) => const TableDetailsScreen()),
        GoRoute(
            path: '/waiter-menu',
            builder: (_, __) => const WaiterOrderScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const StaffChatScreen()),
        GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen()),
      ],
    );
  }

  @override
  void dispose() {
    _cafeState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _cafeState,
      child: Consumer<CafeState>(
        builder: (context, state, _) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'CafeConnect Staff',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: state.themeMode,
          routerConfig: _router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(state.textScale)),
            child: child!,
          ),
        ),
      ),
    );
  }
}

class AppTheme {
  // Фон и поверхности (тёплые)
  static const bg = Color(0xFFF2EFE8);
  static const card = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFFBF9F4);
  static const surfaceSunken = Color(0xFFEBE6DB);

  // Текст
  static const ink = Color(0xFF1E1B16);
  static const ink2 = Color(0x8C1E1B16);
  static const ink3 = Color(0x661E1B16);
  static const separator = Color(0xFFE7E2D8);

  // Действия
  static const cta = Color(0xFF221F1A); // Эспрессо

  // Семантика статусов
  static const success = Color(0xFF3E9C63);
  static const warning = Color(0xFFE0823A); // Зона Кухня
  static const danger = Color(0xFFD9564A);
  static const bar = Color(0xFF3C7BCF); // Зона Бар
  static const gold = Color(0xFFB98A3C);

  // Статусы столов
  static const tFree = Color(0xFFB8B1A3);
  static const tOccupied = Color(0xFF5B86B0);

  // Тени
  static const shadowCard = BoxShadow(
      color: Color(0x1F2B2418),
      blurRadius: 22,
      spreadRadius: -14,
      offset: Offset(0, 10));
  static const shadowSheet = BoxShadow(
      color: Color(0x472B2418),
      blurRadius: 60,
      spreadRadius: -20,
      offset: Offset(0, 30));

  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: cta,
        brightness: brightness,
        surface: isDark ? const Color(0xFF17150F) : bg,
      ),
      scaffoldBackgroundColor: isDark ? const Color(0xFF17150F) : bg,
    );
    return base.copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      cardColor: isDark ? const Color(0xFF201C15) : card,
      dividerColor: isDark ? const Color(0xFF2E2920) : separator,
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6),
        titleLarge: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4),
        titleMedium: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2),
        bodyLarge: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0),
        labelSmall: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            letterSpacing: 0),
      ),
    );
  }
}

// ===== TYPOGRAPHY SCALE =====
class T {
  // Screen-level titles — 30px bold espresso, matches design
  static const screenTitle = TextStyle(
      fontFamily: 'Inter', fontSize: 30, fontWeight: FontWeight.w700,
      letterSpacing: -0.6, color: AppTheme.ink);
  // Section headings inside screens
  static const sectionTitle = TextStyle(
      fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700,
      color: AppTheme.ink);
  // Secondary subtitle — ink at 50% opacity (warm, not grey)
  static TextStyle get subtitle => const TextStyle(
      fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w400,
      color: Color(0x801E1B16));

  static const h1 = TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.ink);
  static const h2 = TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink);
  static const h3 = TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.ink);

  static const body = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: AppTheme.ink);
  static const bodySemi = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink);
  static const small = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: AppTheme.ink2);
  static const smallSemi = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink2);

  static const label = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppTheme.ink2);

  // Numerals use JetBrains Mono per the design; falls back to Inter until the
  // JetBrainsMono ttf is bundled (see the commented fonts block in pubspec.yaml).
  static const price = TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['Inter'], fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink);
  static const priceSmall = TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['Inter'], fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink);
  static const timer = TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['Inter'], fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5);
}

enum UserRole { waiter, cook, bartender, manager, admin }

enum TableStatus { free, occupied, awaitingPayment, ready, late, newOrder }

enum OrderStatus { accepted, cooking, ready, completed }

enum FeedType { kitchen, bar }

enum ButtonKind { primary, secondary, ghost, dark }

enum MessageKind { text, tableCard, orderCard }

class AppUser {
  AppUser(this.id, this.name, this.role, this.status,
      {this.online = true, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();
  final String id;
  String name;
  UserRole role;
  String status;
  bool online;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.index,
        'status': status,
        'online': online,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
  static AppUser fromJson(Map<String, dynamic> j) => AppUser(
        j['id'],
        j['name'],
        UserRole.values[j['role'] as int],
        j['status'],
        online: j['online'] as bool,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
      );
}

class CafeTable {
  CafeTable(this.id, this.number, this.color, this.status, this.guestCount,
      {this.currentOrderId, this.notes = const []});
  final String id;
  final int number;
  Color color;
  TableStatus status;
  int guestCount;
  String? currentOrderId;
  List<String> notes;
  DateTime? openedAt;
  String waiterName = '—';
  // Guest attention signal: 'call' (вызов), 'bill' (счёт), 'arrived' (гость сел), or null.
  String? attention;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'colorValue': color.value,
        'status': status.index,
        'guestCount': guestCount,
        'notes': notes,
        'openedAt': openedAt?.millisecondsSinceEpoch,
        'waiterName': waiterName,
        'attention': attention,
      };
  static CafeTable fromJson(Map<String, dynamic> j) {
    final t = CafeTable(
        j['id'],
        j['number'] as int,
        Color(j['colorValue'] as int),
        TableStatus.values[j['status'] as int],
        j['guestCount'] as int,
        notes: List<String>.from(j['notes'] as List));
    if (j['openedAt'] != null)
      t.openedAt = DateTime.fromMillisecondsSinceEpoch(j['openedAt'] as int);
    t.waiterName = j['waiterName'] as String? ?? '—';
    t.attention = j['attention'] as String?;
    return t;
  }
}

class MenuItem {
  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.imageUrl,
    required this.tags,
    required this.prepTime,
    this.available = true,
    this.promo = false,
    this.composition = '',
    this.allergens = const [],
  });
  final String id;
  String name;
  String description;
  double price;
  String category;
  final String imageUrl;
  List<String> tags;
  int prepTime;
  bool available;
  bool promo;
  String composition;
  List<String> allergens;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'price': price,
        'category': category,
        'imageUrl': imageUrl,
        'tags': tags,
        'prepTime': prepTime,
        'available': available,
        'promo': promo,
        'composition': composition,
        'allergens': allergens,
      };
  static MenuItem fromJson(Map<String, dynamic> j) => MenuItem(
        id: j['id'],
        name: j['name'],
        description: j['description'],
        price: (j['price'] as num).toDouble(),
        category: j['category'],
        imageUrl: j['imageUrl'],
        tags: List<String>.from(j['tags']),
        prepTime: j['prepTime'] as int,
        available: j['available'] as bool,
        promo: j['promo'] as bool,
        composition: j['composition'],
        allergens: List<String>.from(j['allergens']),
      );
}

class CartLine {
  CartLine(
      {required this.item,
      this.quantity = 1,
      this.modifiers = '',
      this.sent = false})
      : lockedPrice = item.price;
  final MenuItem item;
  int quantity;
  final double lockedPrice;
  String modifiers;
  bool sent;
  double get total => lockedPrice * quantity;

  Map<String, dynamic> toJson() => {
        'itemId': item.id,
        'quantity': quantity,
        'modifiers': modifiers,
        'sent': sent,
        'lockedPrice': lockedPrice,
      };
}

class CafeOrder {
  CafeOrder({
    required this.id,
    required this.tableId,
    required this.items,
    required this.status,
    required this.createdAt,
    required this.splitTo,
  });
  final String id;
  final String tableId;
  final List<CartLine> items;
  OrderStatus status;
  final DateTime createdAt;
  final FeedType splitTo;
  double get total => items.fold(0.0, (sum, line) => sum + line.total);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tableId': tableId,
        'items': items.map((i) => i.toJson()).toList(),
        'status': status.index,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'splitTo': splitTo.index,
      };
  static CafeOrder fromJson(Map<String, dynamic> j, List<MenuItem> menu) =>
      CafeOrder(
        id: j['id'],
        tableId: j['tableId'],
        items: (j['items'] as List).map((e) {
          final m = e as Map<String, dynamic>;
          final item = menu.firstWhere((mi) => mi.id == m['itemId'],
              orElse: () => menu.first);
          return CartLine(
              item: item,
              quantity: m['quantity'] as int,
              modifiers: m['modifiers'] as String,
              sent: m['sent'] as bool);
        }).toList(),
        status: OrderStatus.values[j['status'] as int],
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
        splitTo: FeedType.values[j['splitTo'] as int],
      );
}

class ChatGroup {
  ChatGroup(this.id, this.name, this.type, this.members,
      {this.pinned = false, this.muted = false});
  final String id;
  String name;
  FeedType? type;
  List<String> members;
  bool pinned;
  bool muted;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.text,
    required this.tags,
    required this.timestamp,
    this.own = false,
    this.voice = false,
    this.reactions = const [],
    this.kind = MessageKind.text,
    this.refId,
  });
  final String id;
  final String groupId;
  final String senderId;
  final String text;
  final List<String> tags;
  final DateTime timestamp;
  final bool own;
  final bool voice;
  List<String> reactions;
  final MessageKind kind;
  final String? refId;
}

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
  String selectedCategory = 'Все';
  String menuSearch = '';
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
  int lateThresholdMinutes = 20;
  bool showNewOrderBanner = true;
  bool showSyncToast = true;
  bool offlineModeSimulated = false;
  String activeUserName = 'Елена Соколова';
  bool shellHideNav = false;
  void setShellNav(bool visible) { shellHideNav = !visible; notifyListeners(); }

  void setSetting<T>(String key, T value, Function(T) apply) {
    apply(value);
    _box.put(key, value);
    notifyListeners();
  }

  Timer? _retryTimer;
  Timer? _fakeRealtimeTimer;

  void refresh() => notifyListeners();

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _box.put('theme', themeMode.index);
    notifyListeners();
  }

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
                sent: m['sent'] as bool);
          }).toList();
        }
      }
    } else {
      tables
        ..clear()
        ..addAll(_api.seedTables());
      _saveTables();
    }

    // --- Chats: always re-seed (ephemeral for now) ---
    groups
      ..clear()
      ..addAll(_api.seedGroups(staff));
    messages
      ..clear()
      ..addAll(_api.seedMessages(groups));

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
    lateThresholdMinutes = _box.get('lateThreshold') as int? ?? 20;
    activeUserName = _box.get('activeUserName') as String? ?? 'Елена Соколова';
    soundEnabled = _box.get('soundEnabled') as bool? ?? true;

    _retryTimer = Timer.periodic(5.seconds, (_) => retryQueuedOrders());
    _fakeRealtimeTimer =
        Timer.periodic(12.seconds, (_) => simulateRealtimeOrder());
    currentUser = users.firstOrNull;
    notifyListeners();

    // Optional auto-connect to the hub when credentials are supplied at build
    // time:  flutter run --dart-define=API_USERNAME=.. --dart-define=API_PASSWORD=..
    // Without them the app stays in local demo mode (no behaviour change).
    const autoUser = String.fromEnvironment('API_USERNAME');
    const autoPass = String.fromEnvironment('API_PASSWORD');
    if (autoUser.isNotEmpty && autoPass.isNotEmpty) {
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
    _fakeRealtimeTimer?.cancel();
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _remoteApi.close();
    super.dispose();
  }

  List<String> get categories =>
      ['Все', ...menu.map((m) => m.category).toSet()];

  List<MenuItem> filteredMenu({String? category}) {
    final cat = category ?? selectedCategory;
    return menu.where((item) {
      final okCategory = cat == 'Все' || item.category == cat;
      final okSearch = menuSearch.isEmpty ||
          item.name.toLowerCase().contains(menuSearch.toLowerCase());
      return okCategory && okSearch;
    }).toList();
  }

  List<CartLine> tableCart(String tableId) =>
      tableChecks.putIfAbsent(tableId, () => []);

  void addToCart(MenuItem item, int quantity, String modifiers,
      {String? tableId}) {
    if (tableId == null) return;
    final lines = tableCart(tableId);
    final existing = lines.firstWhereOrNull(
        (line) => line.item.id == item.id && line.modifiers == modifiers);
    if (existing == null) {
      lines.add(CartLine(item: item, quantity: quantity, modifiers: modifiers));
    } else {
      existing.quantity = quantity;
      existing.modifiers = modifiers;
    }
    HapticFeedback.selectionClick();
    _saveTables();
    notifyListeners();
  }

  void changeQuantity(CartLine line, int delta, {String? tableId}) {
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

  Future<CafeOrder> submitOrder({String? tableId, FeedType? onlyFor}) async {
    final table = tables.firstWhere(
        (t) => t.id == (tableId ?? currentTable?.id ?? tables.first.id));
    // When connected, send to the hub; realtime echoes it back to all devices.
    if (backendConnected) return _submitOrderRemote(table, onlyFor);
    final source = tableCart(table.id);

    final toSend = source.where((l) => !l.sent).where((l) {
      if (onlyFor != null) {
        final isDrink =
            l.item.category == 'Напитки' || l.item.category == 'Кофе';
        return onlyFor == FeedType.bar ? isDrink : !isDrink;
      }
      return true;
    }).toList();

    if (toSend.isEmpty) return orders.last;

    final food = toSend
        .where((l) => l.item.category != 'Напитки' && l.item.category != 'Кофе')
        .toList();
    final drinks = toSend
        .where((l) => l.item.category == 'Напитки' || l.item.category == 'Кофе')
        .toList();

    final List<CafeOrder> newOrders = [];
    if (food.isNotEmpty) {
      newOrders.add(_makeOrder(
          table,
          food
              .map((l) => CartLine(
                  item: l.item,
                  quantity: l.quantity,
                  modifiers: l.modifiers,
                  sent: true))
              .toList(),
          FeedType.kitchen));
      for (var l in food) l.sent = true;
    }
    if (drinks.isNotEmpty) {
      newOrders.add(_makeOrder(
          table,
          drinks
              .map((l) => CartLine(
                  item: l.item,
                  quantity: l.quantity,
                  modifiers: l.modifiers,
                  sent: true))
              .toList(),
          FeedType.bar));
      for (var l in drinks) l.sent = true;
    }

    if (!online) {
      _pendingQueue
          .addAll(newOrders.map((o) => {'type': 'order', 'data': o.toJson()}));
      _box.put('pendingQueue', _pendingQueue.length);
    } else {
      orders.addAll(newOrders);
    }

    table.status = TableStatus.occupied;
    if (newOrders.isNotEmpty) {
      table.currentOrderId = newOrders.last.id;
      addSystemMessage(newOrders.last);
    }

    HapticFeedback.mediumImpact();
    _saveTables();
    notifyListeners();
    return newOrders.isNotEmpty ? newOrders.last : orders.last;
  }

  /// Online order path: create on the hub, then reflect the server order
  /// locally (idempotent by id, so the WebSocket echo won't duplicate it).
  Future<CafeOrder> _submitOrderRemote(CafeTable table, FeedType? onlyFor) async {
    final source = tableCart(table.id);
    final toSend = source.where((l) => !l.sent).where((l) {
      if (onlyFor != null) {
        final isDrink =
            l.item.category == 'Напитки' || l.item.category == 'Кофе';
        return onlyFor == FeedType.bar ? isDrink : !isDrink;
      }
      return true;
    }).toList();

    CafeOrder fallback() => orders.isNotEmpty
        ? orders.last
        : _makeOrder(table, const <CartLine>[], onlyFor ?? FeedType.kitchen);

    if (toSend.isEmpty) return fallback();

    final dto = await createRemoteOrder(tableId: table.id, lines: toSend);
    if (dto == null) {
      // Backend rejected/unreachable; leave the cart unsent and surface the error.
      notifyListeners();
      return fallback();
    }

    for (final l in toSend) {
      l.sent = true;
    }
    final order = _orderFromDto(dto);
    _upsertLocalOrder(order);
    table.status = TableStatus.newOrder;
    table.currentOrderId = order.id;
    _saveTables();
    HapticFeedback.mediumImpact();
    notifyListeners();
    return order;
  }

  CafeOrder _makeOrder(CafeTable table, List<CartLine> lines, FeedType feed) {
    return CafeOrder(
      id: (1200 + orders.length + 1).toString(),
      tableId: table.id,
      items: lines,
      status: OrderStatus.cooking,
      createdAt: DateTime.now(),
      splitTo: feed,
    );
  }

  void discussInChat(CafeOrder order, ChatGroup group, String comment) {
    final table = tables.firstWhereOrNull((t) => t.id == order.tableId);
    final text =
        '#discuss Заказ Стол${table?.number.toString().padLeft(2, '0') ?? '??'}:${order.items.map((e) => '${e.quantity}x${e.item.name}').join(', ')}\n\n$comment';
    messages.add(ChatMessage(
      id: 'm${messages.length + 1}',
      groupId: group.id,
      senderId: currentUser?.id ?? 'system',
      text: text,
      tags: const ['#discuss'],
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  void forwardTable(CafeTable table, ChatGroup group, String comment) {
    final text =
        '#forward Стол${table.number.toString().padLeft(2, '0')} ·${statusLabel(table.status)}\n\n$comment';
    messages.add(ChatMessage(
      id: 'm${messages.length + 1}',
      groupId: group.id,
      senderId: currentUser?.id ?? 'system',
      text: text,
      tags: const ['#forward'],
      timestamp: DateTime.now(),
      kind: MessageKind.tableCard,
      refId: table.id,
    ));
    notifyListeners();
  }

  void addSystemMessage(CafeOrder order) {
    final group = groups.firstWhereOrNull((g) => g.type == order.splitTo);
    if (group == null) return;
    messages.add(ChatMessage(
      id: 'm${messages.length + 1}',
      groupId: group.id,
      senderId: 'system',
      text:
          '#orders Новый заказ #${order.id}:${order.items.map((e) => '${e.quantity}x${e.item.name}').join(', ')}',
      tags: const ['#orders'],
      timestamp: DateTime.now(),
      kind: MessageKind.orderCard,
      refId: order.id,
    ));
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
        orders.add(CafeOrder.fromJson(item['data'], menu));
      }
    }
    _pendingQueue.clear();
    _box.delete('pendingQueue');
    syncSuccess.value = true;
    notifyListeners();
  }

  void simulateRealtimeOrder() {
    // Don't inject demo orders once we're on the real backend feed.
    if (backendConnected) return;
    if (!online || orders.length > 10) return;
    final table = tables[Random().nextInt(tables.length)];
    if (table.status != TableStatus.free) return;
    final item = menu[Random().nextInt(menu.length)];
    final order = _makeOrder(
        table,
        [CartLine(item: item, quantity: Random().nextInt(2) + 1)],
        item.category == 'Кофе' ? FeedType.bar : FeedType.kitchen);
    orders.add(order);
    table.status = TableStatus.newOrder;
    addSystemMessage(order);
    notifyListeners();
  }

  void closeTable(CafeTable table) {
    final previous = table.status;
    table.status = TableStatus.free;
    table.currentOrderId = null;
    table.guestCount = 0;
    table.attention = null;
    tableChecks[table.id]?.clear();
    _saveTables();
    notifyListeners();
    if (backendConnected) _pushTableStatus(table, 'free', previous);
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
    final id = 't${tables.length + 1}';
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
    _saveTables();
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
      id: 'm${messages.length + 1}',
      groupId: currentGroup!.id,
      senderId: currentUser?.id ?? 'me',
      text: text,
      tags: tags,
      timestamp: DateTime.now(),
      own: true,
      voice: voice,
    ));
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  void react(ChatMessage message, String reaction) {
    message.reactions = [...message.reactions, reaction];
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

  /// Re-run the connection using stored or build-time credentials.
  /// Used by Settings → "Переподключить".
  Future<bool> reconnect() async {
    final user = _lastUser ?? const String.fromEnvironment('API_USERNAME');
    final pass = _lastPass ?? const String.fromEnvironment('API_PASSWORD');
    if (user.isEmpty || pass.isEmpty) {
      backendError =
          'Нет данных входа. Запустите с --dart-define=API_USERNAME/API_PASSWORD.';
      notifyListeners();
      return false;
    }
    return connectBackend(username: user, password: pass);
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

  void _upsertOrderFromDto(OrderDto dto) => _upsertLocalOrder(_orderFromDto(dto));

  void _upsertLocalOrder(CafeOrder order) {
    final index = orders.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      orders[index] = order;
    } else {
      orders.add(order);
    }
    final table = tables.firstWhereOrNull((t) => t.id == order.tableId);
    if (table != null && table.status == TableStatus.free) {
      table.status = TableStatus.newOrder;
    }
    notifyListeners();
  }

  /// Apply a guest attention signal to the matching table tile.
  void _applyAttention(AttentionDto? signal, {required bool acked}) {
    if (signal == null) return;
    final table = tables.firstWhereOrNull((t) => t.id == signal.tableId);
    if (table == null) return;
    if (acked) {
      table.attention = null;
    } else {
      table.attention = switch (signal.signalType) {
        'call_waiter' => 'call',
        'bill_request' => 'bill',
        'arrived' => 'arrived',
        _ => null,
      };
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
      );
    }).toList();
    return CafeOrder(
      id: d.id,
      tableId: d.tableId,
      items: lines,
      status: _orderStatusFromName(d.status),
      createdAt: DateTime.now(),
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
      );

  TableStatus _tableStatusFromName(String name) {
    switch (name) {
      case 'occupied':
        return TableStatus.occupied;
      case 'awaitingPayment':
        return TableStatus.awaitingPayment;
      case 'ready':
        return TableStatus.ready;
      case 'late':
        return TableStatus.late;
      case 'newOrder':
        return TableStatus.newOrder;
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

  List<CafeTable> seedTables() => List.generate(12, (i) {
        final statuses = [
          TableStatus.free,
          TableStatus.occupied,
          TableStatus.awaitingPayment,
          TableStatus.ready,
          TableStatus.late
        ];
        final status = statuses[i % statuses.length];
        return CafeTable('t${i + 1}', i + 1, AppTheme.cta, status,
            status == TableStatus.free ? 0 : (i % 4) + 1,
            notes: i % 3 == 0 ? ['Аллергия на орехи', 'VIP'] : []);
      });

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
            allergens: ['Dairy']),
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
            composition: 'Кофе холодной заварки 12 часов.'),
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
            composition: 'Лимонный сок, сахарный сироп, базилик, газировка.'),
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

  List<ChatMessage> seedMessages(List<ChatGroup> groups) => [
        ChatMessage(
            id: 'm1',
            groupId: groups[0].id,
            senderId: 'waiter',
            text: '#orders Стол 04 сделал заказ, проверяю напитки.',
            tags: ['#orders'],
            timestamp: DateTime.now().subtract(Duration(minutes: 22))),
        ChatMessage(
            id: 'm2',
            groupId: groups[1].id,
            senderId: 'cook',
            text: '#kitchen Бенедикт будет готов через минуту.',
            tags: ['#kitchen'],
            timestamp: DateTime.now().subtract(Duration(minutes: 11))),
      ];
}

// ================= COMPONENT WIDGETS =================

class AppButton extends StatefulWidget {
  const AppButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.kind = ButtonKind.primary,
      this.loading = false,
      this.color});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonKind kind;
  final bool loading;
  final Color? color;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool down = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.kind == ButtonKind.primary;
    final dark = widget.kind == ButtonKind.dark;
    final ghost = widget.kind == ButtonKind.ghost;

    final bg = widget.color ??
        (primary
            ? AppTheme.cta
            : dark
                ? AppTheme.ink
                : ghost
                    ? Colors.transparent
                    : AppTheme.surfaceAlt);
    final fg = primary || dark ? Colors.white : AppTheme.ink;

    return GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapCancel: () => setState(() => down = false),
      onTapUp: (_) => setState(() => down = false),
      onTap: widget.onPressed == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onPressed!();
            },
      child: AnimatedScale(
        duration: 200.ms,
        curve: Curves.elasticOut,
        scale: down ? .97 : 1,
        child: AnimatedContainer(
          duration: 200.ms,
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: ghost
                    ? Colors.transparent
                    : (primary || dark ? bg : AppTheme.separator)),
            boxShadow: primary && !down
                ? [
                    const BoxShadow(
                        color: Color(0x1F2B2418),
                        blurRadius: 22,
                        spreadRadius: -14,
                        offset: Offset(0, 10))
                  ]
                : null,
          ),
          child: widget.loading
              ? const CupertinoActivityIndicator(color: Colors.white)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: fg, size: 19),
                      const SizedBox(width: 8)
                    ],
                    Flexible(
                        child: Text(widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: T.bodySemi.copyWith(color: fg, fontSize: 16))),
                  ],
                ),
        ),
      ),
    );
  }
}

// ===== DESIGN-SYSTEM BUTTONS =====
// Espresso primary: dark bg, ALWAYS white label — contrast can never break.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.enabled = true,
    this.height = 52,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    return GestureDetector(
      onTap: on
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: height,
        decoration: BoxDecoration(
          color: on ? const Color(0xFF221F1A) : const Color(0xFFDCD6CB),
          borderRadius: BorderRadius.circular(15),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: const Color(0xFF221F1A).withValues(alpha: 0.30),
                      blurRadius: 22,
                      offset: const Offset(0, 8))
                ]
              : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, size: 19,
                color: on ? Colors.white : const Color(0xFF8A8275)),
            const SizedBox(width: 9),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : const Color(0xFF8A8275))),
        ]),
      ),
    );
  }
}

// Ghost button: cream bg, ink label — for "Отмена" and secondary actions.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.height = 48,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppTheme.separator),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppTheme.ink),
            const SizedBox(width: 8),
          ],
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink)),
        ]),
      ),
    );
  }
}

// Danger button: red bg, white label — for destructive actions.
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.height = 48,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.danger,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ]),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap,
      this.index = 0,
      this.borderColor,
      this.elevation = true,
      this.height,
      this.width});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final int index;
  final Color? borderColor;
  final bool elevation;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: height,
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? const Color(0xFFF0EBE1)),
        boxShadow: elevation
            ? [
                const BoxShadow(
                    color: Color(0x0A2B2418),
                    blurRadius: 2,
                    offset: Offset(0, 1)),
                const BoxShadow(
                    color: Color(0x1F2B2418),
                    blurRadius: 22,
                    spreadRadius: -14,
                    offset: Offset(0, 10)),
              ]
            : null,
      ),
      child: child,
    )
        .animate(delay: Duration(milliseconds: index * 40))
        .fadeIn(duration: 260.ms)
        .slideY(begin: .08, end: 0);

    if (onTap == null) return box;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap!();
      },
      child: box,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.showLabel = false});
  final TableStatus status;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 6,
              spreadRadius: 2),
        ],
      ),
    );

    Widget animatedDot = dot;
    if (status == TableStatus.newOrder || status == TableStatus.ready) {
      animatedDot = dot
          .animate(onPlay: (c) => c.repeat())
          .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.3, 1.3),
              duration: 800.ms)
          .then()
          .scale(end: const Offset(1, 1), duration: 800.ms);
    } else if (status == TableStatus.late) {
      animatedDot = dot
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fade(begin: .4, end: 1, duration: 500.ms);
    }

    if (!showLabel) return animatedDot;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animatedDot,
          const SizedBox(width: 8),
          Text(
            statusLabel(status).toUpperCase(),
            style: T.label.copyWith(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip(
      {super.key,
      required this.label,
      required this.active,
      required this.onTap,
      this.icon});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: 200.ms,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.cta : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: active ? AppTheme.cta : const Color(0xFFE7E2D8)),
          boxShadow: active
              ? [
                  const BoxShadow(
                      color: Color(0x1F2B2418),
                      blurRadius: 12,
                      offset: Offset(0, 4))
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  color: active ? Colors.white : AppTheme.ink2, size: 16),
              const SizedBox(width: 6)
            ],
            Text(
              label,
              style: T.body.copyWith(
                color: active ? Colors.white : AppTheme.ink2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoteChip extends StatelessWidget {
  const NoteChip({super.key, required this.label, this.onDelete});
  final String label;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3E6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag, color: Color(0xFFA86A24), size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: T.priceSmall.copyWith(color: const Color(0xFFA86A24))),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDelete,
              child:
                  const Icon(Icons.close, color: Color(0xFFA86A24), size: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard(
      {super.key,
      required this.label,
      required this.value,
      required this.delta,
      required this.isPositive,
      required this.color,
      this.index = 0});
  final String label;
  final String value;
  final String delta;
  final bool isPositive;
  final Color color;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      index: index,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label,
                  style: T.priceSmall.copyWith(color: AppTheme.ink2, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Text(value,
              style: T.h2.copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: isPositive ? AppTheme.success : AppTheme.danger),
              const SizedBox(width: 4),
              Text(delta,
                  style: T.smallSemi.copyWith(
                      color: isPositive ? AppTheme.success : AppTheme.danger,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper(
      {super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _step(Icons.remove, () => onChanged(max(1, value - 1))),
        SizedBox(
            width: 42,
            child: Center(
                child: Text('$value',
                    style: Theme.of(context).textTheme.titleMedium))),
        _step(Icons.add, () => onChanged(value + 1)),
      ],
    );
  }

  Widget _step(IconData icon, VoidCallback action) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        action();
      },
      child: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
              color: AppTheme.separator, shape: BoxShape.circle),
          child: Icon(icon, size: 18)),
    );
  }
}

class MenuImage extends StatelessWidget {
  const MenuImage(this.url,
      {super.key, this.radius = 16, this.aspectRatio = 1});
  final String url;
  final double radius;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => const ShimmerBox(),
          fadeInDuration: 300.ms,
          errorWidget: (_, __, ___) => Container(
              color: AppTheme.separator, child: const Icon(Icons.local_cafe)),
        ),
      ),
    );
  }
}

class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(color: AppTheme.separator)
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 900.ms, color: Colors.white70);
  }
}

class MenuGridItem extends StatelessWidget {
  const MenuGridItem(
      {super.key,
      required this.item,
      required this.onTap,
      this.index = 0,
      this.trailing});
  final MenuItem item;
  final VoidCallback onTap;
  final int index;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      index: index,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MenuImage(item.imageUrl),
          const SizedBox(height: 10),
          Text(item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.bodySemi.copyWith(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                  child: Text(item.price.rub,
                      style: T.price.copyWith(color: AppTheme.cta))),
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

// ================= NAVIGATION & SCAFFOLD =================

class AppScaffold extends StatelessWidget {
  const AppScaffold(
      {super.key,
      required this.child,
      this.bottomNav,
      this.floatingActionButton});
  final Widget child;
  final Widget? bottomNav;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Scaffold(
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNav,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: child,
            ),
            if (!state.online && !state.noConnectionDismissed)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text('Нет сети · заказы сохранятся локально',
                            style: T.bodySemi.copyWith(color: Colors.white))),
                    IconButton(
                        onPressed: () {
                          state.noConnectionDismissed = true;
                          state.refresh();
                        },
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 20)),
                  ]),
                ).animate().slideY(
                    begin: -1.2,
                    end: 0,
                    duration: 400.ms,
                    curve: Curves.easeOutQuart),
              ),
          ],
        ),
      ),
    );
  }
}

class StaffBottomNav extends StatelessWidget {
  const StaffBottomNav({super.key, required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    final items = [
      (label: 'Столы', icon: Icons.table_bar, path: '/tables'),
      (label: 'Заказы', icon: Icons.assignment, path: '/orders'),
      (label: 'Меню', icon: Icons.restaurant_menu, path: '/menu-staff'),
      (label: 'Чаты', icon: Icons.chat_bubble, path: '/chats'),
      (label: 'Панель', icon: Icons.analytics, path: '/panel'),
    ];

    int selected = items.indexWhere((e) => e.path == current);

    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            indicatorColor: Colors.transparent,
            selectedIndex: max(0, selected),
            onDestinationSelected: (i) => context.go(items[i].path),
            destinations: items.map((e) {
              final active = items.indexOf(e) == selected;
              return NavigationDestination(
                icon: Icon(
                  e.icon,
                  color: active ? AppTheme.ink : const Color(0xFFA8A091),
                ),
                label: e.label,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ================= SCREENS =================

// ===== MAIN SHELL (PageView tabs + swipe navigation) =====

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});
  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  static const _labels = ['Столы', 'Заказы', 'Меню', 'Чаты', 'Панель'];
  static const _icons = [
    Icons.table_bar,
    Icons.assignment,
    Icons.restaurant_menu,
    Icons.chat_bubble,
    Icons.analytics,
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: const [
          WaiterTableGridScreen(),
          UnifiedOrderFeedScreen(),
          StaffMenuScreen(),
          StaffChatListScreen(),
          StaffPanelScreen(),
        ],
      ),
      bottomNavigationBar: state.shellHideNav
          ? null
          : _ShellBottomNav(
              selectedIndex: _currentIndex,
              onTap: (i) {
                setState(() => _currentIndex = i);
                _pageController.animateToPage(i,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut);
              },
              labels: _labels,
              icons: _icons,
            ),
    );
  }
}

class _ShellBottomNav extends StatelessWidget {
  const _ShellBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.labels,
    required this.icons,
  });
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<String> labels;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .scaffoldBackgroundColor
            .withValues(alpha: 0.92),
        border:
            Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            indicatorColor: Colors.transparent,
            selectedIndex: selectedIndex,
            onDestinationSelected: onTap,
            destinations: List.generate(labels.length, (i) {
              final active = i == selectedIndex;
              return NavigationDestination(
                icon: Icon(icons[i],
                    color: active
                        ? AppTheme.ink
                        : const Color(0xFFA8A091)),
                label: labels[i],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class WaiterTableGridScreen extends StatefulWidget {
  const WaiterTableGridScreen({super.key});
  @override
  State<WaiterTableGridScreen> createState() => _WaiterTableGridScreenState();
}

class _WaiterTableGridScreenState extends State<WaiterTableGridScreen> {
  TableStatus? filter;
  String search = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final filtered = state.tables.where((t) {
      final okFilter = filter == null || t.status == filter;
      final okSearch = search.isEmpty || t.number.toString().contains(search);
      return okFilter && okSearch;
    }).toList();

    return AppScaffold(
      bottomNav: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Header(
            title: 'Столы',
            subtitle:
                'Зал 1 · ${state.tables.where((t) => t.status != TableStatus.free).length} активных · ${state.tables.where((t) => t.status == TableStatus.free).length} свободно',
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [AppTheme.shadowCard]),
                  child: const Icon(Icons.add, color: AppTheme.cta),
                ),
                onPressed: () => _showTableForm(context),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [AppTheme.shadowCard]),
                  child: const Icon(Icons.filter_list, color: AppTheme.ink),
                ),
                onPressed: () => _showStatusPicker(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: const InputDecoration(
                hintText: 'Поиск стола...',
                prefixIcon: Icon(Icons.search, color: AppTheme.ink3),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                CategoryChip(
                    label: 'Все',
                    active: filter == null,
                    onTap: () => setState(() => filter = null)),
                ...TableStatus.values.map((s) => CategoryChip(
                      label: statusLabel(s),
                      active: filter == s,
                      onTap: () => setState(() => filter = s),
                      icon: Icons.circle,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    icon: Icons.table_restaurant_outlined,
                    title: 'Ничего не найдено',
                    sub: 'Нет столов с таким фильтром или номером')
                : RefreshIndicator(
                    color: AppTheme.cta,
                    onRefresh: () async => context.read<CafeState>().refresh(),
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: state.tablesPerRow,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.85),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final table = filtered[i];
                        return TableCard(
                          table: table,
                          index: i,
                          onTap: () {
                            state.currentTable = table;
                            GoRouter.of(context).push('/table-details');
                          },
                          onLongPress: () {
                            _showQuickCheck(context, table);
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showTableForm(BuildContext context, {CafeTable? table}) {
    final numController =
        TextEditingController(text: table?.number.toString() ?? '');
    Color selectedColor = table?.color ?? AppTheme.cta;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(table == null ? 'Новый стол' : 'Редактировать стол',
                    style: T.h1.copyWith(fontSize: 22)),
                const SizedBox(height: 20),
                AppTextField(
                    controller: numController,
                    label: 'Номер стола',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 24),
                const Text('ЦВЕТ МЕТКИ',
                    style: T.label),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Colors.black,
                      Colors.brown,
                      Colors.blueGrey,
                      Colors.deepPurple,
                      Colors.indigo,
                      Colors.blue,
                      Colors.teal,
                      Colors.green,
                      Colors.orange,
                      Colors.red
                    ]
                        .map((c) => GestureDetector(
                              onTap: () =>
                                  setModalState(() => selectedColor = c),
                              child: Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: selectedColor == c
                                        ? Border.all(
                                            color: AppTheme.ink, width: 3)
                                        : null),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 32),
                AppButton(
                  label: table == null ? 'Добавить' : 'Сохранить',
                  onPressed: () {
                    final num = int.tryParse(numController.text);
                    if (num != null) {
                      if (table == null) {
                        context.read<CafeState>().addTable(num, selectedColor);
                      } else {
                        context
                            .read<CafeState>()
                            .editTable(table, num, selectedColor);
                      }
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showStatusPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Фильтр по статусу',
                style: T.h2.copyWith(fontSize: 20)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                AppButton(
                    label: 'Все столы',
                    kind: ButtonKind.secondary,
                    onPressed: () {
                      setState(() => filter = null);
                      Navigator.pop(context);
                    }),
                ...TableStatus.values.map((s) => AppButton(
                      label: statusLabel(s),
                      kind: ButtonKind.secondary,
                      onPressed: () {
                        setState(() => filter = s);
                        Navigator.pop(context);
                      },
                    )),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class TableCard extends StatefulWidget {
  const TableCard(
      {super.key,
      required this.table,
      required this.onTap,
      required this.onLongPress,
      this.index = 0});
  final CafeTable table;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final int index;

  @override
  State<TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<TableCard> {
  Timer? _holdTimer;
  bool _held = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final color = statusColor(widget.table.status);
    final isLate = widget.table.status == TableStatus.late;

    return GestureDetector(
      onTapDown: (_) {
        _held = false;
        _holdTimer = Timer(const Duration(milliseconds: 380), () {
          _held = true;
          HapticFeedback.mediumImpact();
          widget.onLongPress();
        });
      },
      onTapUp: (_) {
        _holdTimer?.cancel();
        if (!_held) {
          HapticFeedback.lightImpact();
          widget.onTap();
        }
      },
      onTapCancel: () {
        _holdTimer?.cancel();
        _held = false;
      },
      child: AppCard(
        index: widget.index,
        padding: const EdgeInsets.all(12),
        borderColor: isLate
            ? AppTheme.danger
            : (widget.table.attention != null
                ? attentionColor(widget.table.attention!)
                : null),
        child: Stack(
          children: [
            Positioned(
                top: 0,
                left: 0,
                child: Text('#${widget.table.number}',
                    style: T.label.copyWith(color: AppTheme.ink3, fontSize: 10))),
            Positioned(top: 0, right: 0, child: StatusBadge(widget.table.status)),
            if (widget.table.attention != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(child: _AttentionPill(widget.table.attention!)),
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${widget.table.number}',
                      style: T.h1.copyWith(fontSize: 32)),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(statusLabel(widget.table.status),
                        style: T.label.copyWith(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  widget.table.status == TableStatus.free
                      ? 'свободен'
                      : state
                          .tableCart(widget.table.id)
                          .fold(0.0, (s, l) => s + l.total)
                          .rub,
                  style: T.label.copyWith(color: AppTheme.ink2),
                ),
              ),
            ),
          ],
        ),
      )
          .animate(onPlay: isLate ? (c) => c.repeat(reverse: true) : null)
          .shimmer(duration: 2.seconds, color: Colors.white24),
    );
  }
}

class _AttentionPill extends StatelessWidget {
  const _AttentionPill(this.attention);
  final String attention;

  @override
  Widget build(BuildContext context) {
    final color = attentionColor(attention);
    final (label, icon) = switch (attention) {
      'call' => ('Зовут', Icons.pan_tool_rounded),
      'bill' => ('Счёт', Icons.receipt_long_rounded),
      'arrived' => ('Гость', Icons.chair_rounded),
      _ => ('Сигнал', Icons.notifications_active_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 600.ms)
        .scaleXY(begin: 0.94, end: 1.0, duration: 700.ms);
  }
}

void _showQuickCheck(BuildContext context, CafeTable table) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x8C0D0B08),
    transitionDuration: 300.ms,
    pageBuilder: (_, __, ___) => QuickCheckOverlay(table: table),
    transitionBuilder: (context, anim, __, child) => BackdropFilter(
      filter:
          ImageFilter.blur(sigmaX: 14 * anim.value, sigmaY: 14 * anim.value),
      child: ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
    ),
  );
}

class QuickCheckOverlay extends StatelessWidget {
  const QuickCheckOverlay({super.key, required this.table});
  final CafeTable table;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final items = state.tableCart(table.id);
    final total = items.fold(0.0, (s, l) => s + l.total);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [AppTheme.shadowSheet],
                ),
                child: Column(
                  children: [
                    Container(
                        height: 6,
                        decoration: BoxDecoration(
                            color: statusColor(table.status),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24)))),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Стол ${table.number}',
                                  style: T.screenTitle),
                              const Spacer(),
                              StatusBadge(table.status, showLabel: true),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('Открыт 14:05 · Елена',
                              style: T.priceSmall),
                          const Divider(height: 32),
                          if (items.isEmpty)
                            const Center(
                                child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 32),
                                    child: Text('Чек пуст',
                                        style: T.body)))
                          else
                            ...items.map((l) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Text('${l.quantity}×',
                                          style: T.timer.copyWith(color: AppTheme.ink2)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Text(l.item.name,
                                              style: T.body)),
                                      Text(l.total.rub,
                                          style: T.timer),
                                    ],
                                  ),
                                )),
                          const Divider(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ИТОГО',
                                  style: T.h2),
                              Text(total.rub,
                                  style: T.h2.copyWith(color: AppTheme.cta)),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                  child: GhostButton(
                                      label: 'Переслать',
                                      icon: Icons.forward,
                                      onTap: () =>
                                          _showForwardSheet(context, table))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: PrimaryButton(
                                      label: 'Открыть',
                                      icon: Icons.table_restaurant,
                                      onTap: () {
                                        Navigator.pop(context);
                                        state.currentTable = table;
                                        GoRouter.of(context)
                                            .push('/table-details');
                                      })),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('Нажмите на фон, чтобы закрыть',
                  style: T.priceSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class TableDetailsScreen extends StatefulWidget {
  const TableDetailsScreen({super.key});
  @override
  State<TableDetailsScreen> createState() => _TableDetailsScreenState();
}

class _TableDetailsScreenState extends State<TableDetailsScreen> {
  final noteController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final table = state.currentTable ?? state.tables.first;
    final lines = state.tableCart(table.id);
    final total = lines.fold(0.0, (sum, l) => sum + l.total);

    return AppScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back, color: AppTheme.ink)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Стол ${table.number}',
                        style: T.screenTitle),
                    Text('Открыт 14:05 · Елена',
                        style: T.subtitle),
                  ],
                ),
              ),
              StatusBadge(table.status, showLabel: true),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                const SectionTitle('Заказ'),
                if (lines.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long,
                              size: 48, color: AppTheme.separator),
                          const SizedBox(height: 16),
                          const Text('Чек пуст',
                              style: T.bodySemi),
                          const SizedBox(height: 16),
                          AppButton(
                              label: 'Добавить блюдо',
                              kind: ButtonKind.secondary,
                              onPressed: () =>
                                  GoRouter.of(context).push('/waiter-menu')),
                        ],
                      ),
                    ),
                  )
                else
                  ...lines.map((l) => Dismissible(
                        key: ValueKey(l.hashCode),
                        onDismissed: (_) =>
                            state.deleteLine(l, tableId: table.id),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Text('${l.quantity}×',
                                  style: T.timer.copyWith(color: AppTheme.ink2)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.item.name,
                                        style: T.bodySemi),
                                    if (l.sent)
                                      Text(
                                          l.item.category == 'Напитки' ||
                                                  l.item.category == 'Кофе'
                                              ? 'В баре ✓'
                                              : 'На кухне ✓',
                                          style: T.label.copyWith(
                                              color: l.item.category ==
                                                          'Напитки' ||
                                                      l.item.category == 'Кофе'
                                                  ? AppTheme.bar
                                                  : AppTheme.warning,
                                              fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                              Text(l.total.rub,
                                  style: T.timer),
                            ],
                          ),
                        ),
                      )),
                if (lines.isNotEmpty) ...[
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ИТОГО',
                          style: T.h2),
                      Text(total.rub,
                          style: T.h2.copyWith(color: AppTheme.cta)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                      label: 'Очистить стол',
                      icon: Icons.cleaning_services,
                      kind: ButtonKind.ghost,
                      color: AppTheme.danger,
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppTheme.card,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            title: Text(
                              'Очистить стол ${table.number}?',
                              style: T.h2,
                            ),
                            content: const Text(
                              'Заказ будет удалён. Убедитесь, что оплата прошла в кассе.',
                              style: T.body,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Отмена'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.danger,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Да, очистить',
                                    style: T.bodySemi),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && context.mounted) {
                          state.closeTable(table);
                          context.pop();
                        }
                      }),
                  const SizedBox(height: 8),
                  AppButton(
                      label: 'Сдача / Оплата',
                      icon: Icons.calculate,
                      kind: ButtonKind.ghost,
                      onPressed: () => _showChangeCalculator(context, total)),
                  const SizedBox(height: 8),
                  AppButton(
                      label: 'Добавить в заказ',
                      icon: Icons.add,
                      kind: ButtonKind.secondary,
                      onPressed: () =>
                          GoRouter.of(context).push('/waiter-menu')),
                ],
                const SizedBox(height: 32),
                const SectionTitle('Заметки'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...table.notes.asMap().entries.map((e) => NoteChip(
                        label: e.value,
                        onDelete: () => state.removeNote(table, e.key))),
                    GestureDetector(
                      onTap: () => _showAddNote(context, table),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.separator),
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add, size: 14, color: AppTheme.ink2),
                              const SizedBox(width: 4),
                              Text('Добавить',
                                  style: T.priceSmall.copyWith(color: AppTheme.ink2))
                            ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const SectionTitle('Статус стола'),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: TableStatus.values
                        .map((s) => CategoryChip(
                              label: statusLabel(s),
                              active: table.status == s,
                              onTap: () {
                                table.status = s;
                                state.refresh();
                              },
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
          BlurBar(
            child: Row(
              children: [
                Expanded(
                    child: AppButton(
                        label: 'На кухню',
                        icon: Icons.restaurant,
                        color: AppTheme.warning,
                        onPressed: () {
                          state.submitOrder(
                              tableId: table.id, onlyFor: FeedType.kitchen);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Отправлено на кухню')));
                        })),
                const SizedBox(width: 12),
                Expanded(
                    child: AppButton(
                        label: 'В бар',
                        icon: Icons.local_bar,
                        color: AppTheme.bar,
                        onPressed: () {
                          state.submitOrder(
                              tableId: table.id, onlyFor: FeedType.bar);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Отправлено в бар')));
                        })),
                const SizedBox(width: 12),
                AppButton(
                    label: '',
                    icon: Icons.send,
                    kind: ButtonKind.secondary,
                    onPressed: () => _showForwardSheet(context, table)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddNote(BuildContext context, CafeTable table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Новая заметка',
                  style: T.h2),
              const SizedBox(height: 16),
              AppTextField(
                  controller: noteController,
                  label: 'Текст заметки',
                  hint: 'Аллергия, ДР, VIP...'),
              const SizedBox(height: 20),
              AppButton(
                  label: 'Добавить',
                  onPressed: () {
                    if (noteController.text.isNotEmpty) {
                      context
                          .read<CafeState>()
                          .addNote(table, noteController.text);
                      noteController.clear();
                    }
                    Navigator.pop(context);
                  }),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangeCalculator(BuildContext context, double total) {
    final cashController = TextEditingController();
    double change = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Калькулятор сдачи',
                    style: T.h1.copyWith(fontSize: 22)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('К оплате:',
                        style: T.bodySemi.copyWith(fontSize: 16)),
                    Text(total.rub,
                        style: T.h2.copyWith(color: AppTheme.cta)),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: cashController,
                  label: 'Получено наличных',
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final cash = double.tryParse(v) ?? 0;
                    setModalState(() => change = max(0, cash - total));
                  },
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceSunken,
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('СДАЧА:',
                          style: T.label.copyWith(
                              fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      Text(change.rub,
                          style: T.h1.copyWith(
                              fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.success)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AppButton(
                    label: 'Готово', onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WaiterOrderScreen extends StatefulWidget {
  const WaiterOrderScreen({super.key});
  @override
  State<WaiterOrderScreen> createState() => _WaiterOrderScreenState();
}

class _WaiterOrderScreenState extends State<WaiterOrderScreen> {
  final Map<MenuItem, int> _selQty = {};
  bool _selMode = false;

  void _enterSel(MenuItem item) =>
      setState(() { _selMode = true; _selQty[item] = 1; });

  void _toggleItem(MenuItem item) => setState(() {
        if (_selQty.containsKey(item)) {
          _selQty.remove(item);
          if (_selQty.isEmpty) _selMode = false;
        } else {
          _selQty[item] = 1;
        }
      });

  void _exitSel() => setState(() { _selMode = false; _selQty.clear(); });

  void _openPrecheck(BuildContext context, String tableId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrecheckSheet(
        selectionQty: Map.from(_selQty),
        fixedTableId: tableId,
        onConfirmed: () => setState(() { _selMode = false; _selQty.clear(); }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final table = state.currentTable ?? state.tables.first;
    final items = state.filteredMenu();
    final total = _selQty.entries.fold(0.0, (s, e) => s + e.key.price * e.value);

    return AppScaffold(
      child: Stack(children: [
        Column(children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              IconButton(
                onPressed: _selMode ? _exitSel : () => context.pop(),
                icon: Icon(_selMode ? Icons.close : Icons.arrow_back,
                    color: AppTheme.ink),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_selMode ? 'Выбрано: ${_selQty.length}' : 'Стол ${table.number}',
                      style: T.screenTitle),
                  Text(_selMode ? total.rub : 'Добавить в заказ',
                      style: T.subtitle),
                ]),
              ),
            ]),
          ),
          _StaffMenuChips(),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.only(top: 8, bottom: _selMode ? 100 : 40),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62),
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                final qty = _selQty[item];
                return _SelectableMenuCard(
                  item: item,
                  isSelected: qty != null,
                  qty: qty ?? 1,
                  selectionMode: _selMode,
                  onTap: () => _selMode ? _toggleItem(item) : showDishDetails(ctx, item, tableId: table.id),
                  onLongPress: () => _enterSel(item),
                  onQtyChanged: (v) => setState(() => _selQty[item] = v),
                );
              },
            ),
          ),
        ]),
        if (_selMode && _selQty.isNotEmpty)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _SelectionBar(
              count: _selQty.length,
              total: total,
              onCancel: _exitSel,
              onNext: () => _openPrecheck(context, table.id),
            ),
          ),
      ]),
    );
  }
}

class UnifiedOrderFeedScreen extends StatefulWidget {
  const UnifiedOrderFeedScreen({super.key});
  @override
  State<UnifiedOrderFeedScreen> createState() => _UnifiedOrderFeedScreenState();
}

class _UnifiedOrderFeedScreenState extends State<UnifiedOrderFeedScreen> {
  // 0 = kitchen, 1 = bar — tap-only, no swipe (avoids conflict with main PageView)
  int _zone = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final kitchenOrders = state.orders
        .where((o) =>
            o.splitTo == FeedType.kitchen && o.status != OrderStatus.completed)
        .toList();
    final barOrders = state.orders
        .where((o) =>
            o.splitTo == FeedType.bar && o.status != OrderStatus.completed)
        .toList();

    return AppScaffold(
      bottomNav: null,
      child: Column(
        children: [
          Header(
              title: 'Заказы',
              subtitle: '${kitchenOrders.length + barOrders.length} активных'),
          // Tap-only segmented control — no swipe widget, no gesture conflict
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: AppTheme.surfaceSunken,
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              _ZoneTab(
                label: 'КУХНЯ',
                count: kitchenOrders.length,
                icon: Icons.restaurant,
                iconColor: AppTheme.warning,
                selected: _zone == 0,
                onTap: () => setState(() => _zone = 0),
              ),
              _ZoneTab(
                label: 'БАР',
                count: barOrders.length,
                icon: Icons.local_bar,
                iconColor: AppTheme.bar,
                selected: _zone == 1,
                onTap: () => setState(() => _zone = 1),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: IndexedStack(
              index: _zone,
              children: [
                kitchenOrders.isEmpty
                    ? const _EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'Всё готово',
                        sub: 'Нет активных заказов на кухне')
                    : ListView.builder(
                        itemCount: kitchenOrders.length,
                        itemBuilder: (_, i) =>
                            OrderCard(order: kitchenOrders[i], index: i)),
                barOrders.isEmpty
                    ? const _EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'Всё готово',
                        sub: 'Нет активных заказов в баре')
                    : ListView.builder(
                        itemCount: barOrders.length,
                        itemBuilder: (_, i) =>
                            OrderCard(order: barOrders[i], index: i)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Tap-only zone tab for КУХНЯ/БАР — replaces swipeable TabBar
class _ZoneTab extends StatelessWidget {
  const _ZoneTab({
    required this.label,
    required this.count,
    required this.icon,
    required this.iconColor,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final IconData icon;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected ? const [AppTheme.shadowCard] : null),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Text('$label ($count)',
                style: T.bodySemi.copyWith(
                    color: selected ? AppTheme.ink : AppTheme.ink2,
                    fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.index = 0});
  final CafeOrder order;
  final int index;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final table = state.tables.firstWhereOrNull((t) => t.id == order.tableId);
    final age = DateTime.now().difference(order.createdAt);
    final late = age.inMinutes > 20;
    final color = late
        ? AppTheme.danger
        : age.inMinutes > 15
            ? AppTheme.warning
            : AppTheme.success;
    final zoneColor =
        order.splitTo == FeedType.kitchen ? AppTheme.warning : AppTheme.bar;

    return AppCard(
      index: index,
      padding: EdgeInsets.zero,
      borderColor: late ? AppTheme.danger : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              height: 4,
              decoration: BoxDecoration(
                  color: zoneColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: zoneColor,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('СТОЛ${table?.number ?? '??'}',
                          style: T.priceSmall.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            '#${order.id} ·${order.splitTo == FeedType.kitchen ? 'Кухня' : 'Бар'}',
                            style: T.priceSmall.copyWith(color: AppTheme.ink2))),
                    _LiveTimer(createdAt: order.createdAt, color: color),
                  ],
                ),
                const Divider(height: 24),
                ...order.items.map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${line.quantity}×',
                              style: T.price.copyWith(color: zoneColor, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(line.item.name,
                                  style: T.h3)),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: AppButton(
                            label: order.status == OrderStatus.ready
                                ? 'Завершить'
                                : 'Готово',
                            onPressed: () => state.markReady(order))),
                    const SizedBox(width: 12),
                    AppButton(
                        label: '',
                        icon: Icons.chat_bubble_outline,
                        kind: ButtonKind.secondary,
                        onPressed: () => _showDiscussModal(context, order)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(onPlay: late ? (c) => c.repeat(reverse: true) : null).tint(
        color:
            late ? AppTheme.danger.withValues(alpha: .05) : Colors.transparent,
        duration: 500.ms);
  }
}

class StaffMenuScreen extends StatefulWidget {
  const StaffMenuScreen({super.key});

  @override
  State<StaffMenuScreen> createState() => _StaffMenuScreenState();
}

class _StaffMenuScreenState extends State<StaffMenuScreen> {
  final Map<MenuItem, int> _selQty = {};
  bool _selMode = false;

  void _enterSel(MenuItem item) {
    context.read<CafeState>().setShellNav(false);
    setState(() { _selMode = true; _selQty[item] = 1; });
  }

  void _toggleItem(MenuItem item) => setState(() {
        if (_selQty.containsKey(item)) {
          _selQty.remove(item);
          if (_selQty.isEmpty) _exitSel();
        } else {
          _selQty[item] = 1;
        }
      });

  void _exitSel() {
    context.read<CafeState>().setShellNav(true);
    setState(() { _selMode = false; _selQty.clear(); });
  }

  void _openPrecheck(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrecheckSheet(
        selectionQty: Map.from(_selQty),
        fixedTableId: null,
        onConfirmed: () => setState(() { _selMode = false; _selQty.clear(); }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final items = state.filteredMenu();
    final total = _selQty.entries.fold(0.0, (s, e) => s + e.key.price * e.value);

    return AppScaffold(
      bottomNav: null,
      child: Stack(children: [
        Column(children: [
          Header(
            title: _selMode ? 'Выбрано: ${_selQty.length}' : 'Меню',
            subtitle: _selMode ? total.rub : 'Витрина для персонала',
            actions: [
              if (_selMode)
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.ink),
                  onPressed: _exitSel,
                )
              else
                IconButton(
                  icon: const Icon(Icons.select_all, color: AppTheme.ink2),
                  tooltip: 'Зажмите карточку для выбора',
                  onPressed: null,
                ),
            ],
          ),
          if (!_selMode) ...[
            AppCard(
              padding: EdgeInsets.zero,
              child: TextField(
                onChanged: (v) { state.menuSearch = v; state.refresh(); },
                decoration: const InputDecoration(
                  hintText: 'Поиск блюда...',
                  prefixIcon: Icon(Icons.search, color: AppTheme.ink3),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _StaffMenuChips(),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.only(top: 12, bottom: _selMode ? 100 : 40),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62),
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                final qty = _selQty[item];
                return _SelectableMenuCard(
                  item: item,
                  isSelected: qty != null,
                  qty: qty ?? 1,
                  selectionMode: _selMode,
                  onTap: () => _selMode ? _toggleItem(item) : _showStaffDishDetails(ctx, item),
                  onLongPress: () => _enterSel(item),
                  onQtyChanged: (v) => setState(() => _selQty[item] = v),
                );
              },
            ),
          ),
        ]),
        if (_selMode && _selQty.isNotEmpty)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _SelectionBar(
              count: _selQty.length,
              total: total,
              onCancel: _exitSel,
              onNext: () => _openPrecheck(context),
            ),
          ),
      ]),
    );
  }
}

// ===== SHARED SELECTION-MODE WIDGETS =====

class _SelectableMenuCard extends StatelessWidget {
  const _SelectableMenuCard({
    required this.item,
    required this.isSelected,
    required this.qty,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onQtyChanged,
  });
  final MenuItem item;
  final bool isSelected;
  final int qty;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<int> onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final zoneColor = (item.category == 'Напитки' || item.category == 'Кофе')
        ? AppTheme.bar
        : AppTheme.warning;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Stack(children: [
        AppCard(
          padding: const EdgeInsets.all(10),
          borderColor: isSelected ? AppTheme.bar : null,
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              MenuImage(item.imageUrl, radius: 13),
              Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: zoneColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5)))),
              Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration:
                          BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                      child: Row(children: [
                        const Icon(Icons.schedule, size: 10, color: Colors.white),
                        const SizedBox(width: 2),
                        Text('${item.prepTime}м',
                            style: T.label.copyWith(
                                color: Colors.white, fontSize: 9)),
                      ]))),
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                        color: AppTheme.bar.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(13)),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Text(item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.bodySemi),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.small),
            ],
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(item.price.rub,
                  style: T.price.copyWith(color: AppTheme.cta)),
              if (!selectionMode)
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: item.available ? AppTheme.success : AppTheme.danger,
                        shape: BoxShape.circle)),
            ]),
            if (isSelected) ...[
              const SizedBox(height: 8),
              Center(child: _CompactStepper(value: qty, onChanged: onQtyChanged)),
            ],
          ]),
        ),
        // Circle checkbox
        if (selectionMode)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.bar : Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(
                    color: isSelected ? AppTheme.bar : AppTheme.ink2, width: 1.5),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ),
      ]),
    );
  }
}

class _CompactStepper extends StatelessWidget {
  const _CompactStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(Icons.remove, () { if (value > 1) onChanged(value - 1); }),
      SizedBox(
          width: 30,
          child: Center(
              child: Text('$value',
                  style: T.bodySemi))),
      _btn(Icons.add, () => onChanged(value + 1)),
    ]);
  }

  Widget _btn(IconData icon, VoidCallback action) => GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); action(); },
        child: Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
              color: AppTheme.surfaceSunken, shape: BoxShape.circle),
          child: Icon(icon, size: 14),
        ),
      );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.onCancel,
    required this.onNext,
  });
  final int count;
  final double total;
  final VoidCallback onCancel;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.viewPaddingOf(context).bottom + 12),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [AppTheme.shadowSheet],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Выбрано: $count',
                style: T.smallSemi),
            Text(total.rub,
                style: T.h2),
          ]),
        ),
        GhostButton(
          label: 'Отмена',
          onTap: onCancel,
          height: 44,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: PrimaryButton(
            label: 'Далее →',
            height: 44,
            onTap: onNext,
          ),
        ),
      ]),
    );
  }
}

// ===== PRECHECK SHEET =====

class _PrecheckSheet extends StatefulWidget {
  const _PrecheckSheet({
    required this.selectionQty,
    required this.fixedTableId,
    this.onConfirmed,
  });
  final Map<MenuItem, int> selectionQty;
  final String? fixedTableId;
  final VoidCallback? onConfirmed;

  @override
  State<_PrecheckSheet> createState() => _PrecheckSheetState();
}

class _PrecheckSheetState extends State<_PrecheckSheet> {
  late final Map<MenuItem, int> _items;
  final Map<MenuItem, TextEditingController> _noteCtrl = {};
  final Map<MenuItem, bool> _noteExp = {};
  String? _tableId;

  @override
  void initState() {
    super.initState();
    _items = Map.from(widget.selectionQty);
    _tableId = widget.fixedTableId;
    for (final item in _items.keys) {
      _noteCtrl[item] = TextEditingController();
      _noteExp[item] = false;
    }
  }

  @override
  void dispose() {
    for (final c in _noteCtrl.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final total = _items.entries.fold(0.0, (s, e) => s + e.key.price * e.value);
    final kitchenItems = _items.entries
        .where((e) => e.key.category != 'Напитки' && e.key.category != 'Кофе')
        .toList();
    final barItems = _items.entries
        .where((e) => e.key.category == 'Напитки' || e.key.category == 'Кофе')
        .toList();
    final selectedTable = _tableId != null
        ? state.tables.firstWhereOrNull((t) => t.id == _tableId)
        : null;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.88,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppTheme.separator, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.ink),
                onPressed: () => Navigator.pop(context)),
            Expanded(
                child: Text('Новый заказ',
                    style: T.h1.copyWith(fontSize: 20))),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Table section
              if (widget.fixedTableId == null) ...[
                const Text('СТОЛ', style: T.label),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: state.tables.map((t) {
                      final active = _tableId == t.id;
                      return GestureDetector(
                        onTap: () => setState(() => _tableId = t.id),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? AppTheme.cta : AppTheme.card,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: active ? AppTheme.cta : AppTheme.separator),
                          ),
                          child: Text('Стол ${t.number}',
                              style: T.priceSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: active ? Colors.white : AppTheme.ink)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
              ] else if (selectedTable != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceSunken,
                      borderRadius: BorderRadius.circular(11)),
                  child: Row(children: [
                    const Icon(Icons.table_restaurant,
                        size: 16, color: AppTheme.ink2),
                    const SizedBox(width: 8),
                    Text('Стол ${selectedTable.number}',
                        style: T.bodySemi),
                  ]),
                ),
                const SizedBox(height: 20),
              ],

              // Items
              const Text('ПОЗИЦИИ', style: T.label),
              const SizedBox(height: 12),
              ..._items.entries.map((entry) => _PrecheckItemRow(
                    item: entry.key,
                    qty: entry.value,
                    noteController: _noteCtrl[entry.key]!,
                    expanded: _noteExp[entry.key] ?? false,
                    onQtyChanged: (v) => setState(() => _items[entry.key] = v),
                    onToggleNote: () => setState(
                        () => _noteExp[entry.key] = !(_noteExp[entry.key] ?? false)),
                    onPreset: (p) {
                      final c = _noteCtrl[entry.key]!;
                      c.text = c.text.isEmpty ? p : '${c.text}, $p';
                    },
                  )),

              // Split preview
              const Divider(height: 24),
              if (kitchenItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.restaurant, size: 16, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Text('Кухня: ${kitchenItems.length} блюд',
                        style: T.bodySemi.copyWith(color: AppTheme.warning)),
                  ]),
                ),
              if (barItems.isNotEmpty)
                Row(children: [
                  const Icon(Icons.local_bar, size: 16, color: AppTheme.bar),
                  const SizedBox(width: 8),
                  Text('Бар: ${barItems.length} напиток',
                      style: T.bodySemi.copyWith(color: AppTheme.bar)),
                ]),
              const Divider(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('ИТОГО', style: T.h2),
                Text(total.rub, style: T.h2.copyWith(color: AppTheme.cta)),
              ]),
              const SizedBox(height: 24),
            ]),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.viewPaddingOf(context).bottom + 16),
          child: PrimaryButton(
            label: 'ОТПРАВИТЬ ЗАКАЗ',
            icon: Icons.send,
            height: 52,
            enabled: _items.isNotEmpty && _tableId != null,
            onTap: _items.isNotEmpty && _tableId != null
                ? () => _confirm(context, state)
                : null,
          ),
        ),
      ]),
    );
  }

  void _confirm(BuildContext context, CafeState state) {
    final tableId = _tableId!;
    final table = state.tables.firstWhere((t) => t.id == tableId);
    final kitchenCount = _items.entries
        .where((e) => e.key.category != 'Напитки' && e.key.category != 'Кофе')
        .length;
    final barCount = _items.entries
        .where((e) => e.key.category == 'Напитки' || e.key.category == 'Кофе')
        .length;

    for (final entry in _items.entries) {
      final note = _noteCtrl[entry.key]?.text.trim() ?? '';
      state.addToCart(entry.key, entry.value, note, tableId: tableId);
    }
    state.submitOrder(tableId: tableId);

    Navigator.pop(context);
    widget.onConfirmed?.call();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Заказ на Стол ${table.number} отправлен · Кухня $kitchenCount · Бар $barCount'),
        backgroundColor: AppTheme.success,
      ));
    }
  }
}

class _PrecheckItemRow extends StatelessWidget {
  const _PrecheckItemRow({
    required this.item,
    required this.qty,
    required this.noteController,
    required this.expanded,
    required this.onQtyChanged,
    required this.onToggleNote,
    required this.onPreset,
  });
  final MenuItem item;
  final int qty;
  final TextEditingController noteController;
  final bool expanded;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onToggleNote;
  final ValueChanged<String> onPreset;

  static const _presets = [
    'Без лука',
    'Без льда',
    'Остро',
    'Навынос',
    'Без сахара',
    'Хорошо прожарить',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(item.name,
                  style: T.price)),
          Text((item.price * qty).rub,
              style: T.bodySemi.copyWith(color: AppTheme.cta)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _CompactStepper(value: qty, onChanged: onQtyChanged),
          const Spacer(),
          GestureDetector(
            onTap: onToggleNote,
            child: Text(expanded ? '− заметка' : '+ примечание',
                style: T.priceSmall.copyWith(color: AppTheme.bar)),
          ),
        ]),
        if (expanded) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _presets
                .map((p) => GestureDetector(
                      onTap: () => onPreset(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppTheme.surfaceSunken,
                            borderRadius: BorderRadius.circular(9)),
                        child: Text(p, style: T.smallSemi),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          AppTextField(controller: noteController, label: 'Примечание...'),
        ],
      ]),
    );
  }
}

// ===== END SELECTION / PRECHECK WIDGETS =====

class StaffChatListScreen extends StatelessWidget {
  const StaffChatListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final groups = [...state.groups]
      ..sort((a, b) => b.pinned.toString().compareTo(a.pinned.toString()));
    return AppScaffold(
      bottomNav: null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Header(title: 'Чаты', subtitle: 'Команда на связи'),
        Expanded(
            child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final group = groups[i];
                  final last = state.messages
                      .where((m) => m.groupId == group.id)
                      .lastOrNull;
                  final zoneColor = group.type == FeedType.kitchen
                      ? AppTheme.warning
                      : group.type == FeedType.bar
                          ? AppTheme.bar
                          : AppTheme.ink3;
                  return AppCard(
                    index: i,
                    onTap: () {
                      state.currentGroup = group;
                      GoRouter.of(context).push('/chat');
                    },
                    child: Row(children: [
                      Avatar(label: group.name, color: zoneColor),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(group.name,
                                      style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16))),
                              if (group.pinned)
                                const Icon(Icons.push_pin,
                                    size: 14, color: AppTheme.ink3)
                            ]),
                            Text(last?.text ?? 'Нет сообщений',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.priceSmall.copyWith(color: AppTheme.ink2)),
                          ])),
                      const SizedBox(width: 8),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                                last == null
                                    ? ''
                                    : '${last.timestamp.hour}:${last.timestamp.minute.toString().padLeft(2, '0')}',
                                style: T.label.copyWith(color: AppTheme.ink3)),
                            const SizedBox(height: 5),
                            if (i == 0)
                              Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                      color: AppTheme.warning,
                                      shape: BoxShape.circle),
                                  child: const Text('2',
                                      style: T.label)),
                          ]),
                    ]),
                  );
                })),
      ]),
    );
  }
}

class StaffChatScreen extends StatefulWidget {
  const StaffChatScreen({super.key});
  @override
  State<StaffChatScreen> createState() => _StaffChatScreenState();
}

class _StaffChatScreenState extends State<StaffChatScreen> {
  final input = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final group = state.currentGroup ?? state.groups.first;
    final messages =
        state.messages.where((m) => m.groupId == group.id).toList();
    final zoneColor = group.type == FeedType.kitchen
        ? AppTheme.warning
        : group.type == FeedType.bar
            ? AppTheme.bar
            : AppTheme.ink3;

    _scrollToBottom();

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AppScaffold(
      child: Column(children: [
        Row(children: [
          IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back, color: AppTheme.ink)),
          Avatar(label: group.name, color: zoneColor),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(group.name,
                    style: T.h2.copyWith(fontSize: 17)),
                const Text('8 онлайн',
                    style: T.smallSemi),
              ])),
        ]),
        Expanded(
            child: messages.isEmpty
                ? _EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Чатик пуст',
                    sub: 'Начните общение — отправьте первое сообщение')
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = messages[i];
                      if (msg.kind == MessageKind.tableCard) {
                        return ForwardedTableCard(message: msg);
                      }
                      if (msg.kind == MessageKind.orderCard) {
                        return OrderReceiptCard(message: msg);
                      }
                      final senderName = state.staff
                              .firstWhereOrNull(
                                  (u) => u.id == msg.senderId)
                              ?.name ??
                          msg.senderId;
                      return ChatBubble(
                          message: msg, senderName: senderName);
                    })),
        Padding(
          padding: EdgeInsets.only(
              bottom: keyboardInset > 0 ? keyboardInset + 8 : 8, top: 8),
          child: Row(children: [
            Expanded(
                child: AppTextField(controller: input, label: 'Сообщение...')),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final text = input.text.trim();
                if (text.isEmpty) return;
                state.sendMessage(text);
                input.clear();
                _scrollToBottom();
              },
              child: const CircleAvatar(
                  radius: 25,
                  backgroundColor: AppTheme.cta,
                  child: Icon(Icons.send, color: Colors.white, size: 20)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class StaffPanelScreen extends StatefulWidget {
  const StaffPanelScreen({super.key});
  @override
  State<StaffPanelScreen> createState() => _StaffPanelScreenState();
}

class _StaffPanelScreenState extends State<StaffPanelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      bottomNav: null,
      child: Column(
        children: [
          Header(title: 'Панель', subtitle: 'Управление системой', actions: [
            IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => GoRouter.of(context).push('/settings')),
          ]),
          Container(
            height: 38,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppTheme.cta,
              labelColor: AppTheme.ink,
              unselectedLabelColor: AppTheme.ink2,
              tabs: const [
                Tab(text: 'Обзор'),
                Tab(text: 'Команда'),
                Tab(text: 'Меню'),
                Tab(text: 'Доступ')
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _OverviewTab(),
                const TeamManagementScreen(),
                const MenuManagementScreen(),
                _AccessTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: const [
            MetricCard(
                label: 'Выручка',
                value: '1,280 \$',
                delta: '▲ 12%',
                isPositive: true,
                color: AppTheme.success),
            MetricCard(
                label: 'Средний чек',
                value: '42.50 \$',
                delta: '▼ 3%',
                isPositive: false,
                color: AppTheme.danger,
                index: 1),
            MetricCard(
                label: 'Столы',
                value: '8 / 12',
                delta: 'активны',
                isPositive: true,
                color: AppTheme.tOccupied,
                index: 2),
            MetricCard(
                label: 'Готовка',
                value: '14 мин',
                delta: '▲ 2 мин',
                isPositive: false,
                color: AppTheme.warning,
                index: 3),
          ],
        ),
        const SizedBox(height: 20),
        const SectionTitle('Выручка по часам'),
        AppCard(
          height: 160,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [30, 50, 80, 45, 90, 120, 70, 40]
                .map((h) => Container(
                    width: 20,
                    height: h.toDouble(),
                    decoration: BoxDecoration(
                        color:
                            h == 120 ? AppTheme.cta : const Color(0xFFE4D7C2),
                        borderRadius: BorderRadius.circular(4))))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class TeamManagementScreen extends StatelessWidget {
  const TeamManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return ListView(children: [
      Row(children: [
        const Expanded(child: SectionTitle('Сотрудники')),
        AppButton(
            label: 'Добавить',
            kind: ButtonKind.ghost,
            icon: Icons.person_add,
            onPressed: () => _showStaffForm(context))
      ]),
      ...state.users.map((u) => StaffMemberRow(user: u)),
    ]);
  }
}

class MenuManagementScreen extends StatelessWidget {
  const MenuManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return ListView(children: [
      Row(children: [
        const Expanded(child: SectionTitle('Позиции')),
        AppButton(
            label: 'Добавить блюдо',
            kind: ButtonKind.ghost,
            icon: Icons.add,
            onPressed: () => _showMenuForm(context)),
      ]),
      ...state.menu.map((item) => AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () => _showMenuForm(context, item: item),
            child: Row(
              children: [
                MenuImage(item.imageUrl, radius: 10, aspectRatio: 1),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(item.price.rub,
                          style: T.bodySemi.copyWith(color: AppTheme.cta)),
                    ],
                  ),
                ),
                CupertinoSwitch(
                    value: item.available,
                    activeColor: AppTheme.success,
                    onChanged: (v) => state.toggleAvailability(item)),
              ],
            ),
          )),
    ]);
  }
}

void _showMenuForm(BuildContext context, {MenuItem? item}) {
  final name = TextEditingController(text: item?.name ?? '');
  final desc = TextEditingController(text: item?.description ?? '');
  final price = TextEditingController(text: item?.price.toString() ?? '');
  final category = TextEditingController(text: item?.category ?? 'Кухня');
  final prep = TextEditingController(text: item?.prepTime.toString() ?? '10');

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item == null ? 'Новая позиция' : 'Редактировать позицию',
                  style: T.h1.copyWith(fontSize: 22)),
              const SizedBox(height: 20),
              AppTextField(controller: name, label: 'Название'),
              const SizedBox(height: 12),
              AppTextField(
                  controller: desc,
                  label: 'Описание',
                  hint: 'Состав, особенности...'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: AppTextField(
                          controller: price,
                          label: 'Цена',
                          keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: AppTextField(
                          controller: prep,
                          label: 'Время (мин)',
                          keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(controller: category, label: 'Категория'),
              const SizedBox(height: 24),
              AppButton(
                label: 'Сохранить',
                onPressed: () {
                  if (item == null) {
                    final newItem = MenuItem(
                      id: 'm${context.read<CafeState>().menu.length + 1}',
                      name: name.text,
                      description: desc.text,
                      price: double.tryParse(price.text) ?? 0.0,
                      category: category.text,
                      imageUrl:
                          'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400',
                      tags: [],
                      prepTime: int.tryParse(prep.text) ?? 10,
                    );
                    context.read<CafeState>().menu.add(newItem);
                  } else {
                    item.name = name.text;
                    item.description = desc.text;
                    item.price = double.tryParse(price.text) ?? item.price;
                    item.category = category.text;
                    item.prepTime = int.tryParse(prep.text) ?? item.prepTime;
                  }
                  context.read<CafeState>().refresh();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AccessTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SectionTitle('Права ролей'),
        _roleAccessCard('Официант', [
          ('Заказы', true),
          ('Счёт', true),
          ('Меню', true),
          ('Админка', false)
        ]),
        _roleAccessCard('Повар', [
          ('Заказы', true),
          ('Столы', false),
          ('Меню', true),
          ('Админка', false)
        ]),
      ],
    );
  }

  Widget _roleAccessCard(String title, List<(String, bool)> perms) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              children: perms
                  .map((p) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: p.$2
                              ? AppTheme.success.withValues(alpha: 0.12)
                              : AppTheme.separator,
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(p.$2 ? Icons.check_circle : Icons.circle,
                            size: 12,
                            color: p.$2 ? AppTheme.success : AppTheme.ink3),
                        const SizedBox(width: 4),
                        Text(p.$1,
                            style: T.smallSemi.copyWith(
                                color: p.$2 ? AppTheme.success : AppTheme.ink3,
                                fontWeight: FontWeight.w700))
                      ])))
                  .toList()),
        ]),
      );
}

// ================= HELPERS & UTILS =================

class Header extends StatelessWidget {
  const Header(
      {super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 16),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: T.screenTitle),
          if (subtitle != null)
            Text(subtitle!, style: T.subtitle),
        ])),
        ...actions,
      ]));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(children: [
        Expanded(child: Text(title, style: T.sectionTitle)),
        if (action != null)
          AppButton(label: 'Все', kind: ButtonKind.ghost, onPressed: action),
      ]));
}

class Avatar extends StatelessWidget {
  const Avatar(
      {super.key, required this.label, this.online = false, this.color});
  final String label;
  final bool online;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final initials = label
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part.substring(0, 1).toUpperCase())
        .take(2)
        .join();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          color: (color ?? AppTheme.cta).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14)),
      child: Center(
          child: Text(initials,
              style: T.bodySemi.copyWith(color: color ?? AppTheme.cta, fontWeight: FontWeight.w800))),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField(
      {super.key,
      required this.controller,
      required this.label,
      this.hint,
      this.obscure = false,
      this.keyboardType,
      this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: T.body.copyWith(color: AppTheme.ink),
        cursorColor: AppTheme.cta,
        decoration: InputDecoration(
          hintText: hint ?? label,
          hintStyle: T.body.copyWith(color: AppTheme.ink2),
          filled: true,
          fillColor: AppTheme.surfaceSunken,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.cta, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}

class _StaffMenuChips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: state.categories
            .map((c) => CategoryChip(
                  label: c,
                  active: state.selectedCategory == c,
                  onTap: () {
                    state.selectedCategory = c;
                    state.refresh();
                  },
                ))
            .toList(),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble(
      {super.key, required this.message, this.senderName = ''});
  final ChatMessage message;
  final String senderName;
  @override
  Widget build(BuildContext context) {
    final own = message.own;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!own && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(senderName,
                  style: T.label),
            ),
          Container(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: own ? AppTheme.cta : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [AppTheme.shadowCard]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message.text,
                  style: T.body.copyWith(color: own ? Colors.white : AppTheme.ink)),
              const SizedBox(height: 4),
              Text(
                  '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: T.label.copyWith(color: own ? Colors.white70 : AppTheme.ink3)),
            ]),
          ),
        ],
      ),
    );
  }
}

class OrderReceiptCard extends StatelessWidget {
  const OrderReceiptCard({super.key, required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final order = state.orders
        .firstWhereOrNull((o) => o.id == message.refId);
    final table = order != null
        ? state.tables.firstWhereOrNull((t) => t.id == order.tableId)
        : null;
    final isKitchen = order?.splitTo == FeedType.kitchen;
    final zoneColor = isKitchen ? AppTheme.warning : AppTheme.bar;
    final zoneLabel = isKitchen ? 'Кухня' : 'Бар';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: zoneColor, width: 4)),
          boxShadow: const [AppTheme.shadowCard],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 14),
            const SizedBox(width: 6),
            Text(
                'Новый заказ · Стол ${table?.number ?? '??'}',
                style: T.priceSmall.copyWith(color: zoneColor, fontWeight: FontWeight.w700)),
          ]),
          const Divider(height: 16),
          if (order != null)
            ...order.items.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Text('${l.quantity}×  ',
                        style: T.priceSmall.copyWith(fontWeight: FontWeight.w700)),
                    Expanded(
                        child: Text(l.item.name,
                            style: T.priceSmall)),
                    if (l.modifiers.isNotEmpty)
                      Text('(${l.modifiers})',
                          style: T.label.copyWith(color: AppTheme.ink2)),
                  ]),
                )),
          const Divider(height: 16),
          Text(
              '$zoneLabel · ${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: T.label.copyWith(color: AppTheme.ink2)),
        ]),
      ),
    );
  }
}

class ForwardedTableCard extends StatelessWidget {
  const ForwardedTableCard({super.key, required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final table = state.tables.firstWhereOrNull((t) => t.id == message.refId);
    return AppCard(
      borderColor: AppTheme.tOccupied,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.forward, size: 14, color: AppTheme.tOccupied),
          const SizedBox(width: 8),
          Text('ПЕРЕСЛАНО · Елена',
              style: T.label.copyWith(color: AppTheme.tOccupied, fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 8),
        Text('Стол${table?.number ?? '??'}',
            style: T.h2.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        Text(message.text,
            style: T.priceSmall.copyWith(color: AppTheme.ink2)),
        const Divider(height: 24),
        AppButton(
            label: 'Открыть стол',
            kind: ButtonKind.ghost,
            onPressed: () {
              if (table != null) {
                state.currentTable = table;
                GoRouter.of(context).push('/table-details');
              }
            })
      ]),
    );
  }
}

class StaffMemberRow extends StatelessWidget {
  const StaffMemberRow({super.key, required this.user});
  final AppUser user;
  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => _showStaffForm(context, user: user),
      child: Row(children: [
        Avatar(label: user.name),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.name,
              style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(roleLabel(user.role),
              style: T.priceSmall.copyWith(color: AppTheme.ink2)),
        ])),
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: user.online ? AppTheme.success : AppTheme.ink3,
                shape: BoxShape.circle)),
      ]),
    );
  }
}

void _showStaffForm(BuildContext context, {AppUser? user}) {
  final name = TextEditingController(text: user?.name ?? '');
  var role = user?.role ?? UserRole.waiter;
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
          builder: (context, set) => Container(
                decoration: const BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(user == null ? 'Новый сотрудник' : 'Редактировать',
                      style: T.h2),
                  const SizedBox(height: 20),
                  AppTextField(controller: name, label: 'Имя'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField(
                      value: role,
                      items: UserRole.values
                          .map((r) => DropdownMenuItem(
                              value: r, child: Text(roleLabel(r))))
                          .toList(),
                      onChanged: (v) => set(() => role = v!)),
                  const SizedBox(height: 20),
                  AppButton(
                      label: 'Сохранить',
                      onPressed: () {
                        if (user == null) {
                          context
                              .read<CafeState>()
                              .createStaff(name.text, role);
                        } else {
                          user.name = name.text;
                          user.role = role;
                          context.read<CafeState>().refresh();
                        }
                        Navigator.pop(context);
                      }),
                ]),
              )));
}

void _showForwardSheet(BuildContext context, CafeTable table) {
  final comment = TextEditingController();
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
            decoration: const BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Переслать',
                      style: T.h2.copyWith(fontSize: 20)),
                  const SizedBox(height: 16),
                  AppTextField(
                      controller: comment, label: 'Добавить комментарий...'),
                  const SizedBox(height: 24),
                  const Text('КУДА ОТПРАВИТЬ', style: T.label),
                  const SizedBox(height: 12),
                  ...context.read<CafeState>().groups.map((g) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(label: g.name),
                        title: Text(g.name,
                            style: T.bodySemi),
                        trailing:
                            const Icon(Icons.send_rounded, color: AppTheme.cta),
                        onTap: () {
                          context
                              .read<CafeState>()
                              .forwardTable(table, g, comment.text);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Отправлено в чат')));
                        },
                      )),
                ]),
          ));
}

void _showDiscussModal(BuildContext context, CafeOrder order) {
  final comment = TextEditingController();
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
            decoration: const BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Обсудить заказ', style: T.h2),
              const SizedBox(height: 16),
              AppTextField(controller: comment, label: 'Комментарий...'),
              const SizedBox(height: 20),
              Wrap(
                  spacing: 8,
                  children: context
                      .read<CafeState>()
                      .groups
                      .map((g) => AppButton(
                          label: g.name,
                          kind: ButtonKind.secondary,
                          onPressed: () {
                            context
                                .read<CafeState>()
                                .discussInChat(order, g, comment.text);
                            Navigator.pop(context);
                          }))
                      .toList()),
            ]),
          ));
}

void _showStaffDishDetails(BuildContext context, MenuItem item) {
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
            decoration: const BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MenuImage(item.imageUrl, radius: 16, aspectRatio: 16 / 10),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: Text(item.name,
                            style: T.h1.copyWith(fontSize: 22))),
                    Text(item.price.rub,
                        style: T.h2.copyWith(color: AppTheme.cta))
                  ]),
                  const SizedBox(height: 12),
                  Text(item.description,
                      style: T.h3.copyWith(color: AppTheme.ink2)),
                  const SizedBox(height: 20),
                  const Text('СОСТАВ', style: T.label),
                  const SizedBox(height: 4),
                  Text(item.composition, style: T.body),
                  const SizedBox(height: 20),
                  const Text('АЛЛЕРГЕНЫ', style: T.label),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      children: item.allergens.isEmpty
                          ? [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: AppTheme.success
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: const Text('Без аллергенов',
                                      style: T.smallSemi))
                            ]
                          : item.allergens
                              .map((a) => NoteChip(label: a))
                              .toList()),
                  const SizedBox(height: 32),
                  AppButton(
                      label: 'Готово', onPressed: () => Navigator.pop(context)),
                ]),
          ));
}

Future<void> showDishDetails(BuildContext context, MenuItem item,
    {String? tableId}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DishDetailSheet(item: item, tableId: tableId),
  );
}

class DishDetailSheet extends StatefulWidget {
  const DishDetailSheet({super.key, required this.item, this.tableId});
  final MenuItem item;
  final String? tableId;
  @override
  State<DishDetailSheet> createState() => _DishDetailSheetState();
}

class _DishDetailSheetState extends State<DishDetailSheet> {
  int qty = 1;
  final notes = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(widget.item.name,
                      style: T.h1.copyWith(fontSize: 20))),
              Text(widget.item.price.rub,
                  style: T.h2.copyWith(color: AppTheme.cta))
            ]),
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(
                  child: Text('Количество',
                      style: T.bodySemi)),
              QuantityStepper(
                  value: qty, onChanged: (v) => setState(() => qty = v))
            ]),
            const SizedBox(height: 16),
            AppTextField(controller: notes, label: 'Пожелания'),
            const SizedBox(height: 24),
            AppButton(
                label: 'Добавить в чек ·${(widget.item.price * qty).rub}',
                onPressed: () {
                  context.read<CafeState>().addToCart(
                      widget.item, qty, notes.text.trim(),
                      tableId: widget.tableId);
                  Navigator.pop(context);
                }),
          ]),
    );
  }
}

class _LiveTimer extends StatefulWidget {
  const _LiveTimer({required this.createdAt, required this.color});
  final DateTime createdAt;
  final Color color;
  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(1.seconds, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.createdAt);
    return Text(
        '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
        style: T.timer.copyWith(color: widget.color, fontSize: 16));
  }
}

class TypingDots extends StatelessWidget {
  const TypingDots({super.key});
  @override
  Widget build(BuildContext context) => Row(
      children: List.generate(
          3,
          (i) => Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: AppTheme.ink3, shape: BoxShape.circle))
              .animate(
                  delay: Duration(milliseconds: i * 150),
                  onPlay: (c) => c.repeat(reverse: true))
              .scale(
                  begin: const Offset(.5, .5),
                  end: const Offset(1, 1),
                  duration: 450.ms)));
}

extension DurationNum on int {
  Duration get ms => Duration(milliseconds: this);
  Duration get seconds => Duration(seconds: this);
  Duration get minutes => Duration(minutes: this);
}

extension Money on double {
  String get rub => '${toStringAsFixed(2)} \$';
}

String roleLabel(UserRole role) => switch (role) {
      UserRole.admin => 'Админ',
      UserRole.manager => 'Менеджер',
      UserRole.waiter => 'Официант',
      UserRole.cook => 'Повар',
      UserRole.bartender => 'Бармен',
    };

Color attentionColor(String attention) => switch (attention) {
      'call' => AppTheme.warning,
      'bill' => AppTheme.gold,
      'arrived' => AppTheme.bar,
      _ => AppTheme.ink2,
    };

Color statusColor(TableStatus status) => switch (status) {
      TableStatus.free => AppTheme.tFree,
      TableStatus.occupied => AppTheme.tOccupied,
      TableStatus.awaitingPayment => AppTheme.gold,
      TableStatus.ready => AppTheme.success,
      TableStatus.late => AppTheme.danger,
      TableStatus.newOrder => AppTheme.warning,
    };

String statusLabel(TableStatus status) => switch (status) {
      TableStatus.free => 'Свободен',
      TableStatus.occupied => 'Занят',
      TableStatus.awaitingPayment => 'Счёт',
      TableStatus.ready => 'Готово',
      TableStatus.late => 'Задержка',
      TableStatus.newOrder => 'Новый',
    };

class BlurBar extends StatelessWidget {
  const BlurBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withValues(alpha: .82),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(20)),
                child: child)),
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: const BackButton(),
        title: const Text('Настройки', style: T.h2),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSection('Аккаунт', [
            _SettingsRow(
                label: 'Текущий сотрудник', value: state.activeUserName),
          ]),
          _SettingsSection('Внешний вид', [
            _SettingsSegmented(
              label: 'Тема',
              options: const ['Светлая', 'Тёмная', 'Системная'],
              selected: state.themeMode.index,
              onChanged: (i) => state.setSetting(
                  'theme', i, (v) => state.themeMode = ThemeMode.values[v]),
            ),
            _SettingsSegmented(
              label: 'Размер текста',
              options: const ['Мал.', 'Норм.', 'Бол.'],
              selected: state.textScale == 0.85
                  ? 0
                  : state.textScale == 1.15
                      ? 2
                      : 1,
              onChanged: (i) {
                final scales = [0.85, 1.0, 1.15];
                state.setSetting(
                    'textScale', scales[i], (v) => state.textScale = v);
              },
            ),
          ]),
          _SettingsSection('Дисплей', [
            _SettingsSegmented(
              label: 'Столов в ряду',
              options: const ['3', '4'],
              selected: state.tablesPerRow == 3 ? 0 : 1,
              onChanged: (i) => state.setSetting('tablesPerRow', i == 0 ? 3 : 4,
                  (v) => state.tablesPerRow = v),
            ),
            _SettingsToggle(
                label: 'Подсказки жестов',
                value: state.showGestureHints,
                onChanged: (v) => state.setSetting(
                    'showGestureHints', v, (x) => state.showGestureHints = x)),
            _SettingsToggle(
                label: '24-часовой формат',
                value: state.use24hClock,
                onChanged: (v) => state.setSetting(
                    'use24hClock', v, (x) => state.use24hClock = x)),
          ]),
          _SettingsSection('Вибро и звук', [
            _SettingsToggle(
                label: 'Вибрация',
                value: state.hapticsEnabled,
                onChanged: (v) => state.setSetting(
                    'hapticsEnabled', v, (x) => state.hapticsEnabled = x)),
            _SettingsToggle(
                label: 'Звуки',
                value: state.soundEnabled,
                onChanged: (v) => state.setSetting(
                    'soundEnabled', v, (x) => state.soundEnabled = x)),
          ]),
          _SettingsSection('Соединение', [
            _SettingsRow(
                label: 'Статус',
                value: state.backendConnecting
                    ? 'Подключение…'
                    : state.backendConnected
                        ? 'Подключено'
                        : 'Локальный режим'),
            _SettingsRow(label: 'Сервер', value: ApiConfig.baseUrl),
            if (state.backendError != null)
              _SettingsRow(label: 'Последняя ошибка', value: state.backendError),
            _SettingsRow(
                label: 'Переподключить',
                trailing: state.backendConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.cta))
                    : const Icon(Icons.sync, color: AppTheme.cta),
                onTap:
                    state.backendConnecting ? null : () => state.reconnect()),
          ]),
          _SettingsSection('Данные и синхронизация', [
            _SettingsToggle(
                label: 'Симулировать офлайн (QA)',
                value: state.offlineModeSimulated,
                onChanged: (v) {
                  state.setSetting('offlineModeSimulated', v,
                      (x) => state.offlineModeSimulated = x);
                  state.online = !v;
                  state.refresh();
                }),
            _SettingsRow(
                label: 'Ожидают отправки',
                value: '${state.pendingQueueCount} действий'),
            _SettingsRow(
                label: 'Сброс к демо-данным',
                trailing: const Icon(Icons.restart_alt, color: AppTheme.danger),
                onTap: () => _confirmResetToDemo(context, state)),
          ]),
          _SettingsSection('О приложении', [
            const _SettingsRow(label: 'Версия', value: 'v0.1.0-alpha'),
          ]),
        ],
      ),
    );
  }

  void _confirmResetToDemo(BuildContext context, CafeState state) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Сброс данных'),
        content: const Text(
            'Это удалит все текущие изменения и вернет демо-данные. Продолжить?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
          TextButton(
              onPressed: () {
                state.resetToDemo();
                Navigator.pop(c);
              },
              child: const Text('Сбросить',
                  style: T.bodySemi)),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection(this.title, this.children);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(left: 12, top: 24, bottom: 8),
              child: Text(title.toUpperCase(),
                  style: T.label.copyWith(color: AppTheme.ink3))),
          AppCard(padding: EdgeInsets.zero, child: Column(children: children)),
        ],
      );
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsRow(
      {required this.label, this.value, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label, style: T.h3.copyWith(fontWeight: FontWeight.w500)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (value != null)
            Text(value!, style: T.body.copyWith(color: AppTheme.ink2)),
          if (trailing != null) trailing!,
        ]),
        onTap: onTap,
      );
}

class _SettingsToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingsToggle(
      {required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(label, style: T.h3.copyWith(fontWeight: FontWeight.w500)),
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.cta,
      );
}

class _SettingsSegmented extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  const _SettingsSegmented(
      {required this.label,
      required this.options,
      required this.selected,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: T.h3.copyWith(fontWeight: FontWeight.w500))),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                  color: AppTheme.surfaceSunken,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                  children: List.generate(
                      options.length,
                      (i) => GestureDetector(
                            onTap: () => onChanged(i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                  color: selected == i
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: selected == i
                                      ? [
                                          const BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 4)
                                        ]
                                      : null),
                              child: Text(options[i],
                                  style: T.priceSmall.copyWith(
                                      fontWeight: selected == i
                                          ? FontWeight.w600
                                          : FontWeight.w400)),
                            ),
                          ))),
            ),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _EmptyState(
      {required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppTheme.success.withValues(alpha: .3)),
            const SizedBox(height: 12),
            Text(title, style: T.h2),
            Text(sub, style: T.body.copyWith(color: AppTheme.ink2)),
          ],
        ),
      );
}
