import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme/app_theme.dart';
import '../data/dtos.dart';
import '../models/models.dart';
import '../state/cafe_state.dart';

/// Bottom sheet showing an order's audit trail: who confirmed it, who pressed
/// "ready" on each station, who delivered, etc. Fetched on demand from the hub.
void showOrderActivitySheet(BuildContext context, String orderId, String title) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: const BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${L.activity} · $title', style: T.h2),
          const SizedBox(height: 16),
          Flexible(
            child: FutureBuilder<List<OrderEventDto>>(
              future: context.read<CafeState>().orderActivity(orderId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final events = snap.data ?? const [];
                if (events.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text(L.noActivity,
                            style: T.body.copyWith(color: AppTheme.ink2))),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) => _EventRow(event: events[i]),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final OrderEventDto event;

  @override
  Widget build(BuildContext context) {
    final ts = DateTime.tryParse(event.createdAt)?.toLocal();
    final hhmm = ts == null
        ? ''
        : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final who = event.actor.isEmpty ? '—' : event.actor;
    final detail = event.detail.isEmpty ? '' : ' · ${event.detail}';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.success),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who,
              style: T.bodySemi.copyWith(fontWeight: FontWeight.w800)),
          Text('${orderEventLabel(event.action)}$detail',
              style: T.small.copyWith(color: AppTheme.ink2)),
        ]),
      ),
      Text(hhmm, style: T.priceSmall.copyWith(color: AppTheme.ink3)),
    ]);
  }
}
