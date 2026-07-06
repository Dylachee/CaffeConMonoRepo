import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

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
    // Cook is locked to the kitchen feed, bartender to the bar feed — they
    // only ever see their own orders. Everyone else can switch.
    final locked = state.lockedZone;
    final zone = locked ?? (_zone == 0 ? FeedType.kitchen : FeedType.bar);

    // Feeds are driven by the items' station, not by the order's splitTo:
    // a mixed order (e.g. from the guest web) has to appear in BOTH feeds,
    // each showing only its own positions. splitTo alone hid the bar half.
    final active = state.orders
        // `awaiting` orders are still pending a waiter's approval — the
        // kitchen/bar must not see them until they're confirmed.
        .where((o) =>
            o.status != OrderStatus.completed &&
            o.status != OrderStatus.awaiting)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    bool visibleInZone(CafeOrder order, FeedType feed) {
      final items = order.itemsFor(feed);
      if (items.isEmpty) return false;
      return state.isStationRole
          ? items.any((line) => !line.ready)
          : items.any((line) => !line.done);
    }

    final kitchenOrders =
        active.where((o) => visibleInZone(o, FeedType.kitchen)).toList();
    final barOrders =
        active.where((o) => visibleInZone(o, FeedType.bar)).toList();
    final visible = zone == FeedType.kitchen ? kitchenOrders : barOrders;

    return AppScaffold(
      bottomNav: null,
      child: Column(
        children: [
          Header(
              title: L.orders,
              subtitle: locked != null
                  ? L.activeCount(visible.length)
                  : L.activeCount(kitchenOrders.length + barOrders.length)),
          // Tap-only segmented control — no swipe widget, no gesture conflict.
          // Hidden for station roles: their zone is fixed.
          if (locked == null)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: AppTheme.surfaceSunken,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                _ZoneTab(
                  label: L.kitchenU,
                  count: kitchenOrders.length,
                  icon: Icons.restaurant,
                  iconColor: AppTheme.warning,
                  selected: zone == FeedType.kitchen,
                  onTap: () => setState(() => _zone = 0),
                ),
                _ZoneTab(
                  label: L.barU,
                  count: barOrders.length,
                  icon: Icons.local_bar,
                  iconColor: AppTheme.bar,
                  selected: zone == FeedType.bar,
                  onTap: () => setState(() => _zone = 1),
                ),
              ]),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.check_circle_outline,
                    title: L.allDone,
                    sub: zone == FeedType.kitchen
                        ? L.noActiveKitchen
                        : L.noActiveBar)
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) =>
                        OrderCard(order: visible[i], zone: zone, index: i)),
          ),
        ],
      ),
    );
  }
}

// Tap-only zone tab for KITCHEN/BAR — replaces swipeable TabBar
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
  const OrderCard({super.key, required this.order, this.zone, this.index = 0});
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
    // Waiter/manager/admin can jump straight from an order card to its table
    // (station roles have no table screen, so no navigation for them).
    final canOpenTable = state.canSeeTables && table != null;

    final card = AppCard(
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
                      child: Text(L.tableN(table?.number ?? '??').toUpperCase(),
                          style: T.priceSmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            '#${order.id} · ${effectiveZone == FeedType.kitchen ? L.kitchen : L.bar}',
                            style:
                                T.priceSmall.copyWith(color: AppTheme.ink2))),
                    LiveTimer(createdAt: order.createdAt, color: color),
                  ],
                ),
                const Divider(height: 24),
                ...visibleItems.map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${line.quantity}×',
                              style: T.price.copyWith(
                                  color: zoneColor,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(line.item.displayName, style: T.h3),
                                if (line.modifiers.isNotEmpty)
                                  Text(line.modifiers,
                                      style: T.small.copyWith(
                                          color: AppTheme.warning,
                                          fontWeight: FontWeight.w600)),
                                const SizedBox(height: 5),
                                _ItemStateLine(
                                    order: order,
                                    line: line,
                                    state: state,
                                    zoneColor: zoneColor),
                              ])),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _actionFor(state, effectiveZone, visibleItems)),
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

    if (!canOpenTable) return card;
    // Tapping the card body opens the table; taps on the inner buttons
    // (deliver / chat) win the gesture arena, so they still act as before.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        state.currentTable = table;
        GoRouter.of(context).push('/table-details');
      },
      child: card,
    );
  }

  /// Role-aware primary action:
  ///   station (cook/bartender): New → «Start», Cooking → «Ready»; once the
  ///     order is ready their part is done — no way to complete or cancel,
  ///     so a second tap can never make the order vanish;
  ///   waiter: sees progress read-only until the order is READY, then gets
  ///     «Delivered to guest» — that (and only that) moves it to the table
  ///     history, where it stays until the table is cleared;
  ///   manager/admin: can do both.
  Widget _actionFor(
      CafeState state, FeedType effectiveZone, List<CartLine> visibleItems) {
    final role = state.currentRole;
    final actsAsStation = role == UserRole.cook ||
        role == UserRole.bartender ||
        role == UserRole.manager ||
        role == UserRole.admin;
    final canDeliver = state.canDeliverOrders;
    final stationReady =
        visibleItems.isNotEmpty && visibleItems.every((line) => line.ready);
    final stationDelivered =
        visibleItems.isNotEmpty && visibleItems.every((line) => line.done);
    final hasReadyToDeliver =
        visibleItems.any((line) => line.ready && !line.done);

    if (stationDelivered) {
      return _StatusStrip(label: L.osCompleted, color: AppTheme.success);
    }
    if (canDeliver) {
      if (hasReadyToDeliver) {
        // Real action now (was a passive label): deliver every ready item in
        // this order. Per-item "Delivered to guest" buttons still sit on each
        // line for delivering them individually.
        final readyN = visibleItems.where((l) => l.ready && !l.done).length;
        return AppButton(
            label: L.deliverAllReadyN(readyN),
            icon: Icons.done_all,
            color: AppTheme.success,
            onPressed: () => state.deliverReadyLines(order, visibleItems));
      }
      return _StatusStrip(
          label: stationReady ? L.waitingWaiter : L.waitingStation,
          color: stationReady ? AppTheme.success : AppTheme.ink2);
    }
    if (!actsAsStation) {
      return _StatusStrip(label: L.waitingStation, color: AppTheme.ink2);
    }
    if (stationReady) {
      return _StatusStrip(label: L.waitingWaiter, color: AppTheme.success);
    }
    if (order.status == OrderStatus.accepted) {
      return AppButton(
          label: L.startCooking,
          onPressed: () => state.advanceStationStatus(order));
    }
    return AppButton(
        label: L.markReady,
        onPressed: () {
          state.markStationItemsReady(order, effectiveZone);
        });
  }
}

class _ItemStateLine extends StatelessWidget {
  const _ItemStateLine({
    required this.order,
    required this.line,
    required this.state,
    required this.zoneColor,
  });

  final CafeOrder order;
  final CartLine line;
  final CafeState state;
  final Color zoneColor;

  @override
  Widget build(BuildContext context) {
    final label = line.done
        ? L.itemDelivered
        : line.ready
            ? L.itemReady
            : L.inPreparation;
    final color = line.done
        ? AppTheme.success
        : line.ready
            ? AppTheme.success
            : zoneColor;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: T.label.copyWith(color: color, fontWeight: FontWeight.w800)),
      ),
      if (state.canDeliverOrders && line.ready && !line.done) ...[
        const SizedBox(width: 8),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.success,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () {
            state.toggleOrderItemDelivered(order, line);
          },
          child: Text(L.markDelivered,
              style: T.label.copyWith(fontWeight: FontWeight.w900)),
        ),
      ],
    ]);
  }
}

/// Non-interactive status pill shown where a role has no action to take.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: T.bodySemi.copyWith(color: color, fontSize: 14),
          overflow: TextOverflow.ellipsis),
    );
  }
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
              Text(L.discussOrder, style: T.h2),
              const SizedBox(height: 16),
              AppTextField(controller: comment, label: L.comment),
              const SizedBox(height: 20),
              Wrap(
                  spacing: 8,
                  children: context
                      .read<CafeState>()
                      .groups
                      .map((g) => AppButton(
                          label: switch (g.type) {
                            FeedType.kitchen => L.kitchen,
                            FeedType.bar => L.bar,
                            _ => L.generalChat,
                          },
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
