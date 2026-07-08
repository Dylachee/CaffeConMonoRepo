import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/order_activity.dart';

/// Full-screen, day-by-day history for one table. Opens on the newest day that
/// has orders and pages backwards/forwards through the days the hub reports.
/// Read-only: delivery lives on the table's active section, not here.
class TableHistoryScreen extends StatefulWidget {
  const TableHistoryScreen({super.key});
  @override
  State<TableHistoryScreen> createState() => _TableHistoryScreenState();
}

class _TableHistoryScreenState extends State<TableHistoryScreen> {
  late final CafeTable _table;
  bool _loading = true;
  bool _error = false;
  TableHistoryResult? _data;
  int _dayIndex = 0; // index into _data.dates (0 = newest)

  @override
  void initState() {
    super.initState();
    final state = context.read<CafeState>();
    _table = state.currentTable ?? state.tables.first;
    _load();
  }

  Future<void> _load({String? date}) async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final res =
        await context.read<CafeState>().loadTableHistory(_table.id, date: date);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) {
        _error = true;
        return;
      }
      _data = res;
      _dayIndex = (res.date == null) ? 0 : res.dates.indexOf(res.date!);
      if (_dayIndex < 0) _dayIndex = 0;
    });
  }

  // dates are newest-first: an *earlier* day is a higher index.
  void _goEarlier() {
    final d = _data;
    if (d != null && _dayIndex < d.dates.length - 1) {
      _load(date: d.dates[_dayIndex + 1]);
    }
  }

  void _goLater() {
    final d = _data;
    if (d != null && _dayIndex > 0) _load(date: d.dates[_dayIndex - 1]);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
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
                    Text(L.orderHistory, style: T.screenTitle),
                    Text(L.tableN(_table.number), style: T.subtitle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (data != null && data.dates.isNotEmpty) _dayNav(data),
          const SizedBox(height: 16),
          Expanded(child: _body(data)),
        ],
      ),
    );
  }

  Widget _dayNav(TableHistoryResult data) {
    final canEarlier = _dayIndex < data.dates.length - 1;
    final canLater = _dayIndex > 0;
    final ordersN = data.orders.length;
    final dayTotal = data.orders
        .expand((o) => o.items)
        .fold(0.0, (s, l) => s + l.total);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left, L.earlierDay, canEarlier ? _goEarlier : null),
          Expanded(
            child: Column(
              children: [
                Text(_dayLabel(data.date),
                    style: T.h2.copyWith(fontSize: 16),
                    textAlign: TextAlign.center),
                const SizedBox(height: 2),
                Text('${L.historyOrdersN(ordersN)} · ${dayTotal.rub}',
                    style: T.priceSmall.copyWith(color: AppTheme.ink2)),
              ],
            ),
          ),
          _navBtn(Icons.chevron_right, L.laterDay, canLater ? _goLater : null),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, String tooltip, VoidCallback? onTap) {
    final enabled = onTap != null;
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon,
          size: 26,
          color: enabled ? AppTheme.ink : AppTheme.separator),
    );
  }

  Widget _body(TableHistoryResult? data) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 44, color: AppTheme.separator),
            const SizedBox(height: 12),
            Text(L.couldNotLoad, style: T.bodySemi),
            const SizedBox(height: 12),
            AppButton(
                label: L.retry,
                kind: ButtonKind.secondary,
                onPressed: () => _load(date: _data?.date)),
          ],
        ),
      );
    }
    if (data == null || data.dates.isEmpty) {
      return Center(
          child: Text(L.historyEmpty,
              style: T.body.copyWith(color: AppTheme.ink2)));
    }
    if (data.orders.isEmpty) {
      return Center(
          child: Text(L.historyEmptyDay,
              style: T.body.copyWith(color: AppTheme.ink2)));
    }
    return ListView.separated(
      itemCount: data.orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _historyCard(data.orders[i]),
    );
  }

  Widget _historyCard(CafeOrder order) {
    final delivered = order.status == OrderStatus.completed;
    final statusColor = switch (order.status) {
      OrderStatus.completed => AppTheme.success,
      OrderStatus.ready => AppTheme.success,
      OrderStatus.cooking => AppTheme.warning,
      OrderStatus.accepted => AppTheme.ink2,
      OrderStatus.awaiting => AppTheme.warning,
    };
    final ts = order.createdAt;
    final hhmm =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final total = order.items.fold(0.0, (s, l) => s + l.total);

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(delivered ? Icons.check_circle : Icons.schedule,
              size: 15, color: statusColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text('#${order.id} · $hhmm',
                style: T.priceSmall.copyWith(color: AppTheme.ink2)),
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 18),
            color: AppTheme.ink2,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            tooltip: L.activity,
            onPressed: () =>
                showOrderActivitySheet(context, order.id, '#${order.id}'),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(orderStatusLabel(order.status),
                style: T.label
                    .copyWith(color: statusColor, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 8),
        ...order.items.map((l) {
          final lineDone = l.done;
          final lineReady = l.ready;
          final lineColor =
              lineDone || lineReady ? AppTheme.success : AppTheme.ink2;
          final lineStatus = lineDone
              ? L.itemDelivered
              : lineReady
                  ? L.itemReady
                  : L.inPreparation;
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Column(children: [
              Row(children: [
                Text('${l.quantity}× ',
                    style: T.priceSmall.copyWith(fontWeight: FontWeight.w700)),
                Expanded(
                  child: Text(l.item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.priceSmall.copyWith(
                          color: lineDone ? AppTheme.ink2 : AppTheme.ink,
                          decoration:
                              lineDone ? TextDecoration.lineThrough : null)),
                ),
                Text(l.total.rub,
                    style: T.priceSmall.copyWith(color: AppTheme.ink2)),
              ]),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(lineStatus,
                    style: T.label.copyWith(
                        color: lineColor, fontWeight: FontWeight.w800)),
              ),
            ]),
          );
        }),
        const Divider(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(L.total, style: T.bodySemi),
            Text(total.rub,
                style: T.bodySemi.copyWith(color: AppTheme.cta)),
          ],
        ),
      ]),
    );
  }

  /// "Today" / "Yesterday" for the two most recent days, else dd.MM.yyyy.
  String _dayLabel(String? iso) {
    if (iso == null) return '—';
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final d = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return L.today;
    if (diff == 1) return L.yesterday;
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }
}
