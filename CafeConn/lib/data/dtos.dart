/// Plain-Dart data transfer objects mirroring the CafeConnect hub payloads.
///
/// Two server shapes exist and both are supported:
///   * "bootstrap" shape -> GET /api/staff/bootstrap/ (camelCase, Flutter-ready)
///   * "DRF" shape        -> WebSocket order/attention events (snake_case, nested)
///
/// Keeping these as pure Dart (no Flutter imports) makes them unit-testable.
library;

import '../core/i18n.dart';

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
  final String categoryId;

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
    this.categoryId = '',
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
        categoryId: _asString(j['categoryId'], ''),
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
  final int? tableNumber;

  /// Flutter OrderStatus name: accepted | cooking | ready | completed.
  final String status;

  /// station_scope: kitchen | bar | mixed.
  final String station;
  final String? waiterId;
  final String waiterName;

  /// ISO-8601 server timestamp. Nullable: old backends may omit it; the app
  /// then falls back to "now" (and the kitchen timer starts from zero).
  final String? createdAt;

  /// When the waiter accepted the order (guest orders: approval time). The prep
  /// timer counts from here when present, else from createdAt.
  final String? acceptedAt;

  /// Order-level guest comment (allergies / serving requests).
  final String note;

  /// Coupon snapshot (0 / '' when no coupon is applied). Written only by the
  /// hub at redemption; the app just shows the "− discount" line.
  final double discountAmount;
  final String couponCode;

  /// Alert ladder L3: some on-shift device saw this AWAITING order unhandled
  /// for 60s — highlight it everywhere.
  final bool alertEscalated;
  final List<OrderItemDto> items;

  const OrderDto({
    required this.id,
    required this.tableId,
    this.tableNumber,
    required this.status,
    required this.station,
    required this.items,
    this.waiterId,
    this.waiterName = '',
    this.createdAt,
    this.acceptedAt,
    this.note = '',
    this.discountAmount = 0,
    this.couponCode = '',
    this.alertEscalated = false,
  });

  factory OrderDto.fromBootstrap(Map<String, dynamic> j) => OrderDto(
        id: _asString(j['id']),
        tableId: _asString(j['tableId']),
        tableNumber: j['tableNumber'] == null ? null : _asInt(j['tableNumber']),
        status: _asString(j['status'], 'accepted'),
        station: _asString(j['station'], 'kitchen'),
        waiterId: j['waiterId'] == null ? null : _asString(j['waiterId']),
        waiterName: _asString(j['waiterName']),
        createdAt: j['createdAt'] == null ? null : _asString(j['createdAt']),
        acceptedAt: j['acceptedAt'] == null ? null : _asString(j['acceptedAt']),
        note: _asString(j['note'], ''),
        discountAmount: _asDouble(j['discountAmount']),
        couponCode: _asString(j['couponCode']),
        alertEscalated: _asBool(j['alertEscalated']),
        items: ((j['items'] as List?) ?? const [])
            .map((e) =>
                OrderItemDto.fromBootstrap((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// DRF OrderSerializer shape used by WebSocket order.* events.
  factory OrderDto.fromDrf(Map<String, dynamic> j) {
    final table = (j['table'] as Map?)?.cast<String, dynamic>();
    final employee = (j['employee'] as Map?)?.cast<String, dynamic>();
    return OrderDto(
      id: _asString(j['id']),
      tableId: _asString(table?['id'] ?? j['table_id']),
      tableNumber: table?['number'] == null ? null : _asInt(table?['number']),
      status: flutterOrderStatusFromDjango(_asString(j['status'], 'new')),
      station: _asString(j['station_scope'], 'kitchen'),
      waiterId: employee == null ? null : _asString(employee['id']),
      waiterName: _asString(employee?['name']),
      createdAt: j['created_at'] == null ? null : _asString(j['created_at']),
      acceptedAt: j['accepted_at'] == null ? null : _asString(j['accepted_at']),
      note: _asString(j['notes'], ''),
      discountAmount: _asDouble(j['discount_amount']),
      couponCode: _asString(j['coupon_code']),
      alertEscalated: _asBool(j['alert_escalated']),
      items: ((j['items'] as List?) ?? const [])
          .map((e) => OrderItemDto.fromDrf((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// One row of a campaign's per-source analytics.
class CampaignUtmStatDto {
  final String utmSource;
  final int issued;
  final int redeemed;
  const CampaignUtmStatDto(
      {required this.utmSource, required this.issued, required this.redeemed});
  factory CampaignUtmStatDto.fromJson(Map<String, dynamic> j) =>
      CampaignUtmStatDto(
        utmSource: _asString(j['utm_source']),
        issued: _asInt(j['issued']),
        redeemed: _asInt(j['redeemed']),
      );
}

/// A coupon campaign (GET/POST /api/staff/coupons/campaigns/), counters
/// included for the SMM analytics list.
class CouponCampaignDto {
  final int id;
  final String slug;
  final String title;
  final String titleIt;
  final String description;
  final String descriptionIt;

  /// Wire value: percent | fixed.
  final String discountType;
  final double discountValue;
  final String sourceUtm;
  final String? validFrom;
  final String? validUntil;
  final int? maxTotalIssues;
  final int perWalletLimit;
  final bool isActive;
  final int issuedCount;
  final int redeemedCount;
  final List<CampaignUtmStatDto> byUtm;

  const CouponCampaignDto({
    required this.id,
    required this.slug,
    required this.title,
    required this.titleIt,
    required this.description,
    required this.descriptionIt,
    required this.discountType,
    required this.discountValue,
    required this.sourceUtm,
    required this.validFrom,
    required this.validUntil,
    required this.maxTotalIssues,
    required this.perWalletLimit,
    required this.isActive,
    required this.issuedCount,
    required this.redeemedCount,
    required this.byUtm,
  });

  String get displayTitle =>
      // Same convention as MenuItem.displayName: IT label when the app is in
      // Italian and one exists, English otherwise.
      (L.isIt && titleIt.isNotEmpty ? titleIt : title);

  /// "−15%" / "−3.00 €" headline shared by the issue and redeem screens.
  String get discountLabel {
    if (discountType == 'percent') {
      final isWhole = discountValue == discountValue.roundToDouble();
      final text =
          isWhole ? discountValue.round().toString() : discountValue.toString();
      return '−$text%';
    }
    return '−${discountValue.toStringAsFixed(2)} €';
  }

  factory CouponCampaignDto.fromJson(Map<String, dynamic> j) =>
      CouponCampaignDto(
        id: _asInt(j['id']),
        slug: _asString(j['slug']),
        title: _asString(j['title']),
        titleIt: _asString(j['title_it']),
        description: _asString(j['description']),
        descriptionIt: _asString(j['description_it']),
        discountType: _asString(j['discount_type'], 'percent'),
        discountValue: _asDouble(j['discount_value']),
        sourceUtm: _asString(j['source_utm']),
        validFrom: j['valid_from'] == null ? null : _asString(j['valid_from']),
        validUntil:
            j['valid_until'] == null ? null : _asString(j['valid_until']),
        maxTotalIssues: j['max_total_issues'] == null
            ? null
            : _asInt(j['max_total_issues']),
        perWalletLimit: _asInt(j['per_wallet_limit'], 1),
        isActive: _asBool(j['is_active'], true),
        issuedCount: _asInt(j['issued_count']),
        redeemedCount: _asInt(j['redeemed_count']),
        byUtm: ((j['by_utm'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => CampaignUtmStatDto.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

/// POST /api/staff/coupons/issue/ — the signed claim link the guest scans.
class CouponIssueDto {
  final String token;
  final String claimUrl;
  final int expiresIn;
  final CouponCampaignDto campaign;
  const CouponIssueDto({
    required this.token,
    required this.claimUrl,
    required this.expiresIn,
    required this.campaign,
  });
  factory CouponIssueDto.fromJson(Map<String, dynamic> j) => CouponIssueDto(
        token: _asString(j['token']),
        claimUrl: _asString(j['claimUrl']),
        expiresIn: _asInt(j['expiresIn']),
        campaign: CouponCampaignDto.fromJson(
            ((j['campaign'] as Map?) ?? const {}).cast<String, dynamic>()),
      );
}

/// A guest coupon as staff sees it (redeem preview / redeem result).
class StaffCouponDto {
  final int id;
  final String code;

  /// Wire value: active | redeemed | expired | void.
  final String status;
  final String campaignTitle;
  final String campaignTitleIt;
  final String discountType;
  final double discountValue;
  final String issuedVia;
  final String utmSource;
  final int? orderId;
  final String redeemedBy;
  final String? redeemedAt;

  const StaffCouponDto({
    required this.id,
    required this.code,
    required this.status,
    required this.campaignTitle,
    required this.campaignTitleIt,
    required this.discountType,
    required this.discountValue,
    required this.issuedVia,
    required this.utmSource,
    required this.orderId,
    required this.redeemedBy,
    required this.redeemedAt,
  });

  String get displayTitle =>
      (L.isIt && campaignTitleIt.isNotEmpty ? campaignTitleIt : campaignTitle);

  String get discountLabel {
    if (discountType == 'percent') {
      final isWhole = discountValue == discountValue.roundToDouble();
      final text =
          isWhole ? discountValue.round().toString() : discountValue.toString();
      return '−$text%';
    }
    return '−${discountValue.toStringAsFixed(2)} €';
  }

  factory StaffCouponDto.fromJson(Map<String, dynamic> j) => StaffCouponDto(
        id: _asInt(j['id']),
        code: _asString(j['code']),
        status: _asString(j['status'], 'active'),
        campaignTitle: _asString(j['campaign_title']),
        campaignTitleIt: _asString(j['campaign_title_it']),
        discountType: _asString(j['discount_type'], 'percent'),
        discountValue: _asDouble(j['discount_value']),
        issuedVia: _asString(j['issued_via']),
        utmSource: _asString(j['utm_source']),
        orderId: j['order_id'] == null ? null : _asInt(j['order_id']),
        redeemedBy: _asString(j['redeemed_by']),
        redeemedAt:
            j['redeemed_at'] == null ? null : _asString(j['redeemed_at']),
      );
}

/// POST /api/staff/coupons/redeem-preview/ result.
class CouponPreviewDto {
  final StaffCouponDto coupon;
  final String displayStatus;
  final String? discountPreview;
  final String? orderTotal;
  const CouponPreviewDto({
    required this.coupon,
    required this.displayStatus,
    this.discountPreview,
    this.orderTotal,
  });
  factory CouponPreviewDto.fromJson(Map<String, dynamic> j) => CouponPreviewDto(
        coupon: StaffCouponDto.fromJson(
            ((j['coupon'] as Map?) ?? const {}).cast<String, dynamic>()),
        displayStatus: _asString(j['displayStatus'], 'active'),
        discountPreview: j['discountPreview'] == null
            ? null
            : _asString(j['discountPreview']),
        orderTotal: j['orderTotal'] == null ? null : _asString(j['orderTotal']),
      );
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
  final String? waiterId;
  final String waiter;
  final String? openedAt;
  final String? currentOrderId;
  final String? attention;
  final String attentionReason;

  /// Latest unacked attention-signal id (bootstrap only) — lets the staff app
  /// ack a signal that fired before this device connected.
  final String? attentionSignalId;

  /// The unacked signal reached alert ladder L3 somewhere — highlight it.
  final bool attentionEscalated;
  final bool ack;

  const TableDto({
    required this.id,
    required this.number,
    required this.name,
    required this.seats,
    required this.guestCount,
    required this.status,
    required this.colorTag,
    this.waiterId,
    required this.waiter,
    required this.openedAt,
    required this.currentOrderId,
    required this.attention,
    required this.attentionReason,
    this.attentionSignalId,
    this.attentionEscalated = false,
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
        waiterId: j['waiterId'] == null ? null : _asString(j['waiterId']),
        waiter: _asString(j['waiter']),
        openedAt: j['openedAt'] == null ? null : _asString(j['openedAt']),
        currentOrderId:
            j['currentOrderId'] == null ? null : _asString(j['currentOrderId']),
        attention: j['attention'] == null ? null : _asString(j['attention']),
        attentionReason: _asString(j['attentionReason']),
        attentionSignalId: j['attentionSignalId'] == null
            ? null
            : _asString(j['attentionSignalId']),
        attentionEscalated: _asBool(j['attentionEscalated']),
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
        waiterId: j['waiter_id'] == null ? null : _asString(j['waiter_id']),
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
  final String? employeeId;
  final String username;
  final String name;

  /// Employee.Role wire value: waiter | kitchen | bar | manager | accountant
  /// | admin. Empty when the hub predates role-aware bootstraps.
  final String role;

  /// Effective capabilities from the hub: {wait, bar, kitchen, menu, manage}.
  /// Empty when the hub predates capability-aware bootstraps (fall back to
  /// deriving them from [role]).
  final Map<String, dynamic> capabilities;

  /// Employee.is_on_shift — alerts only fire on on-shift devices.
  final bool isOnShift;
  final List<String> shiftAreas;
  final List<String> lastShiftAreas;
  const CurrentUserDto(
      {required this.id,
      this.employeeId,
      required this.username,
      required this.name,
      this.role = '',
      this.capabilities = const {},
      this.isOnShift = false,
      this.shiftAreas = const [],
      this.lastShiftAreas = const []});
  factory CurrentUserDto.fromJson(Map<String, dynamic> j) => CurrentUserDto(
        id: _asString(j['id']),
        employeeId: j['employeeId'] == null ? null : _asString(j['employeeId']),
        username: _asString(j['username']),
        name: _asString(j['name']),
        role: _asString(j['role']),
        capabilities: j['capabilities'] is Map
            ? (j['capabilities'] as Map).cast<String, dynamic>()
            : const {},
        isOnShift: _asBool(j['isOnShift']),
        shiftAreas: _asStringList(j['shiftAreas']),
        lastShiftAreas: _asStringList(j['lastShiftAreas']),
      );
}

class RestaurantDto {
  final String id;
  final String name;
  final String slug;
  final String timezone;
  final String currency;
  final int staffCount;
  final int tableCount;
  final double todaySales;
  final int activeTables;
  final int openCalls;
  final int onShiftStaff;

  const RestaurantDto({
    required this.id,
    required this.name,
    required this.slug,
    this.timezone = 'Europe/Rome',
    this.currency = 'EUR',
    this.staffCount = 0,
    this.tableCount = 0,
    this.todaySales = 0,
    this.activeTables = 0,
    this.openCalls = 0,
    this.onShiftStaff = 0,
  });

  factory RestaurantDto.fromJson(Map<String, dynamic> j) => RestaurantDto(
        id: _asString(j['id']),
        name: _asString(j['name']),
        slug: _asString(j['slug'], 'sissy-bar'),
        timezone: _asString(j['timezone'], 'Europe/Rome'),
        currency: _asString(j['currency'], 'EUR'),
        staffCount: _asInt(j['staffCount']),
        tableCount: _asInt(j['tableCount']),
        todaySales: _asDouble(j['todaySales']),
        activeTables: _asInt(j['activeTables']),
        openCalls: _asInt(j['openCalls']),
        onShiftStaff: _asInt(j['onShiftStaff']),
      );
}

/// A staff member as the manager sees them in the access panel: identity,
/// primary role and the grantable capability flags.
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
  final bool canContent;
  final bool canGrantDiscount;
  final bool canManage;
  final bool canReports;
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
    this.canContent = false,
    this.canGrantDiscount = false,
    this.canManage = false,
    this.canReports = false,
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
        canContent: _asBool(j['can_content']),
        canGrantDiscount: _asBool(j['can_grant_discount']),
        canManage: _asBool(j['can_manage']),
        canReports: _asBool(j['can_reports']),
      );
}

/// One post on the venue's guest social feed (GET/POST /api/staff/feed/).
/// `embedHtml` is hub-generated markup; the app only shows metadata and a
/// platform preview card — rendering the embed is the guest page's job.
class SocialPostDto {
  final int id;
  final String sourceUrl;

  /// Wire value: instagram | threads | twitter_x | facebook.
  final String platform;
  final String domain;
  final bool isHidden;
  final bool isPinned;
  final String createdBy;
  final String? createdAt;

  const SocialPostDto({
    required this.id,
    required this.sourceUrl,
    required this.platform,
    required this.domain,
    required this.isHidden,
    required this.isPinned,
    this.createdBy = '',
    this.createdAt,
  });

  factory SocialPostDto.fromJson(Map<String, dynamic> j) => SocialPostDto(
        id: _asInt(j['id']),
        sourceUrl: _asString(j['source_url']),
        platform: _asString(j['platform']),
        domain: _asString(j['domain']),
        isHidden: _asBool(j['is_hidden']),
        isPinned: _asBool(j['is_pinned']),
        createdBy: _asString(j['created_by']),
        createdAt: j['created_at'] == null ? null : _asString(j['created_at']),
      );
}

/// The staff feed list: posts (pinned first) + the configurable pinned limit.
class StaffFeedDto {
  final List<SocialPostDto> posts;
  final int pinnedLimit;
  const StaffFeedDto({required this.posts, required this.pinnedLimit});

  factory StaffFeedDto.fromJson(Map<String, dynamic> j) => StaffFeedDto(
        posts: ((j['posts'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => SocialPostDto.fromJson(e.cast<String, dynamic>()))
            .toList(),
        pinnedLimit: _asInt(j['pinnedLimit'], 3),
      );
}

/// One storefront block (cover / facts / badges / cta / popular / about):
/// its position in this list is the render order on the guest page.
class StorefrontBlockDto {
  final String key;
  final bool visible;
  const StorefrontBlockDto({required this.key, required this.visible});
  factory StorefrontBlockDto.fromJson(Map<String, dynamic> j) =>
      StorefrontBlockDto(
          key: _asString(j['key']), visible: _asBool(j['visible'], true));
  Map<String, dynamic> toJson() => {'key': key, 'visible': visible};
}

/// A built-in theme preset from the hub ("sissi" is always first).
class ThemePresetDto {
  final String key;
  final String name;
  final String nameIt;

  /// bg / card / ink / mut / line / accent / accent_deep / accent_soft → hex.
  final Map<String, String> palette;
  const ThemePresetDto({
    required this.key,
    required this.name,
    required this.nameIt,
    required this.palette,
  });
  factory ThemePresetDto.fromJson(Map<String, dynamic> j) => ThemePresetDto(
        key: _asString(j['key']),
        name: _asString(j['name']),
        nameIt: _asString(j['name_it'], _asString(j['name'])),
        palette: ((j['palette'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
      );
}

/// The venue storefront settings (GET/PATCH /api/staff/venue/).
class VenueSettingsDto {
  final String name;
  final String tagline;
  final String taglineIt;
  final String about;
  final String aboutIt;
  final String address;
  final String addressIt;
  final String hours;
  final String hoursIt;
  final List<Map<String, String>> badges; // [{en, it}]
  final String mapsUrl;
  final String logoUrl;
  final String coverUrl;

  /// bg / card / ink / mut / line / accent / accent_deep / accent_soft → hex.
  final Map<String, String> palette;
  final List<StorefrontBlockDto> blocks;
  final int pinnedPostsLimit;

  const VenueSettingsDto({
    required this.name,
    required this.tagline,
    required this.taglineIt,
    required this.about,
    required this.aboutIt,
    required this.address,
    required this.addressIt,
    required this.hours,
    required this.hoursIt,
    required this.badges,
    required this.mapsUrl,
    required this.logoUrl,
    required this.coverUrl,
    required this.palette,
    required this.blocks,
    required this.pinnedPostsLimit,
  });

  static const _paletteWire = {
    'bg': 'color_bg',
    'card': 'color_card',
    'ink': 'color_ink',
    'mut': 'color_mut',
    'line': 'color_line',
    'accent': 'color_accent',
    'accent_deep': 'color_accent_deep',
    'accent_soft': 'color_accent_soft',
  };

  factory VenueSettingsDto.fromJson(Map<String, dynamic> j) => VenueSettingsDto(
        name: _asString(j['name']),
        tagline: _asString(j['tagline']),
        taglineIt: _asString(j['tagline_it']),
        about: _asString(j['about']),
        aboutIt: _asString(j['about_it']),
        address: _asString(j['address']),
        addressIt: _asString(j['address_it']),
        hours: _asString(j['hours']),
        hoursIt: _asString(j['hours_it']),
        badges: ((j['badges'] as List?) ?? const [])
            .whereType<Map>()
            .map((b) => {
                  'en': _asString(b['en']),
                  'it': _asString(b['it']),
                })
            .toList(),
        mapsUrl: _asString(j['maps_url']),
        logoUrl: _asString(j['logo_url']),
        coverUrl: _asString(j['cover_url']),
        palette: _paletteWire
            .map((key, wire) => MapEntry(key, _asString(j[wire], '#000000'))),
        blocks: ((j['storefront_blocks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => StorefrontBlockDto.fromJson(e.cast<String, dynamic>()))
            .toList(),
        pinnedPostsLimit: _asInt(j['pinned_posts_limit'], 3),
      );

  /// Wire name of one palette entry (bg → color_bg).
  static String paletteWireName(String key) => _paletteWire[key] ?? key;
}

/// GET /api/staff/venue/ payload: settings + built-in presets.
class VenuePayloadDto {
  final VenueSettingsDto venue;
  final List<ThemePresetDto> presets;
  const VenuePayloadDto({required this.venue, required this.presets});
  factory VenuePayloadDto.fromJson(Map<String, dynamic> j) => VenuePayloadDto(
        venue: VenueSettingsDto.fromJson(
            ((j['venue'] as Map?) ?? const {}).cast<String, dynamic>()),
        presets: ((j['presets'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ThemePresetDto.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

/// A compact in-venue directory used by task assignment and @ completion.
class TaskAssigneeDto {
  final int id;
  final String name;
  final String role;
  final bool isOnShift;

  const TaskAssigneeDto({
    required this.id,
    required this.name,
    required this.role,
    required this.isOnShift,
  });

  factory TaskAssigneeDto.fromJson(Map<String, dynamic> j) => TaskAssigneeDto(
        id: _asInt(j['id']),
        name: _asString(j['name']),
        role: _asString(j['role']),
        isOnShift: _asBool(j['is_on_shift']),
      );
}

/// A staff task — the same object behind chat bubbles and the planner.
class StaffTaskDto {
  final int id;
  final String title;
  final String note;

  /// Wire: opening | closing | cleaning | inventory | service | other.
  final String category;
  final int? assigneeId;
  final String assigneeName;
  final String createdByName;
  final String? dueAt;

  /// Wire: none | daily | weekly.
  final String recurrence;
  final List<int> recurrenceWeekdays;

  /// Wire: open | done | cancelled.
  final String status;
  final String doneByName;
  final String? doneAt;

  /// Wire: chat | planner | bot.
  final String source;

  /// Non-empty when the task came from a checklist ("opening"/"closing").
  final String checklistKey;

  const StaffTaskDto({
    required this.id,
    required this.title,
    required this.note,
    required this.category,
    required this.assigneeId,
    required this.assigneeName,
    required this.createdByName,
    required this.dueAt,
    required this.recurrence,
    required this.recurrenceWeekdays,
    required this.status,
    required this.doneByName,
    required this.doneAt,
    required this.source,
    required this.checklistKey,
  });

  bool get isDone => status == 'done';
  bool get isOpen =>
      status == 'open' || status == 'available' || status == 'in_progress';
  bool get isAvailable =>
      status == 'available' || (status == 'open' && assigneeId == null);
  bool get isInProgress =>
      status == 'in_progress' || (status == 'open' && assigneeId != null);

  StaffTaskDto copyWith({
    int? assigneeId,
    bool clearAssignee = false,
    String? assigneeName,
    String? dueAt,
    String? status,
    String? doneByName,
    String? doneAt,
    bool clearDone = false,
  }) =>
      StaffTaskDto(
        id: id,
        title: title,
        note: note,
        category: category,
        assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
        assigneeName: clearAssignee ? '' : (assigneeName ?? this.assigneeName),
        createdByName: createdByName,
        dueAt: dueAt ?? this.dueAt,
        recurrence: recurrence,
        recurrenceWeekdays: recurrenceWeekdays,
        status: status ?? this.status,
        doneByName: clearDone ? '' : (doneByName ?? this.doneByName),
        doneAt: clearDone ? null : (doneAt ?? this.doneAt),
        source: source,
        checklistKey: checklistKey,
      );

  factory StaffTaskDto.fromJson(Map<String, dynamic> j) => StaffTaskDto(
        id: _asInt(j['id']),
        title: _asString(j['title']),
        note: _asString(j['note']),
        category: _asString(j['category'], 'other'),
        assigneeId: j['assignee'] == null ? null : _asInt(j['assignee']),
        assigneeName: _asString(j['assignee_name']),
        createdByName: _asString(j['created_by_name']),
        dueAt: j['due_at'] == null ? null : _asString(j['due_at']),
        recurrence: _asString(j['recurrence'], 'none'),
        recurrenceWeekdays: ((j['recurrence_weekdays'] as List?) ?? const [])
            .map((e) => _asInt(e))
            .toList(),
        status: _asString(j['status'], 'open'),
        doneByName: _asString(j['done_by_name']),
        doneAt: j['done_at'] == null ? null : _asString(j['done_at']),
        source: _asString(j['source'], 'chat'),
        checklistKey: _asString(j['checklist_key']),
      );
}

/// The quoted preview shown on a threaded reply.
class ChatReplyPreviewDto {
  final int id;
  final String authorName;
  final String kind;
  final String body;
  const ChatReplyPreviewDto({
    required this.id,
    required this.authorName,
    required this.kind,
    required this.body,
  });
  factory ChatReplyPreviewDto.fromJson(Map<String, dynamic> j) =>
      ChatReplyPreviewDto(
        id: _asInt(j['id']),
        authorName: _asString(j['author_name'], 'CafeBot'),
        kind: _asString(j['kind'], 'text'),
        body: _asString(j['body']),
      );
}

/// One persistent chat message. `task` is the LIVE task for task bubbles.
class ChatMessageDto {
  final int id;

  /// Wire: general | kitchen | bar.
  final String channel;

  /// Wire: text | task | checklist | system.
  final String kind;
  final String body;
  final int? authorId;
  final String authorName; // 'CafeBot' for bot/system posts
  final StaffTaskDto? task;
  final int? replyTo;
  final ChatReplyPreviewDto? replyPreview;
  final int replyCount;
  final String? createdAt;

  const ChatMessageDto({
    required this.id,
    required this.channel,
    required this.kind,
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.task,
    required this.replyTo,
    required this.replyPreview,
    required this.replyCount,
    required this.createdAt,
  });

  bool get isBot => authorId == null;

  factory ChatMessageDto.fromJson(Map<String, dynamic> j) => ChatMessageDto(
        id: _asInt(j['id']),
        channel: _asString(j['channel'], 'general'),
        kind: _asString(j['kind'], 'text'),
        body: _asString(j['body']),
        authorId: j['author'] == null ? null : _asInt(j['author']),
        authorName: _asString(j['author_name'], 'CafeBot'),
        task: j['task'] is Map
            ? StaffTaskDto.fromJson((j['task'] as Map).cast<String, dynamic>())
            : null,
        replyTo: j['reply_to'] == null ? null : _asInt(j['reply_to']),
        replyPreview: j['reply_preview'] is Map
            ? ChatReplyPreviewDto.fromJson(
                (j['reply_preview'] as Map).cast<String, dynamic>())
            : null,
        replyCount: _asInt(j['reply_count']),
        createdAt: j['created_at'] == null ? null : _asString(j['created_at']),
      );

  /// A copy with an updated live task (task.updated realtime events).
  ChatMessageDto withTask(StaffTaskDto updated) => ChatMessageDto(
        id: id,
        channel: channel,
        kind: kind,
        body: body,
        authorId: authorId,
        authorName: authorName,
        task: updated,
        replyTo: replyTo,
        replyPreview: replyPreview,
        replyCount: replyCount,
        createdAt: createdAt,
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
  final RestaurantDto? restaurant;
  final List<RestaurantDto> availableRestaurants;
  final bool isPlatformOwner;
  final CurrentUserDto? currentUser;
  final List<TableDto> tables;
  final List<MenuItemDto> menu;
  final List<OrderDto> orders;
  final List<OrderDto> history; // recently-archived (paid) orders, for history
  final List<CategoryDto> categories;
  final Map<String, dynamic> preferences;

  /// Web Push feature flag + the applicationServerKey for
  /// pushManager.subscribe(). Disabled when no VAPID keys are in the env.
  final bool pushEnabled;
  final String pushPublicKey;

  const BootstrapDto({
    this.restaurant,
    this.availableRestaurants = const [],
    this.isPlatformOwner = false,
    required this.currentUser,
    required this.tables,
    required this.menu,
    required this.orders,
    required this.history,
    required this.preferences,
    this.categories = const [],
    this.pushEnabled = false,
    this.pushPublicKey = '',
  });

  factory BootstrapDto.fromJson(Map<String, dynamic> j) => BootstrapDto(
        restaurant: j['restaurant'] is Map
            ? RestaurantDto.fromJson(
                (j['restaurant'] as Map).cast<String, dynamic>())
            : null,
        availableRestaurants: ((j['availableRestaurants'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => RestaurantDto.fromJson(e.cast<String, dynamic>()))
            .toList(),
        isPlatformOwner: _asBool(j['isPlatformOwner']),
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
        categories: ((j['categories'] as List?) ?? const [])
            .map(
                (e) => CategoryDto.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        preferences:
            (j['preferences'] as Map?)?.cast<String, dynamic>() ?? const {},
        pushEnabled: _asBool(((j['push'] as Map?) ?? const {})['enabled']),
        pushPublicKey:
            _asString(((j['push'] as Map?) ?? const {})['publicKey']),
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

/// One owner-defined menu category: display name + hex color, editable from
/// the manager panel and /system-admin/. `key` is the stable machine id.
class CategoryDto {
  final String id;
  final String key;
  final String name;
  final String color; // hex, e.g. #DFAF2B
  const CategoryDto({
    required this.id,
    required this.key,
    required this.name,
    required this.color,
  });
  factory CategoryDto.fromJson(Map<String, dynamic> j) => CategoryDto(
        id: _asString(j['id']),
        key: _asString(j['key'], ''),
        name: _asString(j['name']),
        color: _asString(j['color'], '#DFAF2B'),
      );
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
