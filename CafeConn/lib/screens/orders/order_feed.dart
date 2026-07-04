import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

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
                    ? const EmptyState(
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
                    ? const EmptyState(
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
