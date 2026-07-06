import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme/app_theme.dart';

enum UserRole { waiter, cook, bartender, manager, admin }

/// Maps the hub's Employee.Role wire value to the app's UserRole.
/// Unknown roles fall back to waiter — the most restricted role that can
/// still run a shift (never silently grant manager screens).
UserRole roleFromWire(String wire) => switch (wire) {
      'waiter' => UserRole.waiter,
      'kitchen' => UserRole.cook,
      'bar' => UserRole.bartender,
      'manager' => UserRole.manager,
      'accountant' => UserRole.manager,
      'admin' => UserRole.admin,
      _ => UserRole.waiter,
    };

/// Reverse of [roleFromWire]: the app's UserRole to the hub's Employee.Role
/// wire value. Used when a manager creates a staff account.
String roleToWire(UserRole role) => switch (role) {
      UserRole.waiter => 'waiter',
      UserRole.cook => 'kitchen',
      UserRole.bartender => 'bar',
      UserRole.manager => 'manager',
      UserRole.admin => 'admin',
    };

/// Deliberately just three states (product decision, 2026-07-02): a table is
/// either free, taken, or the guests are waiting for a waiter. Must stay in
/// sync with Table.Status on the Django side (free / occupied / waiting).
enum TableStatus { free, occupied, waiting }

// `awaiting` = a guest order placed from the guest web, pending a waiter's
// approval before it reaches the kitchen/bar. Kept last so existing persisted
// status indices don't shift.
enum OrderStatus { accepted, cooking, ready, completed, awaiting }

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
  // Guest attention signal: 'call', 'bill', 'arrived', or null.
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
    this.nameIt = '',
    this.descriptionIt = '',
    this.categoryIt = '',
  });
  final String id;
  String name;
  String description;
  double price;
  String category;

  /// Italian display labels from the hub (menu_i18n). Empty for locally
  /// created items — display falls back to the primary (English) field.
  String nameIt;
  String descriptionIt;
  String categoryIt;

  String get displayName => L.isIt && nameIt.isNotEmpty ? nameIt : name;
  String get displayDescription =>
      L.isIt && descriptionIt.isNotEmpty ? descriptionIt : description;
  String get displayCategory =>
      L.isIt && categoryIt.isNotEmpty ? categoryIt : category;
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
  /// that sent beer to the kitchen: only 'Drinks'/'Coffee' counted as bar.
  String station;

  static const _barCategories = {
    'Drinks',
    'Coffee',
    'Tea',
    'Bar',
    'Beer',
    'Wine',
    'Cocktails',
    'Alcohol',
    'Lemonades',
    'Smoothies',
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
        'nameIt': nameIt,
        'descriptionIt': descriptionIt,
        'categoryIt': categoryIt,
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
        nameIt: j['nameIt'] as String? ?? '',
        descriptionIt: j['descriptionIt'] as String? ?? '',
        categoryIt: j['categoryIt'] as String? ?? '',
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
      this.orderItemId,
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
  String? orderItemId; // backend OrderItem.id for item-level ready/delivery
  bool get isBar => item.isBar;
  double get total => lockedPrice * quantity;

  Map<String, dynamic> toJson() => {
        'itemId': item.id,
        'quantity': quantity,
        'modifiers': modifiers,
        'sent': sent,
        'ready': ready,
        'done': done,
        'orderItemId': orderItemId,
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
  bool hasZone(FeedType zone) =>
      items.any((l) => (zone == FeedType.bar) == l.isBar);

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
                name: 'Menu item',
                description: '',
                price: (m['lockedPrice'] as num?)?.toDouble() ?? 0,
                category: 'Kitchen',
                imageUrl: '',
                tags: const [],
                prepTime: 5,
              );
          return CartLine(
              item: item,
              quantity: m['quantity'] as int,
              modifiers: m['modifiers'] as String,
              sent: m['sent'] as bool? ?? false,
              ready: m['ready'] as bool? ?? false,
              done: m['done'] as bool? ?? false,
              orderItemId: m['orderItemId'] as String?,
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
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        own: j['own'] as bool? ?? false,
        voice: j['voice'] as bool? ?? false,
        reactions: List<String>.from(j['reactions'] as List? ?? const []),
        kind: MessageKind.values[(j['kind'] as int?) ?? 0],
        refId: j['refId'] as String?,
      );
}

String attentionLabel(String attention) => switch (attention) {
      'call' => L.attCall,
      'bill' => L.attBill,
      'arrived' => L.attGuest,
      _ => L.attSignal,
    };

String roleLabel(UserRole role) => switch (role) {
      UserRole.admin => L.roleAdmin,
      UserRole.manager => L.roleManager,
      UserRole.waiter => L.roleWaiter,
      UserRole.cook => L.roleCook,
      UserRole.bartender => L.roleBartender,
    };

String orderStatusLabel(OrderStatus status) => switch (status) {
      OrderStatus.awaiting => L.osAwaiting,
      OrderStatus.accepted => L.osAccepted,
      OrderStatus.cooking => L.osCooking,
      OrderStatus.ready => L.osReady,
      OrderStatus.completed => L.osCompleted,
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
      TableStatus.free => L.stFree,
      TableStatus.occupied => L.stOccupied,
      TableStatus.waiting => L.stWaiting,
    };
