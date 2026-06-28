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
String flutterTableStatusFromDjango(String s) {
  switch (s) {
    case 'occupied':
      return 'occupied';
    case 'awaiting_payment':
      return 'awaitingPayment';
    case 'ready':
      return 'ready';
    case 'late':
      return 'late';
    case 'new_order':
    case 'needs_service':
      return 'newOrder';
    case 'free':
    default:
      return 'free';
  }
}

class MenuItemDto {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
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
    required this.description,
    required this.price,
    required this.category,
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
        description: _asString(j['description']),
        price: _asDouble(j['price']),
        category: _asString(j['category']),
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
  final List<OrderItemDto> items;

  const OrderDto({
    required this.id,
    required this.tableId,
    required this.status,
    required this.station,
    required this.items,
  });

  factory OrderDto.fromBootstrap(Map<String, dynamic> j) => OrderDto(
        id: _asString(j['id']),
        tableId: _asString(j['tableId']),
        status: _asString(j['status'], 'accepted'),
        station: _asString(j['station'], 'kitchen'),
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
        attention: (j['attention'] == null ||
                _asString(j['attention']).isEmpty)
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
  const CurrentUserDto(
      {required this.id, required this.username, required this.name});
  factory CurrentUserDto.fromJson(Map<String, dynamic> j) => CurrentUserDto(
        id: _asString(j['id']),
        username: _asString(j['username']),
        name: _asString(j['name']),
      );
}

class BootstrapDto {
  final CurrentUserDto? currentUser;
  final List<TableDto> tables;
  final List<MenuItemDto> menu;
  final List<OrderDto> orders;
  final Map<String, dynamic> preferences;

  const BootstrapDto({
    required this.currentUser,
    required this.tables,
    required this.menu,
    required this.orders,
    required this.preferences,
  });

  factory BootstrapDto.fromJson(Map<String, dynamic> j) => BootstrapDto(
        currentUser: j['currentUser'] == null
            ? null
            : CurrentUserDto.fromJson(
                (j['currentUser'] as Map).cast<String, dynamic>()),
        tables: ((j['tables'] as List?) ?? const [])
            .map((e) => TableDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
        menu: ((j['menu'] as List?) ?? const [])
            .map((e) =>
                MenuItemDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
        orders: ((j['orders'] as List?) ?? const [])
            .map((e) => OrderDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
        preferences:
            (j['preferences'] as Map?)?.cast<String, dynamic>() ?? const {},
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
