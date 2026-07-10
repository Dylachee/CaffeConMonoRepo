import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../models/models.dart';
import '../state/cafe_state.dart';
import 'app_widgets.dart';

/// Amber "N guest orders to approve" banner. Shows only when there are pending
/// guest orders and the current user can approve them; tap opens the review
/// sheet. Reused on the Tables and Orders screens so a waiter sees it wherever
/// they are.
class PendingApprovalBanner extends StatelessWidget {
  const PendingApprovalBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final pending = state.pendingApprovalOrders;
    if (pending.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => showPendingApprovalSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_rounded,
                size: 18, color: AppTheme.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                L.pendingApprovalN(pending.length),
                style: T.smallSemi
                    .copyWith(color: AppTheme.ink, fontWeight: FontWeight.w800),
              ),
            ),
            Text(L.reviewOrder,
                style: T.smallSemi.copyWith(
                    color: AppTheme.warning, fontWeight: FontWeight.w800)),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.ink2),
          ]),
        ),
      ),
    );
  }
}

/// Inline pending-approval list for one table's detail screen: every guest
/// order on this table still awaiting the waiter, with the same approve/reject
/// card used in the review sheet. Self-hides when there's nothing pending.
class TablePendingOrders extends StatelessWidget {
  const TablePendingOrders({super.key, required this.tableId});
  final String tableId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final pending =
        state.pendingApprovalOrders.where((o) => o.tableId == tableId).toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.notifications_active_rounded,
              size: 16, color: AppTheme.warning),
          const SizedBox(width: 7),
          Text(L.pendingApproval,
              style: T.label.copyWith(
                  color: AppTheme.warning, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        ...pending.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _pendingOrderCard(context, state, o),
            )),
      ]),
    );
  }
}

String _hhmm(DateTime ts) =>
    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

/// The review sheet: every pending guest order with Send to kitchen & bar /
/// Reject actions. Rebuilds live as orders are approved/rejected.
void showPendingApprovalSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Consumer<CafeState>(
      builder: (context, state, _) {
        final pending = state.pendingApprovalOrders;
        return Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82),
          decoration: const BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.pendingApproval, style: T.h2),
                const SizedBox(height: 16),
                if (pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                        child: Text(L.noPendingOrders,
                            style: T.body.copyWith(color: AppTheme.ink2))),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: pending.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) =>
                          _pendingOrderCard(context, state, pending[i]),
                    ),
                  ),
              ]),
        );
      },
    ),
  );
}

Widget _pendingOrderCard(
    BuildContext context, CafeState state, CafeOrder order) {
  final matches = state.tables.where((t) => t.id == order.tableId);
  final title = matches.isEmpty
      ? '${L.guestOrder} · #${order.id}'
      : '${L.table} ${matches.first.number} · #${order.id}';
  return AppCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(title,
                style:
                    T.h3.copyWith(fontWeight: FontWeight.w800, fontSize: 15))),
        Text(_hhmm(order.createdAt),
            style: T.priceSmall.copyWith(color: AppTheme.ink2)),
      ]),
      const SizedBox(height: 8),
      OrderNoteBox(note: order.note),
      ...order.items.map((l) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Text('${l.quantity}× ',
                  style: AppTypography.mono(
                      size: 13, weight: FontWeight.w700, color: AppColors.ink)),
              Expanded(child: Text(l.item.displayName, style: T.body)),
              if (l.modifiers.isNotEmpty)
                Text(l.modifiers,
                    style: T.label.copyWith(color: AppTheme.warning)),
            ]),
          )),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: AppButton(
            label: L.sendToKitchenBar,
            icon: Icons.send_rounded,
            onPressed: () async {
              final err = await state.confirmGuestOrder(order);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err ?? L.orderApproved)));
            },
          ),
        ),
        const SizedBox(width: 10),
        AppButton(
          label: L.rejectOrder,
          kind: ButtonKind.ghost,
          color: AppTheme.danger,
          onPressed: () => _confirmReject(context, state, order),
        ),
      ]),
    ]),
  );
}

Future<void> _confirmReject(
    BuildContext context, CafeState state, CafeOrder order) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(L.rejectOrderQ, style: T.h2),
      content: Text(L.rejectOrderWarn, style: T.body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: Text(L.cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(L.rejectOrder, style: T.bodySemi),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    final err = await state.rejectGuestOrder(order);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? L.orderRejected)));
  }
}
