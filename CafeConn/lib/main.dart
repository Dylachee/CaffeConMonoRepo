import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_typography.dart';
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

/// Deliberately just three states (product decision, 2026-07-02): a table is
/// either free, taken, or the guests are waiting for a waiter. Must stay in
/// sync with Table.Status on the Django side (free / occupied / waiting).
enum TableStatus { free, occupied, waiting }

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
  // Server id of the newest unacked attention signal — needed to POST the ack
  // back to the hub. Transient (not persisted): after a restart the bootstrap
  // brings fresh state anyway.
  String? lastSignalId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'colorValue': color.value,
        'status': status.name,
        'guestCount': guestCount,
        'notes': notes,
        'openedAt': openedAt?.millisecondsSinceEpoch,
        'waiterName': waiterName,
        'attention': attention,
      };

  /// Accepts both the current string format and the legacy Hive format that
  /// stored the index of the old 6-value enum (0 free, 1 occupied,
  /// 2 awaitingPayment, 3 ready, 4 late, 5 newOrder). Without this, devices
  /// with old cached data would crash on `TableStatus.values[index]`.
  static TableStatus _statusFromRaw(dynamic raw) {
    if (raw is String) {
      for (final s in TableStatus.values) {
        if (s.name == raw) return s;
      }
      return TableStatus.free;
    }
    if (raw is int) {
      switch (raw) {
        case 1: // occupied
        case 3: // ready -> guests seated, order in progress
          return TableStatus.occupied;
        case 2: // awaitingPayment
        case 4: // late
        case 5: // newOrder
          return TableStatus.waiting;
        default:
          return TableStatus.free;
      }
    }
    return TableStatus.free;
  }

  static CafeTable fromJson(Map<String, dynamic> j) {
    final t = CafeTable(
        j['id'],
        j['number'] as int,
        Color(j['colorValue'] as int),
        _statusFromRaw(j['status']),
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
    this.station = '',
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

  /// Station routing: 'kitchen' | 'bar'. The hub is the source of truth
  /// (MenuItem.station in Django); category is only a fallback for legacy
  /// Hive data and the offline seed. Guessing by category alone was the bug
  /// that sent beer to the kitchen: only 'Напитки'/'Кофе' counted as bar.
  String station;

  static const _barCategories = {
    'Напитки', 'Кофе', 'Чай', 'Бар', 'Пиво', 'Вино',
    'Коктейли', 'Алкоголь', 'Лимонады', 'Смузи',
  };

  bool get isBar =>
      station.isNotEmpty ? station == 'bar' : _barCategories.contains(category);

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
        'station': station,
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
        station: j['station'] as String? ?? '',
      );
}

class CartLine {
  CartLine(
      {required this.item,
      this.quantity = 1,
      this.modifiers = '',
      this.sent = false,
      this.ready = false,
      this.done = false,
      double? lockedPrice})
      // lockedPrice survives persistence: a menu price change must not
      // silently reprice an already-open check.
      : lockedPrice = lockedPrice ?? item.price;
  final MenuItem item;
  int quantity;
  final double lockedPrice;
  String modifiers;
  bool sent;
  bool ready; // station (kitchen/bar) marked it ready
  bool done; // waiter delivered it to the guest
  bool get isBar => item.isBar;
  double get total => lockedPrice * quantity;

  Map<String, dynamic> toJson() => {
        'itemId': item.id,
        'quantity': quantity,
        'modifiers': modifiers,
        'sent': sent,
        'ready': ready,
        'done': done,
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

  /// Zone helpers: an order may contain both kitchen and bar items (e.g. a
  /// guest-web order). Feeds must look at the items, not just [splitTo] —
  /// otherwise the bar half of a mixed order is never shown to the bartender.
  List<CartLine> itemsFor(FeedType zone) =>
      items.where((l) => (zone == FeedType.bar) == l.isBar).toList();
  bool hasZone(FeedType zone) => items.any((l) => (zone == FeedType.bar) == l.isBar);

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
          final item = menu.firstWhereOrNull((mi) => mi.id == m['itemId']) ??
              MenuItem(
                id: m['itemId'] as String? ?? '?',
                name: 'Позиция из меню',
                description: '',
                price: (m['lockedPrice'] as num?)?.toDouble() ?? 0,
                category: 'Кухня',
                imageUrl: '',
                tags: const [],
                prepTime: 5,
              );
          return CartLine(
              item: item,
              quantity: m['quantity'] as int,
              modifiers: m['modifiers'] as String,
              sent: m['sent'] as bool,
              lockedPrice: (m['lockedPrice'] as num?)?.toDouble());
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'senderId': senderId,
        'text': text,
        'tags': tags,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'own': own,
        'voice': voice,
        'reactions': reactions,
        'kind': kind.index,
        'refId': refId,
      };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        groupId: j['groupId'] as String,
        senderId: j['senderId'] as String,
        text: j['text'] as String,
        tags: List<String>.from(j['tags'] as List? ?? const []),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        own: j['own'] as bool? ?? false,
        voice: j['voice'] as bool? ?? false,
        reactions: List<String>.from(j['reactions'] as List? ?? const []),
        kind: MessageKind.values[(j['kind'] as int?) ?? 0],
        refId: j['refId'] as String?,
      );
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
  bool showNewOrderBanner = true;
  bool showSyncToast = true;
  bool offlineModeSimulated = false;
  String activeUserName = 'Елена Соколова';

  void setSetting<T>(String key, T value, Function(T) apply) {
    apply(value);
    _box.put(key, value);
    notifyListeners();
  }

  Timer? _retryTimer;

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
    if (status == TableStatus.waiting) {
      animatedDot = dot
          .animate(onPlay: (c) => c.repeat())
          .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.3, 1.3),
              duration: 800.ms)
          .then()
          .scale(end: const Offset(1, 1), duration: 800.ms);
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
      this.icon,
      this.dotColor});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dotColor;

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
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ] else if (icon != null) ...[
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

// Photo widgets (MenuImage/ShimmerBox/MenuGridItem) and the old
// QuantityStepper were removed together with the photo-based ordering UI:
// the staff app is text-first now (see _OrderComposerTile/_CompactStepper).

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
    // The bottom nav is ALWAYS visible on the shell. The old multi-select
    // flow hid it (state.shellHideNav) and never brought it back after the
    // precheck was confirmed — waiters ended up on «Заказы» with no tabs at
    // all. Ordering now happens on a dedicated pushed screen, so the shell
    // never needs to hide its navigation.
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
      bottomNavigationBar: _ShellBottomNav(
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
          // Explicit demo/offline banner: without it the local seed data was
          // routinely mistaken for the real floor ("почему 12 столов?").
          if (!state.backendConnected) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => GoRouter.of(context).push('/settings'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 18, color: AppTheme.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.backendConnecting
                            ? 'Подключение к серверу…'
                            : 'Демо-режим: данные не с сервера. Нажмите, чтобы войти.',
                        style: T.smallSemi.copyWith(color: AppTheme.ink),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.ink2),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: const InputDecoration(
                hintText: 'Поиск стола или официанта',
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
                      dotColor: statusColor(s),
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
    final table = widget.table;
    final color = statusColor(table.status);
    final hasAttention = table.attention != null;
    final accent = hasAttention ? attentionColor(table.attention!) : color;
    final pillText =
        hasAttention ? attentionLabel(table.attention!) : statusLabel(table.status);
    final pulse = table.status == TableStatus.waiting || hasAttention;
    // colorTag bar only shows for a non-default (custom) tag color.
    final hasTag =
        table.color != AppColors.espresso && table.color != AppColors.ink;

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
        borderColor: hasAttention ? accent : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Guest-attention tint wash over the card surface.
            if (hasAttention)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            // 4px color-tag bar on the top edge.
            if (hasTag)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: table.color,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                ),
              ),
            // Status dot + 4px halo, top-right.
            Positioned(
              top: 0,
              right: 0,
              child: _HaloDot(accent, pulse: pulse),
            ),
            // Big mono table number + status/attention pill.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    table.number.toString().padLeft(2, '0'),
                    style: AppTypography.mono(
                        size: 30, weight: FontWeight.w800, color: AppColors.ink),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      pillText,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Order total (mono) or "свободен" at the bottom.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  table.status == TableStatus.free
                      ? 'свободен'
                      : state
                          .tableCart(table.id)
                          .fold(0.0, (s, l) => s + l.total)
                          .rub,
                  style: table.status == TableStatus.free
                      ? AppTypography.label(color: AppColors.ink40)
                      : AppTypography.mono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.ink55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String attentionLabel(String attention) => switch (attention) {
      'call' => 'ЗОВУТ',
      'bill' => 'СЧЁТ',
      'arrived' => 'ГОСТЬ',
      _ => 'СИГНАЛ',
    };

/// A status dot with a crisp 4px halo ring, matching the design's
/// `box-shadow: 0 0 0 4px <halo>`. Pulses while the table waits for a waiter
/// or has a guest-attention badge.
class _HaloDot extends StatelessWidget {
  const _HaloDot(this.color, {this.pulse = false});
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 0,
              spreadRadius: 4),
        ],
      ),
    );
    if (pulse) {
      dot = dot
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 1.0, end: 1.18, duration: 800.ms);
    }
    // Reserve room so the 4px halo isn't clipped against the card edge.
    return Padding(padding: const EdgeInsets.all(4), child: dot);
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.attention, required this.onAck});
  final String attention;
  final VoidCallback onAck;

  @override
  Widget build(BuildContext context) {
    final color = attentionColor(attention);
    final (label, icon) = switch (attention) {
      'call' => ('Гость зовёт официанта', Icons.pan_tool_rounded),
      'bill' => ('Гость просит счёт', Icons.receipt_long_rounded),
      'arrived' => ('Гость сел за стол', Icons.chair_rounded),
      _ => ('Сигнал от гостя', Icons.notifications_active_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTypography.bodySemi())),
          GestureDetector(
            onTap: onAck,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text('Принял',
                  style: AppTypography.bodySemi().copyWith(fontSize: 13)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0);
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
                          Text(
                              table.openedAt == null
                                  ? statusLabel(table.status)
                                  : 'Открыт ${table.openedAt!.hour.toString().padLeft(2, '0')}:${table.openedAt!.minute.toString().padLeft(2, '0')}${table.waiterName != '—' && table.waiterName.isNotEmpty ? ' · ${table.waiterName}' : ''}',
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
                    Text(_tableSubtitle(table), style: T.subtitle),
                  ],
                ),
              ),
              StatusBadge(table.status, showLabel: true),
            ],
          ),
          if (table.attention != null) ...[
            const SizedBox(height: 14),
            _AttentionBanner(
              attention: table.attention!,
              onAck: () => state.ackAttention(table),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                Row(
                  children: [
                    Text('Заказ', style: T.sectionTitle),
                    const SizedBox(width: 10),
                    if (lines.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.ok.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${lines.where((l) => l.done).length}/${lines.length} отдано',
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ok),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _guestStepper(context, state, table),
                const SizedBox(height: 16),
                if (lines.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long,
                              size: 48, color: AppTheme.separator),
                          const SizedBox(height: 16),
                          const Text('Чек пуст', style: T.bodySemi),
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
                  // Unsent (draft) lines can be swiped away or deleted with
                  // the explicit button; sent lines are already on the
                  // kitchen/bar screens and can only be marked as delivered.
                  ...lines.map((l) => l.sent
                      ? _orderItemRow(context, state, table, l)
                      : Dismissible(
                          key: ValueKey(l.hashCode),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.delete_outline,
                                color: AppTheme.danger),
                          ),
                          onDismissed: (_) =>
                              state.deleteLine(l, tableId: table.id),
                          child: _orderItemRow(context, state, table, l),
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
                              // Push through CafeState so the change reaches
                              // the hub (and every other device), not just
                              // this screen.
                              onTap: () => state.setTableStatus(table, s),
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
                        label: 'Добавить',
                        icon: Icons.add,
                        onPressed: () =>
                            GoRouter.of(context).push('/waiter-menu'))),
                const SizedBox(width: 12),
                Expanded(
                    child: AppButton(
                        label: 'Отправить',
                        icon: Icons.send,
                        color: AppTheme.warning,
                        onPressed: () => _sendUnsent(context, state, table))),
                const SizedBox(width: 12),
                AppButton(
                    label: '',
                    icon: Icons.forward,
                    kind: ButtonKind.secondary,
                    onPressed: () => _showForwardSheet(context, table)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Send everything not yet sent; kitchen/bar routing happens by station.
  /// Always answers with a snackbar — silence («нажал и ничего») is a bug.
  Future<void> _sendUnsent(
      BuildContext context, CafeState state, CafeTable table) async {
    final messenger = ScaffoldMessenger.of(context);
    final pending = state.tableCart(table.id).where((l) => !l.sent).toList();
    if (pending.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Нет новых позиций — всё уже отправлено')));
      return;
    }
    final kitchen = pending.where((l) => !l.isBar).fold(0, (s, l) => s + l.quantity);
    final bar = pending.where((l) => l.isBar).fold(0, (s, l) => s + l.quantity);
    final order = await state.submitOrder(tableId: table.id);
    if (!context.mounted) return;
    if (order != null) {
      messenger.showSnackBar(SnackBar(
          content: Text('Отправлено · Кухня $kitchen · Бар $bar'),
          backgroundColor: AppTheme.success));
    } else {
      messenger.showSnackBar(SnackBar(
          content: Text(state.backendError == null
              ? 'Не удалось отправить'
              : 'Не отправлено: ${state.backendError}'),
          backgroundColor: AppTheme.danger));
    }
  }

  /// Real header data instead of the hardcoded «Открыт 14:05 · Елена».
  String _tableSubtitle(CafeTable table) {
    final parts = <String>[];
    if (table.openedAt != null) {
      final t = table.openedAt!;
      parts.add(
          'Открыт ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    } else {
      parts.add(statusLabel(table.status));
    }
    if (table.waiterName.isNotEmpty && table.waiterName != '—') {
      parts.add(table.waiterName);
    }
    return parts.join(' · ');
  }

  Widget _guestStepper(BuildContext context, CafeState state, CafeTable table) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4ED),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_outline, size: 19, color: AppColors.occupied),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Гостей за столом',
                style: AppTypography.bodySemi().copyWith(fontSize: 13.5)),
          ),
          _stepperBtn(Icons.remove, false,
              () => state.setGuestCount(table.id, table.guestCount - 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('${table.guestCount}',
                style: AppTypography.mono(size: 18, weight: FontWeight.w700)),
          ),
          _stepperBtn(Icons.add, true,
              () => state.setGuestCount(table.id, table.guestCount + 1)),
        ],
      ),
    );
  }

  Widget _stepperBtn(IconData icon, bool primary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: primary ? AppColors.espresso : Colors.white,
          borderRadius: BorderRadius.circular(11),
          boxShadow: primary
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1))
                ],
        ),
        child: Icon(icon, size: 15, color: primary ? Colors.white : AppColors.ink),
      ),
    );
  }

  Widget _orderItemRow(
      BuildContext context, CafeState state, CafeTable table, CartLine line) {
    final notes = line.modifiers
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final isBar = line.isBar;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onLongPress: () => state.toggleItemDone(table, line),
        onTap: () => _showNotePresets(context, state, line),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => state.toggleItemDone(table, line),
              child: Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: line.done ? AppColors.ok : Colors.white,
                  border: Border.all(
                      color: line.done ? AppColors.ok : const Color(0xFFD8D3C7),
                      width: 2),
                ),
                child: line.done
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 9),
            Text('${line.quantity}×',
                style: AppTypography.mono(
                        size: 14,
                        weight: FontWeight.w700,
                        color: line.done ? AppColors.ink40 : AppColors.ink)
                    .copyWith(
                        decoration: line.done
                            ? TextDecoration.lineThrough
                            : null)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.item.name,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: line.done ? AppColors.ink40 : AppColors.ink,
                          decoration: line.done
                              ? TextDecoration.lineThrough
                              : null)),
                  if (!line.sent)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('черновик — не отправлено',
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.warning)),
                      ),
                    ),
                  if (line.ready && !line.done)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.ok.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check, size: 10, color: AppColors.ok),
                            const SizedBox(width: 4),
                            Text('готово на ${isBar ? "баре" : "кухне"}',
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ok)),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...notes.map(
                            (n) => _noteChip(n, () => state.removeItemNote(line, n))),
                        _addNoteChip(
                            () => _showNotePresets(context, state, line)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(line.lockedPrice.rub,
                style: AppTypography.mono(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: AppColors.ink55)
                    .copyWith(
                        decoration:
                            line.done ? TextDecoration.lineThrough : null)),
            if (!line.sent) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => state.deleteLine(line, tableId: table.id),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noteChip(String label, VoidCallback onRemove) {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.amberBg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.amber)),
            const SizedBox(width: 4),
            const Icon(Icons.close, size: 11, color: AppColors.amber),
          ],
        ),
      ),
    );
  }

  Widget _addNoteChip(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD8C9A8)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 11, color: AppColors.amber),
            SizedBox(width: 3),
            Text('примечание',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.amber)),
          ],
        ),
      ),
    );
  }

  void _showNotePresets(BuildContext context, CafeState state, CartLine line) {
    const presets = [
      'Без лука',
      'Без льда',
      'На соевом',
      'Остро',
      'Не остро',
      'Навынос',
      'Без сахара',
      'Хорошо прожарить'
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('${line.quantity}× ${line.item.name}', style: AppTypography.h3()),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets
                  .map((p) => GestureDetector(
                        onTap: () {
                          state.addItemNote(line, p);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: AppColors.sunken,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(p, style: AppTypography.body()),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
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

/// Unified order-taking screen ("приём заказа").
///
/// One and the same flow whether it's the FIRST order of a table or an
/// addition to an open one: search + always-visible category chips + compact
/// photo-less cards. Tap adds a dish (multi-category selection just works —
/// the selection is independent of the current filter), the stepper adjusts
/// quantity, long-press shows dish info. «Пречек» reviews and sends.
class _WaiterOrderScreenState extends State<WaiterOrderScreen> {
  /// Selection lives here (not in the table cart) until the precheck is
  /// confirmed — cancelling leaves no trace on the table's check.
  final Map<MenuItem, int> _selQty = {};
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _category = 'Все';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MenuItem> _filtered(CafeState state) {
    final q = _search.trim().toLowerCase();
    return state.menu.where((m) {
      final okCat = _category == 'Все' || m.category == _category;
      final okSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q);
      return okCat && okSearch;
    }).toList();
  }

  void _add(BuildContext context, MenuItem item) {
    if (!item.available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('«${item.name}» в стоп-листе'),
          backgroundColor: AppTheme.danger));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _selQty[item] = (_selQty[item] ?? 0) + 1);
  }

  void _removeOne(MenuItem item) {
    final current = _selQty[item] ?? 0;
    HapticFeedback.selectionClick();
    setState(() {
      if (current <= 1) {
        _selQty.remove(item);
      } else {
        _selQty[item] = current - 1;
      }
    });
  }

  void _openPrecheck(BuildContext context, String tableId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrecheckSheet(
        selectionQty: Map.from(_selQty),
        fixedTableId: tableId,
        onConfirmed: () {
          if (!mounted) return;
          setState(() => _selQty.clear());
          // Back to the table: the sent lines are visible on its check.
          if (context.canPop()) context.pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final table = state.currentTable ?? state.tables.firstOrNull;
    if (table == null) {
      return const AppScaffold(
          child: _EmptyState(
              icon: Icons.table_restaurant_outlined,
              title: 'Нет столов',
              sub: 'Сначала добавьте стол'));
    }
    final items = _filtered(state);
    final count = _selQty.values.fold(0, (s, v) => s + v);
    final total =
        _selQty.entries.fold(0.0, (s, e) => s + e.key.price * e.value);

    return AppScaffold(
      child: Stack(children: [
        Column(children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back, color: AppTheme.ink),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Стол ${table.number} · заказ',
                          style: T.screenTitle.copyWith(fontSize: 24)),
                      Text('Нажмите на блюдо, чтобы добавить',
                          style: T.subtitle),
                    ]),
              ),
            ]),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Поиск по меню...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.ink3),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.ink3),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Category chips stay visible at every moment of the selection —
          // switching categories must never drop what's already picked.
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: state.categories
                  .map((c) => CategoryChip(
                        label: c,
                        active: _category == c,
                        onTap: () => setState(() => _category = c),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: items.isEmpty
                ? const _EmptyState(
                    icon: Icons.search_off,
                    title: 'Ничего не найдено',
                    sub: 'Поменяйте запрос или категорию')
                : ListView.builder(
                    padding:
                        EdgeInsets.only(top: 6, bottom: count > 0 ? 130 : 40),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      return _OrderComposerTile(
                        item: item,
                        qty: _selQty[item] ?? 0,
                        onAdd: () => _add(ctx, item),
                        onRemove: () => _removeOne(item),
                        onInfo: () => _showStaffDishDetails(ctx, item),
                      );
                    },
                  ),
          ),
        ]),
        if (count > 0)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _ComposerBar(
              count: count,
              total: total,
              onClear: () => setState(() => _selQty.clear()),
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
    // Feeds are driven by the items' station, not by the order's splitTo:
    // a mixed order (e.g. from the guest web) has to appear in BOTH feeds,
    // each showing only its own positions. splitTo alone hid the bar half.
    final active =
        state.orders.where((o) => o.status != OrderStatus.completed).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final kitchenOrders =
        active.where((o) => o.hasZone(FeedType.kitchen)).toList();
    final barOrders = active.where((o) => o.hasZone(FeedType.bar)).toList();

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
                        itemBuilder: (_, i) => OrderCard(
                            order: kitchenOrders[i],
                            zone: FeedType.kitchen,
                            index: i)),
                barOrders.isEmpty
                    ? const _EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'Всё готово',
                        sub: 'Нет активных заказов в баре')
                    : ListView.builder(
                        itemCount: barOrders.length,
                        itemBuilder: (_, i) => OrderCard(
                            order: barOrders[i],
                            zone: FeedType.bar,
                            index: i)),
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
  const OrderCard(
      {super.key, required this.order, this.zone, this.index = 0});
  final CafeOrder order;

  /// The feed this card is rendered in. A mixed order shows only this
  /// zone's items here; null shows everything (e.g. in chat receipts).
  final FeedType? zone;
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
    final effectiveZone = zone ?? order.splitTo;
    final zoneColor =
        effectiveZone == FeedType.kitchen ? AppTheme.warning : AppTheme.bar;
    final visibleItems = zone == null ? order.items : order.itemsFor(zone!);

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
                            '#${order.id} ·${effectiveZone == FeedType.kitchen ? 'Кухня' : 'Бар'}',
                            style: T.priceSmall.copyWith(color: AppTheme.ink2))),
                    _LiveTimer(createdAt: order.createdAt, color: color),
                  ],
                ),
                const Divider(height: 24),
                ...visibleItems.map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${line.quantity}×',
                              style: T.price.copyWith(color: zoneColor, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Text(line.item.name, style: T.h3),
                                if (line.modifiers.isNotEmpty)
                                  Text(line.modifiers,
                                      style: T.small.copyWith(
                                          color: AppTheme.warning,
                                          fontWeight: FontWeight.w600)),
                              ])),
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

/// Staff menu tab — a read-only showcase (composition, allergens, stop-list).
/// Order taking moved to the dedicated composer screen: «Принять заказ» asks
/// for the table and opens the exact same flow as inside a table. The old
/// long-press multi-select is gone — it hid the category chips (locking the
/// waiter into one category) and hid the bottom navigation without a way back.
class _StaffMenuScreenState extends State<StaffMenuScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _category = 'Все';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MenuItem> _filtered(CafeState state) {
    final q = _search.trim().toLowerCase();
    return state.menu.where((m) {
      final okCat = _category == 'Все' || m.category == _category;
      final okSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q);
      return okCat && okSearch;
    }).toList();
  }

  void _pickTableAndOrder(BuildContext context) {
    final state = context.read<CafeState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TablePickerSheet(
        onPicked: (table) {
          state.currentTable = table;
          GoRouter.of(context).push('/waiter-menu');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final items = _filtered(state);

    return AppScaffold(
      bottomNav: null,
      child: Stack(children: [
        Column(children: [
          const Header(title: 'Меню', subtitle: 'Витрина и стоп-лист'),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Поиск блюда...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.ink3),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.ink3),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: state.categories
                  .map((c) => CategoryChip(
                        label: c,
                        active: _category == c,
                        onTap: () => setState(() => _category = c),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty
                ? const _EmptyState(
                    icon: Icons.search_off,
                    title: 'Ничего не найдено',
                    sub: 'Поменяйте запрос или категорию')
                : GridView.builder(
                    padding: const EdgeInsets.only(top: 12, bottom: 110),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.92),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) => _MenuShowcaseCard(
                      item: items[i],
                      onTap: () => _showStaffDishDetails(ctx, items[i]),
                    ),
                  ),
          ),
        ]),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: PrimaryButton(
            label: 'Принять заказ',
            icon: Icons.point_of_sale,
            onTap: () => _pickTableAndOrder(context),
          ),
        ),
      ]),
    );
  }
}

/// Compact photo-less showcase card: zone dot + category, name, price,
/// prep time and availability at a glance.
class _MenuShowcaseCard extends StatelessWidget {
  const _MenuShowcaseCard({required this.item, required this.onTap});
  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zoneColor = item.isBar ? AppTheme.bar : AppTheme.warning;
    return Opacity(
      opacity: item.available ? 1 : 0.55,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: zoneColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(item.category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.label.copyWith(color: AppTheme.ink3)),
            ),
            if (!item.available)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('СТОП',
                    style: T.label
                        .copyWith(color: Colors.white, fontSize: 9)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(item.name,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: T.bodySemi),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(item.description,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small),
          ],
          const Spacer(),
          Row(children: [
            Text(item.price.rub, style: T.price.copyWith(color: AppTheme.cta)),
            const Spacer(),
            const Icon(Icons.schedule, size: 12, color: AppTheme.ink3),
            const SizedBox(width: 3),
            Text('${item.prepTime} мин',
                style: T.label.copyWith(color: AppTheme.ink3)),
          ]),
        ]),
      ),
    );
  }
}

/// «На какой стол?» — the entry into the unified order flow from the menu tab.
class _TablePickerSheet extends StatelessWidget {
  const _TablePickerSheet({required this.onPicked});
  final ValueChanged<CafeTable> onPicked;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: AppTheme.separator,
              borderRadius: BorderRadius.circular(2)),
        ),
        Text('На какой стол?', style: T.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 16),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1),
            itemCount: state.tables.length,
            itemBuilder: (_, i) {
              final t = state.tables[i];
              final color = statusColor(t.status);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  onPicked(t);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(t.number.toString().padLeft(2, '0'),
                            style: AppTypography.mono(
                                size: 18,
                                weight: FontWeight.w800,
                                color: AppColors.ink)),
                        const SizedBox(height: 4),
                        Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                      ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ===== ORDER COMPOSER WIDGETS (photo-less, built for speed) =====

/// One menu position in the order composer. The whole row is a tap target
/// («+1»); a stepper appears once the dish is selected; long-press (or the
/// info icon) opens dish details. No photos — a colored zone bar tells
/// kitchen from bar at a glance.
class _OrderComposerTile extends StatelessWidget {
  const _OrderComposerTile({
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
    required this.onInfo,
  });
  final MenuItem item;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final zoneColor = item.isBar ? AppTheme.bar : AppTheme.warning;
    final selected = qty > 0;

    return GestureDetector(
      onTap: onAdd,
      onLongPress: onInfo,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.cta.withValues(alpha: 0.04)
              : AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppTheme.cta : const Color(0xFFF0EBE1),
              width: selected ? 1.4 : 1),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Opacity(
          opacity: item.available ? 1 : 0.5,
          child: Row(children: [
            // Zone bar: orange = kitchen, blue = bar.
            Container(
              width: 4,
              height: 62,
              decoration: BoxDecoration(
                color: zoneColor,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(13)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.bodySemi.copyWith(fontSize: 15)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text('${item.prepTime} мин · ${item.category}',
                            style: T.label.copyWith(color: AppTheme.ink3)),
                        if (!item.available) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: AppTheme.danger,
                                borderRadius: BorderRadius.circular(5)),
                            child: Text('СТОП',
                                style: T.label.copyWith(
                                    color: Colors.white, fontSize: 8.5)),
                          ),
                        ],
                      ]),
                    ]),
              ),
            ),
            const SizedBox(width: 8),
            Text(item.price.rub,
                style: T.priceSmall.copyWith(
                    fontSize: 14,
                    color: selected ? AppTheme.cta : AppTheme.ink)),
            const SizedBox(width: 10),
            if (!selected)
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                    color: AppTheme.cta, shape: BoxShape.circle),
                child:
                    const Icon(Icons.add, color: Colors.white, size: 18),
              )
            else
              Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                        color: AppTheme.surfaceSunken,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.remove, size: 18),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Center(
                      child: Text('$qty',
                          style: AppTypography.mono(
                              size: 16,
                              weight: FontWeight.w800,
                              color: AppColors.ink))),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                      color: AppTheme.cta, shape: BoxShape.circle),
                  child: const Icon(Icons.add,
                      color: Colors.white, size: 18),
                ),
              ]),
          ]),
        ),
      ),
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

/// Sticky bottom bar of the composer: running total + jump to the precheck.
class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.count,
    required this.total,
    required this.onClear,
    required this.onNext,
  });
  final int count;
  final double total;
  final VoidCallback onClear;
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
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count поз.', style: T.smallSemi),
                Text(total.rub, style: T.h2),
              ]),
        ),
        GhostButton(
          label: 'Очистить',
          onTap: onClear,
          height: 44,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 132,
          child: PrimaryButton(
            label: 'Пречек →',
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
    // Split preview by the real station (kitchen/bar), not by category name.
    final kitchenCount = _items.entries
        .where((e) => !e.key.isBar)
        .fold(0, (s, e) => s + e.value);
    final barCount = _items.entries
        .where((e) => e.key.isBar)
        .fold(0, (s, e) => s + e.value);
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
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('Все позиции удалены',
                          style: T.body.copyWith(color: AppTheme.ink2))),
                ),
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
                    // Position can be removed right up until the send —
                    // after that it lives on the station screens.
                    onDelete: () => setState(() => _items.remove(entry.key)),
                  )),

              // Split preview
              const Divider(height: 24),
              if (kitchenCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.restaurant, size: 16, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Text('На кухню: $kitchenCount',
                        style: T.bodySemi.copyWith(color: AppTheme.warning)),
                  ]),
                ),
              if (barCount > 0)
                Row(children: [
                  const Icon(Icons.local_bar, size: 16, color: AppTheme.bar),
                  const SizedBox(width: 8),
                  Text('В бар: $barCount',
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

  Future<void> _confirm(BuildContext context, CafeState state) async {
    final tableId = _tableId!;
    final table = state.tables.firstWhere((t) => t.id == tableId);
    final kitchenCount = _items.entries
        .where((e) => !e.key.isBar)
        .fold(0, (s, e) => s + e.value);
    final barCount = _items.entries
        .where((e) => e.key.isBar)
        .fold(0, (s, e) => s + e.value);
    final messenger = ScaffoldMessenger.of(context);

    for (final entry in _items.entries) {
      final note = _noteCtrl[entry.key]?.text.trim() ?? '';
      state.addToCart(entry.key, entry.value, note, tableId: tableId);
    }
    final order = await state.submitOrder(tableId: tableId);

    if (!mounted) return;
    Navigator.pop(context);
    widget.onConfirmed?.call();

    // Explicit feedback in BOTH outcomes — «отправил в бар и ничего не
    // произошло» must never happen again.
    if (order != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Заказ на Стол ${table.number} отправлен · Кухня $kitchenCount · Бар $barCount'),
        backgroundColor: AppTheme.success,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(state.backendError == null
            ? 'Нечего отправлять'
            : 'Не отправлено: ${state.backendError}. Позиции сохранены в чеке стола.'),
        backgroundColor: AppTheme.danger,
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
    required this.onDelete,
  });
  final MenuItem item;
  final int qty;
  final TextEditingController noteController;
  final bool expanded;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onToggleNote;
  final ValueChanged<String> onPreset;
  final VoidCallback onDelete;

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
          Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: item.isBar ? AppTheme.bar : AppTheme.warning,
                  shape: BoxShape.circle)),
          Expanded(
              child: Text(item.name,
                  style: T.price)),
          Text((item.price * qty).rub,
              style: T.bodySemi.copyWith(color: AppTheme.cta)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _CompactStepper(value: qty, onChanged: onQtyChanged),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onToggleNote,
            child: Text(expanded ? '− заметка' : '+ примечание',
                style: T.priceSmall.copyWith(color: AppTheme.bar)),
          ),
          const Spacer(),
          // Delete the position while the order is still a draft.
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              onDelete();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline,
                  size: 18, color: AppTheme.danger),
            ),
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
                Text('${group.members.length} участников',
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
    // Live numbers from the actual state — the tab used to show hardcoded
    // demo values (fake revenue, fake deltas), which read as "simulated"
    // activity even on a clean install.
    final state = context.watch<CafeState>();
    final now = DateTime.now();
    final todayOrders = state.orders
        .where((o) =>
            o.createdAt.year == now.year &&
            o.createdAt.month == now.month &&
            o.createdAt.day == now.day)
        .toList();
    final revenue = todayOrders.fold(0.0, (s, o) => s + o.total);
    final servedTables = todayOrders.map((o) => o.tableId).toSet().length;
    final avgCheck = servedTables == 0 ? 0.0 : revenue / servedTables;
    final activeTables =
        state.tables.where((t) => t.status != TableStatus.free).length;
    final activeOrders =
        state.orders.where((o) => o.status != OrderStatus.completed).toList();
    final oldestMin = activeOrders.isEmpty
        ? 0
        : activeOrders
            .map((o) => now.difference(o.createdAt).inMinutes)
            .reduce(max);

    // Revenue by hour (today, 08:00–23:00).
    final byHour = List<double>.filled(16, 0);
    for (final o in todayOrders) {
      final h = o.createdAt.hour;
      if (h >= 8 && h <= 23) byHour[h - 8] += o.total;
    }
    final maxHour = byHour.fold(0.0, max);

    return ListView(
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            MetricCard(
                label: 'Выручка',
                value: revenue.rub,
                delta: 'сегодня · ${todayOrders.length} заказов',
                isPositive: true,
                color: AppTheme.success),
            MetricCard(
                label: 'Средний чек',
                value: avgCheck.rub,
                delta: 'по $servedTables столам',
                isPositive: true,
                color: AppTheme.gold,
                index: 1),
            MetricCard(
                label: 'Столы',
                value: '$activeTables / ${state.tables.length}',
                delta: 'занято сейчас',
                isPositive: true,
                color: AppTheme.tOccupied,
                index: 2),
            MetricCard(
                label: 'В работе',
                value: '${activeOrders.length}',
                delta: oldestMin > 0 ? 'старейший $oldestMin мин' : 'нет очереди',
                isPositive: oldestMin <= 20,
                color: AppTheme.warning,
                index: 3),
          ],
        ),
        const SizedBox(height: 20),
        const SectionTitle('Выручка по часам'),
        AppCard(
          height: 160,
          child: maxHour == 0
              ? Center(
                  child: Text('Сегодня заказов ещё не было',
                      style: T.body.copyWith(color: AppTheme.ink2)))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: byHour
                      .map((v) => Container(
                          width: 12,
                          height: v == 0 ? 4 : 8 + 110 * (v / maxHour),
                          decoration: BoxDecoration(
                              color: v == maxHour
                                  ? AppTheme.cta
                                  : const Color(0xFFE4D7C2),
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
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: item.isBar ? AppTheme.bar : AppTheme.warning,
                        shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                          '${item.price.rub} · ${item.category} · ${item.isBar ? 'бар' : 'кухня'}',
                          style: T.smallSemi.copyWith(color: AppTheme.ink2)),
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
  var station = item == null ? 'kitchen' : (item.isBar ? 'bar' : 'kitchen');

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
                const SizedBox(height: 16),
                // Where the position is prepared — this is what routes the
                // order to the kitchen or bar screen.
                const Text('ГОТОВИТ', style: T.label),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: CategoryChip(
                      label: 'Кухня',
                      active: station == 'kitchen',
                      icon: Icons.restaurant,
                      onTap: () => setModalState(() => station = 'kitchen'),
                    ),
                  ),
                  Expanded(
                    child: CategoryChip(
                      label: 'Бар',
                      active: station == 'bar',
                      icon: Icons.local_bar,
                      onTap: () => setModalState(() => station = 'bar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                AppButton(
                  label: 'Сохранить',
                  onPressed: () {
                    final state = context.read<CafeState>();
                    if (name.text.trim().isEmpty) return;
                    if (item == null) {
                      state.upsertMenuItem(MenuItem(
                        id: 'm${DateTime.now().millisecondsSinceEpoch}',
                        name: name.text.trim(),
                        description: desc.text.trim(),
                        price: double.tryParse(price.text) ?? 0.0,
                        category: category.text.trim().isEmpty
                            ? 'Кухня'
                            : category.text.trim(),
                        imageUrl: '',
                        tags: [],
                        prepTime: int.tryParse(prep.text) ?? 10,
                        station: station,
                      ));
                    } else {
                      item.name = name.text.trim();
                      item.description = desc.text.trim();
                      item.price = double.tryParse(price.text) ?? item.price;
                      item.category = category.text.trim().isEmpty
                          ? item.category
                          : category.text.trim();
                      item.prepTime = int.tryParse(prep.text) ?? item.prepTime;
                      item.station = station;
                      state.upsertMenuItem(item);
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
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
                  Row(children: [
                    Expanded(
                        child: Text(item.name,
                            style: T.h1.copyWith(fontSize: 22))),
                    Text(item.price.rub,
                        style: T.h2.copyWith(color: AppTheme.cta))
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: (item.isBar ? AppTheme.bar : AppTheme.warning)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(item.isBar ? Icons.local_bar : Icons.restaurant,
                            size: 13,
                            color:
                                item.isBar ? AppTheme.bar : AppTheme.warning),
                        const SizedBox(width: 5),
                        Text(item.isBar ? 'Бар' : 'Кухня',
                            style: T.smallSemi.copyWith(
                                color: item.isBar
                                    ? AppTheme.bar
                                    : AppTheme.warning,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppTheme.surfaceSunken,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('${item.prepTime} мин · ${item.category}',
                          style: T.smallSemi),
                    ),
                    if (!item.available)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('СТОП-ЛИСТ',
                            style: T.smallSemi.copyWith(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w800)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  if (item.description.isNotEmpty)
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
      TableStatus.waiting => AppTheme.warning,
    };

String statusLabel(TableStatus status) => switch (status) {
      TableStatus.free => 'Свободен',
      TableStatus.occupied => 'Занят',
      TableStatus.waiting => 'Ждёт официанта',
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
            // Below: two different ways to (re)establish the connection.
            // reconnect() only works once _lastUser/_lastPass are already set
            // from a prior successful login (or via --dart-define, which we
            // deliberately do not bake into the web build — that would ship
            // real staff passwords inside a publicly downloadable JS bundle).
            // So the very first connection on a fresh device must go through
            // a typed login, not "Переподключить" — hence this form.
            if (!state.backendConnected) const _ConnectionLoginForm(),
            if (state.backendConnected)
              _SettingsRow(
                  label: 'Переподключить',
                  trailing: state.backendConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.cta))
                      : const Icon(Icons.sync, color: AppTheme.cta),
                  onTap: state.backendConnecting
                      ? null
                      : () => state.reconnect()),
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
            const _SettingsRow(label: 'Версия', value: 'v0.2.0'),
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

// First-time login form for the "Соединение" settings section. Distinct from
// reconnect() (which only re-uses credentials from an already-successful
// session): this is the only in-app way to type a username/password, since
// the web build intentionally does not bake real staff passwords into the
// public JS bundle via --dart-define.
class _ConnectionLoginForm extends StatefulWidget {
  const _ConnectionLoginForm();
  @override
  State<_ConnectionLoginForm> createState() => _ConnectionLoginFormState();
}

class _ConnectionLoginFormState extends State<_ConnectionLoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(CafeState state) async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;
    FocusScope.of(context).unfocus();
    await state.connectBackend(username: username, password: password);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _username, label: 'Логин'),
        const SizedBox(height: 10),
        AppTextField(controller: _password, label: 'Пароль', obscure: true),
        const SizedBox(height: 12),
        PrimaryButton(
          label: state.backendConnecting ? 'Подключение…' : 'Войти',
          onTap: state.backendConnecting ? null : () => _submit(state),
          height: 46,
        ),
      ]),
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
            // Bug fix: an unconstrained long value (e.g. backendError's full
            // sentence) took its full intrinsic width in ListTile.trailing,
            // squeezing the title down to ~0px and wrapping it one letter per
            // line. Capping width + wrapping onto up to 2 lines keeps long
            // values (error text) readable without starving the label.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                value!,
                style: T.body.copyWith(color: AppTheme.ink2),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
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
