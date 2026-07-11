/// Plain-Dart data transfer objects mirroring the CafeConnect hub payloads.
///
/// Two server shapes exist and both are supported:
///   * "bootstrap" shape -> GET /api/staff/bootstrap/ (camelCase, Flutter-ready)
///   * "DRF" shape        -> WebSocket order/attention events (snake_case, nested)
///
/// Keeping these as pure Dart (no Flutter imports) makes them unit-testable.
library;

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String _asString(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

bool _asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

List<String> _asStringList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

/// Maps a Django Order.status to the Flutter OrderStatus name the app uses.
/// Mirrors the backend `flutter_order_status` so realtime (DRF) events agree
/// with the bootstrap payload.
String flutterOrderStatusFromDjango(String s) {
  switch (s) {
    case 'awaiting':
      return 'awaiting';
    case 'new':
    case 'pending':
      return 'accepted';
    case 'cooking':
    case 'preparing':
      return 'cooking';
    case 'ready':
      return 'ready';
    case 'delivered':
    case 'completed':
    case 'paid':
      return 'completed';
    default:
      return 'accepted';
  }
}

/// Maps a Django Table.status to the Flutter TableStatus name the app uses.
/// Only three statuses exist since 2026-07-02 (free/occupied/waiting); the
/// legacy Django values are kept here so an old backend can't crash the app.
String flutterTableStatusFromDjango(String s) {
  switch (s) {
    case 'occupied':
    case 'ready': // legacy
      return 'occupied';
    case 'waiting':
    case 'new_order': // legacy
    case 'needs_service': // legacy
    case 'awaiting_payment': // legacy
    case 'late': // legacy
      return 'waiting';
    case 'free':
    default:
      return 'free';
  }
}

class MenuItemDto {
  final String id;
  final String name;
  final String nameIt;
  final String description;
  final String descriptionIt;
  final double price;
  final String category;
  final String categoryIt;
  final String imageUrl;
  final List<String> tags;
  final int prepTime;
  final bool available;
  final bool promo;
  final String composition;
  final List<String> allergens;
  final String station;

  const MenuItemDto({
    required this.id,
    required this.name,
    this.nameIt = '',
    required this.description,
    this.descriptionIt = '',
    required this.price,
    required this.category,
    this.categoryIt = '',
    required this.imageUrl,
    required this.tags,
    required this.prepTime,
    required this.available,
    required this.promo,
    required this.composition,
    required this.allergens,
    required this.station,
  });

  factory MenuItemDto.fromBootstrap(Map<String, dynamic> j) => MenuItemDto(
        id: _asString(j['id']),
        name: _asString(j['name']),
        nameIt: _asString(j['nameIt']),
        description: _asString(j['description']),
        descriptionIt: _asString(j['descriptionIt']),
        price: _asDouble(j['price']),
        category: _asString(j['category']),
        categoryIt: _asString(j['categoryIt']),
        imageUrl: _asString(j['imageUrl']),
        tags: _asStringList(j['tags']),
        prepTime: _asInt(j['prepTime'], 5),
        available: _asBool(j['available'], true),
        promo: _asBool(j['promo']),
        composition: _asString(j['composition']),
        allergens: _asStringList(j['allergens']),
        station: _asString(j['station'], 'kitchen'),
      );
}

class OrderItemDto {
  final String id;
  final String dishId;
  final String name;
  final int qty;
  final double price;
  final List<String> notes;
  final String station;
  final bool ready;
  final bool done;

  const OrderItemDto({
    required this.id,
    required this.dishId,
    required this.name,
    required this.qty,
    required this.price,
    required this.notes,
    required this.station,
    required this.ready,
    required this.done,
  });

  factory OrderItemDto.fromBootstrap(Map<String, dynamic> j) => OrderItemDto(
        id: _asString(j['id']),
        dishId: _asString(j['dishId']),
        name: _asString(j['name']),
        qty: _asInt(j['qty'], 1),
        price: _asDouble(j['price']),
        notes: _asStringList(j['notes']),
        station: _asString(j['station'], 'kitchen'),
        ready: _asBool(j['ready']),
        done: _asBool(j['done']),
      );

  /// DRF OrderItemSerializer shape (snake_case, nested menu_item).
  factory OrderItemDto.fromDrf(Map<String, dynamic> j) {
    final menuItem = (j['menu_item'] as Map?)?.cast<String, dynamic>();
    return OrderItemDto(
      id: _asString(j['id']),
      dishId: _asString(menuItem?['id']),
      name: _asString(menuItem?['name']),
      qty: _asInt(j['quantity'], 1),
      price: _asDouble(j['unit_price']),
      notes: _asStringList(j['notes']),
      station: _asString(j['station'], 'kitchen'),
      ready: _asBool(j['ready']),
      done: _asBool(j['done']),
    );
  }
}

class OrderDto {
  final String id;
  final String tableId;

  /// Flutter OrderStatus name: accepted | cooking | ready | completed.
  final String status;

  /// station_scope: kitchen | bar | mixed.
  final String station;

  /// ISO-8601 server timestamp. Nullable: old backends may omit it; the app
  /// then falls back to "now" (and the kitchen timer starts from zero).
  final String? createdAt;

  /// When the waiter accepted the order (guest orders: approval time). The prep
  /// timer counts from here when present, else from createdAt.
  final String? acceptedAt;

  /// Order-level guest comment (allergies / serving requests).
  final String note;
  final List<OrderItemDto> items;

  const OrderDto({
    required this.id,
    required this.tableId,
    required this.status,
    required this.station,
    required this.items,
    this.createdAt,
    this.acceptedAt,
    this.note = '',
  });

  factory OrderDto.fromBootstrap(Map<String, dynamic> j) => OrderDto(
        id: _asString(j['id']),
        tableId: _asString(j['tableId']),
        status: _asString(j['status'], 'accepted'),
        station: _asString(j['station'], 'kitchen'),
        createdAt: j['createdAt'] == null ? null : _asString(j['createdAt']),
        acceptedAt: j['acceptedAt'] == null ? null : _asString(j['acceptedAt']),
        note: _asString(j['note'], ''),
        items: ((j['items'] as List?) ?? const [])
            .map((e) =>
                OrderItemDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// DRF OrderSerializer shape used by WebSocket order.* events.
  factory OrderDto.fromDrf(Map<String, dynamic> j) {
    final table = (j['table'] as Map?)?.cast<String, dynamic>();
    return OrderDto(
      id: _asString(j['id']),
      tableId: _asString(table?['id'] ?? j['table_id']),
      status: flutterOrderStatusFromDjango(_asString(j['status'], 'new')),
      station: _asString(j['station_scope'], 'kitchen'),
      createdAt: j['created_at'] == null ? null : _asString(j['created_at']),
      acceptedAt: j['accepted_at'] == null ? null : _asString(j['accepted_at']),
      note: _asString(j['notes'], ''),
      items: ((j['items'] as List?) ?? const [])
          .map((e) => OrderItemDto.fromDrf((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class TableDto {
  final String id;
  final int number;
  final String name;
  final int seats;
  final int guestCount;

  /// Flutter TableStatus name.
  final String status;
  final String colorTag;
  final String waiter;
  final String? openedAt;
  final String? currentOrderId;
  final String? attention;
  final String attentionReason;

  /// Latest unacked attention-signal id (bootstrap only) — lets the staff app
  /// ack a signal that fired before this device connected.
  final String? attentionSignalId;
  final bool ack;

  const TableDto({
    required this.id,
    required this.number,
    required this.name,
    required this.seats,
    required this.guestCount,
    required this.status,
    required this.colorTag,
    required this.waiter,
    required this.openedAt,
    required this.currentOrderId,
    required this.attention,
    required this.attentionReason,
    this.attentionSignalId,
    required this.ack,
  });

  factory TableDto.fromBootstrap(Map<String, dynamic> j) => TableDto(
        id: _asString(j['id']),
        number: _asInt(j['number']),
        name: _asString(j['name']),
        seats: _asInt(j['seats'], 2),
        guestCount: _asInt(j['guestCount']),
        status: _asString(j['status'], 'free'),
        colorTag: _asString(j['colorTag']),
        waiter: _asString(j['waiter']),
        openedAt: j['openedAt'] == null ? null : _asString(j['openedAt']),
        currentOrderId:
            j['currentOrderId'] == null ? null : _asString(j['currentOrderId']),
        attention: j['attention'] == null ? null : _asString(j['attention']),
        attentionReason: _asString(j['attentionReason']),
        attentionSignalId: j['attentionSignalId'] == null
            ? null
            : _asString(j['attentionSignalId']),
        ack: _asBool(j['ack']),
      );

  /// DRF TableSerializer shape (snake_case) nested in order/attention events.
  factory TableDto.fromDrf(Map<String, dynamic> j) => TableDto(
        id: _asString(j['id']),
        number: _asInt(j['number']),
        name: _asString(j['label']),
        seats: _asInt(j['capacity'], 2),
        guestCount: _asInt(j['guest_count']),
        status: flutterTableStatusFromDjango(_asString(j['status'], 'free')),
        colorTag: _asString(j['color_tag']),
        waiter: _asString(j['waiter']),
        openedAt: j['opened_at'] == null ? null : _asString(j['opened_at']),
        currentOrderId: null,
        attention: (j['attention'] == null || _asString(j['attention']).isEmpty)
            ? null
            : _asString(j['attention']),
        attentionReason: _asString(j['attention_reason']),
        ack: _asBool(j['attention_acknowledged']),
      );
}

class CurrentUserDto {
  final String id;
  final String username;
  final String name;

  /// Employee.Role wire value: waiter | kitchen | bar | manager | accountant
  /// | admin. Empty when the hub predates role-aware bootstraps.
  final String role;

  /// Effective capabilities from the hub: {wait, bar, kitchen, menu, manage}.
  /// Empty when the hub predates capability-aware bootstraps (fall back to
  /// deriving them from [role]).
  final Map<String, dynamic> capabilities;
  const CurrentUserDto(
      {required this.id,
      required this.username,
      required this.name,
      this.role = '',
      this.capabilities = const {}});
  factory CurrentUserDto.fromJson(Map<String, dynamic> j) => CurrentUserDto(
        id: _asString(j['id']),
        username: _asString(j['username']),
        name: _asString(j['name']),
        role: _asString(j['role']),
        capabilities: j['capabilities'] is Map
            ? (j['capabilities'] as Map).cast<String, dynamic>()
            : const {},
      );
}

/// A staff member as the manager sees them in the access panel: identity,
/// primary role and the four grantable capability flags.
class EmployeeDto {
  final String id;
  final String username;
  final String firstName;
  final String lastName;
  final String name;
  final String role;
  final bool canWait;
  final bool canBar;
  final bool canKitchen;
  final bool canManageMenu;
  const EmployeeDto({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.role,
    required this.canWait,
    required this.canBar,
    required this.canKitchen,
    required this.canManageMenu,
  });
  factory EmployeeDto.fromJson(Map<String, dynamic> j) => EmployeeDto(
        id: _asString(j['id']),
        username: _asString(j['username']),
        firstName: _asString(j['first_name']),
        lastName: _asString(j['last_name']),
        name: _asString(j['name']),
        role: _asString(j['role']),
        canWait: _asBool(j['can_wait']),
        canBar: _asBool(j['can_bar']),
        canKitchen: _asBool(j['can_kitchen']),
        canManageMenu: _asBool(j['can_manage_menu']),
      );
}

/// One line of an order's audit trail (who did what, when).
class OrderEventDto {
  final String actor;
  final String action;
  final String detail;
  final String createdAt;
  const OrderEventDto({
    required this.actor,
    required this.action,
    required this.detail,
    required this.createdAt,
  });
  factory OrderEventDto.fromJson(Map<String, dynamic> j) => OrderEventDto(
        actor: _asString(j['actor']),
        action: _asString(j['action']),
        detail: _asString(j['detail']),
        createdAt: _asString(j['createdAt']),
      );
}

class BootstrapDto {
  final CurrentUserDto? currentUser;
  final List<TableDto> tables;
  final List<MenuItemDto> menu;
  final List<OrderDto> orders;
  final List<OrderDto> history; // recently-archived (paid) orders, for history
  final Map<String, dynamic> preferences;

  const BootstrapDto({
    required this.currentUser,
    required this.tables,
    required this.menu,
    required this.orders,
    required this.history,
    required this.preferences,
  });

  factory BootstrapDto.fromJson(Map<String, dynamic> j) => BootstrapDto(
        currentUser: j['currentUser'] == null
            ? null
            : CurrentUserDto.fromJson(
                (j['currentUser'] as Map).cast<String, dynamic>()),
        tables: ((j['tables'] as List?) ?? const [])
            .map((e) =>
                TableDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
        menu: ((j['menu'] as List?) ?? const [])
            .map((e) =>
                MenuItemDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
        orders: ((j['orders'] as List?) ?? const [])
            .map((e) =>
                OrderDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
        history: ((j['history'] as List?) ?? const [])
            .map((e) =>
                OrderDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
        preferences:
            (j['preferences'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// One table's history for a single day, plus the list of days that have
/// orders (newest first) so the client can page day-by-day. See
/// StaffTableHistoryView on the backend.
class TableHistoryDto {
  final String tableId;
  final String? date; // resolved day being shown (ISO yyyy-MM-dd), null if none
  final List<String> dates; // distinct days with orders, newest first
  final List<OrderDto> orders; // orders for [date], newest first

  const TableHistoryDto({
    required this.tableId,
    required this.date,
    required this.dates,
    required this.orders,
  });

  factory TableHistoryDto.fromJson(Map<String, dynamic> j) => TableHistoryDto(
        tableId: _asString(j['tableId']),
        date: j['date'] == null ? null : _asString(j['date']),
        dates: ((j['dates'] as List?) ?? const [])
            .map((e) => _asString(e))
            .toList(),
        orders: ((j['orders'] as List?) ?? const [])
            .map((e) =>
                OrderDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// Attention signal (guest -> staff) as emitted on the realtime feed.
class AttentionDto {
  final String id;
  final String tableId;
  final String signalType; // arrived | call_waiter | bill_request
  final String reason;
  final bool ack;
  const AttentionDto({
    required this.id,
    required this.tableId,
    required this.signalType,
    required this.reason,
    required this.ack,
  });

  factory AttentionDto.fromDrf(Map<String, dynamic> j) {
    final table = (j['table'] as Map?)?.cast<String, dynamic>();
    return AttentionDto(
      id: _asString(j['id']),
      tableId: _asString(table?['id'] ?? j['table_id']),
      signalType: _asString(j['signal_type']),
      reason: _asString(j['reason']),
      ack: _asBool(j['ack']),
    );
  }
}

/// Manager dashboard analytics from GET /api/staff/stats/ — aggregated over
/// the whole order history server-side (see StaffStatsView).
class StatsDto {
  final double revenueToday;
  final int? revenueDeltaPct; // vs yesterday; null when yesterday had none
  final int ordersToday;
  final double avgCheck;
  final int? avgCheckDeltaPct;
  final int servedTables;
  final int activeTables;
  final int totalTables;
  final int freeTables;
  final int avgPrepMinutes;
  final int delayedOrders;
  final List<double> revenueByHour; // length 24, indexed by hour of day
  final List<WaiterStatDto> byWaiter; // today's sales attributed per waiter
  final List<TopItemDto> topItems; // today's best sellers, by quantity

  const StatsDto({
    required this.revenueToday,
    required this.revenueDeltaPct,
    required this.ordersToday,
    required this.avgCheck,
    required this.avgCheckDeltaPct,
    required this.servedTables,
    required this.activeTables,
    required this.totalTables,
    required this.freeTables,
    required this.avgPrepMinutes,
    required this.delayedOrders,
    required this.revenueByHour,
    required this.byWaiter,
    this.topItems = const [],
  });

  factory StatsDto.fromJson(Map<String, dynamic> j) {
    final raw = (j['revenueByHour'] as List?) ?? const [];
    final hours = List<double>.generate(
        24, (i) => i < raw.length ? _asDouble(raw[i]) : 0.0);
    final waiters = ((j['byWaiter'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => WaiterStatDto.fromJson(e.cast<String, dynamic>()))
        .toList();
    int? asIntOrNull(dynamic v) => v == null ? null : _asInt(v);
    return StatsDto(
      revenueToday: _asDouble(j['revenueToday']),
      revenueDeltaPct: asIntOrNull(j['revenueDeltaPct']),
      ordersToday: _asInt(j['ordersToday']),
      avgCheck: _asDouble(j['avgCheck']),
      avgCheckDeltaPct: asIntOrNull(j['avgCheckDeltaPct']),
      servedTables: _asInt(j['servedTables']),
      activeTables: _asInt(j['activeTables']),
      totalTables: _asInt(j['totalTables']),
      freeTables: _asInt(j['freeTables']),
      avgPrepMinutes: _asInt(j['avgPrepMinutes']),
      delayedOrders: _asInt(j['delayedOrders']),
      revenueByHour: hours,
      byWaiter: waiters,
      topItems: ((j['topItems'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => TopItemDto.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// One of today's best-selling positions (manager overview).
class TopItemDto {
  final String name;
  final String category;
  final int qty;
  final double revenue;
  const TopItemDto({
    required this.name,
    required this.category,
    required this.qty,
    required this.revenue,
  });
  factory TopItemDto.fromJson(Map<String, dynamic> j) => TopItemDto(
        name: _asString(j['name']),
        category: _asString(j['category'], ''),
        qty: _asInt(j['qty']),
        revenue: _asDouble(j['revenue']),
      );
}

/// One waiter's attributed sales for today (manager analytics breakdown).
class WaiterStatDto {
  final String id;
  final String name;
  final int orders;
  final int tables;
  final double revenue;
  const WaiterStatDto({
    required this.id,
    required this.name,
    required this.orders,
    required this.tables,
    required this.revenue,
  });
  factory WaiterStatDto.fromJson(Map<String, dynamic> j) => WaiterStatDto(
        id: _asString(j['id']),
        name: _asString(j['name'], '—'),
        orders: _asInt(j['orders']),
        tables: _asInt(j['tables']),
        revenue: _asDouble(j['revenue']),
      );
}

class OrderHistoryItemDto {
  final String name;
  final int qty;
  final String station;
  final bool ready;
  final bool done;

  const OrderHistoryItemDto({
    required this.name,
    required this.qty,
    required this.station,
    required this.ready,
    required this.done,
  });

  factory OrderHistoryItemDto.fromJson(Map<String, dynamic> j) {
    return OrderHistoryItemDto(
      name: _asString(j['name']),
      qty: _asInt(j['qty']),
      station: _asString(j['station']),
      ready: _asBool(j['ready']),
      done: _asBool(j['done']),
    );
  }
}

class OrderHistoryDto {
  final String id;
  final int tableNumber;
  final String status;
  final String source;
  final String station;
  final String guestName;
  final String employee;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double total;
  final List<OrderHistoryItemDto> items;

  const OrderHistoryDto({
    required this.id,
    required this.tableNumber,
    required this.status,
    required this.source,
    required this.station,
    required this.guestName,
    required this.employee,
    required this.createdAt,
    required this.updatedAt,
    required this.total,
    required this.items,
  });

  factory OrderHistoryDto.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] as List?) ?? const [];
    return OrderHistoryDto(
      id: _asString(j['id']),
      tableNumber: _asInt(j['tableNumber']),
      status: _asString(j['status']),
      source: _asString(j['source']),
      station: _asString(j['station']),
      guestName: _asString(j['guestName']),
      employee: _asString(j['employee']),
      createdAt: DateTime.tryParse(_asString(j['createdAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(_asString(j['updatedAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      total: _asDouble(j['total']),
      items: rawItems
          .whereType<Map>()
          .map((e) => OrderHistoryItemDto.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}
