import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/pending_approval.dart';

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
    // The check has two parts: unsent DRAFT lines (still being composed) and
    // the real orders already sent to the kitchen/bar (live ready/delivered
    // state). Delivery acts on the real orders, never on the draft copies —
    // that disconnect was why "Delivered to guest" did nothing.
    final lines = state.tableCart(table.id);
    final drafts = lines.where((l) => !l.sent).toList();
    final tableOrders =
        state.orders.where((o) => o.tableId == table.id).toList();
    // Everything on this table's current visit that belongs in the order list:
    // still-active AND already-served orders. A served order must stay visible
    // until the table is cleared (the day-by-day history button is for past
    // days); only guest orders awaiting approval are handled elsewhere.
    final visitOrders =
        tableOrders.where((o) => o.status != OrderStatus.awaiting).toList();
    final orderItems = tableOrders.expand((o) => o.items).toList();
    final deliveredCount = orderItems.where((l) => l.done).length;
    final totalItems = orderItems.length;
    final total = orderItems.fold(0.0, (sum, l) => sum + l.total) +
        drafts.fold(0.0, (sum, l) => sum + l.total);
    // Coupon snapshots from the hub (redeemed against this visit's orders).
    final discountTotal =
        tableOrders.fold(0.0, (sum, o) => sum + o.discountAmount);
    final couponCodes = tableOrders
        .where((o) => o.couponCode.isNotEmpty)
        .map((o) => o.couponCode)
        .join(', ');
    final totalDue = (total - discountTotal) > 0 ? total - discountTotal : 0.0;

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
                    Text(L.tableN(table.number), style: T.screenTitle),
                    Text(_tableSubtitle(table), style: T.subtitle),
                  ],
                ),
              ),
              if (state.capWait &&
                  table.waiterId != null &&
                  table.waiterId != state.activeEmployeeId?.toString())
                IconButton(
                  tooltip: L.t('Take over table', 'Prendi in carico il tavolo'),
                  onPressed: () => _takeOver(context, state, table),
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
              StatusBadge(table.status, showLabel: true),
            ],
          ),
          if (table.attention != null) ...[
            const SizedBox(height: 14),
            AttentionBanner(
              attention: table.attention!,
              onAck: () => state.ackAttention(table),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                SectionTitle(L.tableStatus),
                const SizedBox(height: 10),
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
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(L.order, style: T.sectionTitle),
                    const SizedBox(width: 10),
                    if (totalItems > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.ok.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          L.served(deliveredCount, totalItems),
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
                // Guest orders on this table awaiting the waiter's approval —
                // approve/reject right here, not only from the Orders screen.
                TablePendingOrders(tableId: table.id),
                if (drafts.isEmpty && tableOrders.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long,
                              size: 48, color: AppTheme.separator),
                          const SizedBox(height: 16),
                          Text(L.checkEmpty, style: T.bodySemi),
                          const SizedBox(height: 16),
                          AppButton(
                              label: L.addItem,
                              kind: ButtonKind.secondary,
                              onPressed: () =>
                                  GoRouter.of(context).push('/waiter-menu')),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // Live orders (sent to kitchen/bar): per-item delivery +
                  // "deliver all ready". This is the waiter's real delivery
                  // surface, driven by server state, not by the draft copies.
                  if (visitOrders.isNotEmpty)
                    _ActiveDeliverySection(table: table),
                  // Draft (not-yet-sent) lines: still editable — swipe or the
                  // delete button removes them, tap opens note presets.
                  if (drafts.isNotEmpty) ...[
                    if (visitOrders.isNotEmpty) const SizedBox(height: 6),
                    ...drafts.map((l) => Dismissible(
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
                  ],
                ],
                if (totalItems > 0 || drafts.isNotEmpty) ...[
                  const Divider(height: 32),
                  if (discountTotal > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            couponCodes.isEmpty
                                ? L.discountLine
                                : '${L.discountLine} (${L.couponApplied(couponCodes)})',
                            style: T.bodySemi.copyWith(color: AppTheme.success),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('−${discountTotal.rub}',
                            style:
                                T.bodySemi.copyWith(color: AppTheme.success)),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(L.total, style: T.h2),
                      Text(totalDue.rub,
                          style: T.h2.copyWith(color: AppTheme.cta)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                      label: L.clearTable,
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
                              L.clearTableQ(table.number),
                              style: T.h2,
                            ),
                            content: Text(
                              L.clearTableWarn,
                              style: T.body,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(L.cancel),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.danger,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(L.yesClear, style: T.bodySemi),
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
                      label: L.changePayment,
                      icon: Icons.calculate,
                      kind: ButtonKind.ghost,
                      onPressed: () => _showChangeCalculator(context, total)),
                ],
                const SizedBox(height: 32),
                SectionTitle(L.notes),
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
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.add, size: 14, color: AppTheme.ink2),
                          const SizedBox(width: 4),
                          Text(L.add,
                              style:
                                  T.priceSmall.copyWith(color: AppTheme.ink2))
                        ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Single entry-point to the table's full day-by-day history
                // (replaces the old inline last-10 list).
                AppButton(
                    label: L.orderHistory,
                    icon: Icons.history,
                    kind: ButtonKind.ghost,
                    onPressed: () =>
                        GoRouter.of(context).push('/table-history')),
                const SizedBox(height: 40),
              ],
            ),
          ),
          BlurBar(
            child: Row(
              children: [
                Expanded(
                    child: AppButton(
                        label: L.add,
                        icon: Icons.add,
                        onPressed: () =>
                            GoRouter.of(context).push('/waiter-menu'))),
                const SizedBox(width: 12),
                Expanded(
                    child: AppButton(
                        label: L.send,
                        icon: Icons.send,
                        color: AppTheme.warning,
                        // Disabled while a send is in flight so it can't be
                        // double-tapped into duplicate orders.
                        onPressed: state.isSubmitting(table.id)
                            ? null
                            : () => _sendUnsent(context, state, table))),
                const SizedBox(width: 12),
                AppButton(
                    label: '',
                    icon: Icons.forward,
                    kind: ButtonKind.secondary,
                    onPressed: () => showForwardSheet(context, table)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _takeOver(
      BuildContext context, CafeState state, CafeTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(L.t('Take over this table?', 'Prendere in carico il tavolo?')),
        content: Text(L.t(
          'You will become the primary waiter. ${table.waiterName} will be notified.',
          'Diventerai il cameriere principale. ${table.waiterName} verrà avvisato.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L.t('Take over', 'Prendi in carico')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await state.takeOverTable(table);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? L.t('Table taken over', 'Tavolo preso in carico')),
      backgroundColor: error == null ? AppTheme.success : AppTheme.danger,
    ));
  }

  /// Send everything not yet sent; kitchen/bar routing happens by station.
  /// Always answers with a snackbar; silence after a tap is a bug.
  Future<void> _sendUnsent(
      BuildContext context, CafeState state, CafeTable table) async {
    final messenger = ScaffoldMessenger.of(context);
    final pending = state.tableCart(table.id).where((l) => !l.sent).toList();
    if (pending.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(L.noNewItems)));
      return;
    }
    final kitchen =
        pending.where((l) => !l.isBar).fold(0, (s, l) => s + l.quantity);
    final bar = pending.where((l) => l.isBar).fold(0, (s, l) => s + l.quantity);
    final order = await state.submitOrder(tableId: table.id);
    if (!context.mounted) return;
    if (order != null) {
      messenger.showSnackBar(SnackBar(
          content: Text(L.sentKitchenBar(kitchen, bar)),
          backgroundColor: AppTheme.success));
    } else {
      messenger.showSnackBar(SnackBar(
          content: Text(state.backendError == null
              ? L.couldNotSend
              : L.notSent(state.backendError!)),
          backgroundColor: AppTheme.danger));
    }
  }

  /// Real header data instead of a hardcoded opened-at/waiter line.
  String _tableSubtitle(CafeTable table) {
    final parts = <String>[];
    if (table.openedAt != null) {
      final t = table.openedAt!;
      parts.add(L.openedAt(
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
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
            child: Text(L.guestsAtTable,
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
        child:
            Icon(icon, size: 15, color: primary ? Colors.white : AppColors.ink),
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
        onTap: () => _showNotePresets(context, state, line),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Draft marker: unsent lines can't be delivered — they're still
            // being composed. Delivery lives on the live-order rows above.
            Container(
              width: 23,
              height: 23,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD8D3C7), width: 2),
              ),
              child: const Icon(Icons.edit_outlined,
                  size: 11, color: AppColors.ink40),
            ),
            const SizedBox(width: 9),
            Text('${line.quantity}×',
                style: AppTypography.mono(
                        size: 14,
                        weight: FontWeight.w700,
                        color: line.done ? AppColors.ink40 : AppColors.ink)
                    .copyWith(
                        decoration:
                            line.done ? TextDecoration.lineThrough : null)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.item.displayName,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: line.done ? AppColors.ink40 : AppColors.ink,
                          decoration:
                              line.done ? TextDecoration.lineThrough : null)),
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
                        child: Text(L.draftNotSent,
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
                            const Icon(Icons.check,
                                size: 10, color: AppColors.ok),
                            const SizedBox(width: 4),
                            Text(L.readyAt(isBar),
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
                        ...notes.map((n) =>
                            _noteChip(n, () => state.removeItemNote(line, n))),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 11, color: AppColors.amber),
            const SizedBox(width: 3),
            Text(L.note,
                style: const TextStyle(
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
    final presets = line.item.notePresets;
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
            Text('${line.quantity}× ${line.item.displayName}',
                style: AppTypography.h3()),
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
              Text(L.newNote, style: T.h2),
              const SizedBox(height: 16),
              AppTextField(
                  controller: noteController,
                  label: L.noteText,
                  hint: L.noteHint),
              const SizedBox(height: 20),
              AppButton(
                  label: L.add,
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
                Text(L.changeCalculator, style: T.h1.copyWith(fontSize: 22)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(L.toPay, style: T.bodySemi.copyWith(fontSize: 16)),
                    Text(total.rub, style: T.h2.copyWith(color: AppTheme.cta)),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: cashController,
                  label: L.cashReceived,
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
                      Text(L.change,
                          style: T.label.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                      Text(change.rub,
                          style: T.h1.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.success)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AppButton(
                    label: L.done, onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The waiter's order list for the current visit: every order on the table
/// (still-active AND already-served), with a per-item "Delivered" action and a
/// "Deliver all ready" button. Served orders stay here (struck-through) until
/// the table is cleared — they no longer vanish the moment they're delivered.
/// Every action goes through the item-level backend path
/// (toggleOrderItemDelivered), so the kitchen/bar and the guest tracker stay
/// in sync — a bar-only delivery no longer flips the kitchen items.
class _ActiveDeliverySection extends StatelessWidget {
  const _ActiveDeliverySection({required this.table});
  final CafeTable table;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final orders = state.orders
        .where((o) =>
            o.tableId == table.id &&
            // Pending guest orders live in the approval section, not here.
            o.status != OrderStatus.awaiting)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (orders.isEmpty) return const SizedBox.shrink();
    final readyN = state.readyToDeliverCount(table.id);
    // Only offer the deliver action while something is still undelivered; once
    // the whole visit is served the cards remain but the button drops away.
    final hasUndelivered = orders.any((o) => o.status != OrderStatus.completed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...orders.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _orderCard(context, state, o),
            )),
        if (hasUndelivered)
          AppButton(
            label: readyN > 0 ? L.deliverAllReadyN(readyN) : L.nothingReadyYet,
            icon: readyN > 0 ? Icons.done_all : null,
            kind: readyN > 0 ? ButtonKind.primary : ButtonKind.secondary,
            color: readyN > 0 ? AppColors.ok : null,
            onPressed: readyN > 0
                ? () => state.deliverAllReadyForTable(table.id)
                : null,
          ),
      ],
    );
  }

  Widget _orderCard(BuildContext context, CafeState state, CafeOrder order) {
    final isKitchen = order.splitTo == FeedType.kitchen;
    final zoneColor = isKitchen ? AppTheme.warning : AppTheme.bar;
    final statusColor = switch (order.status) {
      OrderStatus.completed => AppTheme.success,
      OrderStatus.ready => AppTheme.success,
      OrderStatus.cooking => AppTheme.warning,
      OrderStatus.accepted => AppTheme.ink2,
      OrderStatus.awaiting => AppTheme.warning,
    };
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: zoneColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(isKitchen ? L.kitchen : L.bar,
                style: T.label
                    .copyWith(color: zoneColor, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('#${order.id}',
                style: T.priceSmall.copyWith(color: AppTheme.ink2)),
          ),
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
        const SizedBox(height: 10),
        OrderNoteBox(note: order.note),
        ...order.items.map((l) => _deliverRow(context, state, order, l)),
      ]),
    );
  }

  Widget _deliverRow(
      BuildContext context, CafeState state, CafeOrder order, CartLine l) {
    final canDeliver = l.ready && !l.done;
    final statusText = l.done
        ? L.itemDelivered
        : l.ready
            ? L.itemReady
            : L.inPreparation;
    final statusColor = l.done || l.ready ? AppColors.ok : AppTheme.ink2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        GestureDetector(
          onTap: (canDeliver || l.done)
              ? () => state.toggleOrderItemDelivered(order, l)
              : null,
          child: Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: l.done ? AppColors.ok : Colors.white,
              border: Border.all(
                  color: l.done ? AppColors.ok : const Color(0xFFD8D3C7),
                  width: 2),
            ),
            child: l.done
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 9),
        Text('${l.quantity}×',
            style: AppTypography.mono(
                size: 14,
                weight: FontWeight.w700,
                color: l.done ? AppColors.ink40 : AppColors.ink)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.item.displayName,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: l.done ? AppColors.ink40 : AppColors.ink,
                      decoration: l.done ? TextDecoration.lineThrough : null)),
              if (l.modifiers.isNotEmpty)
                Text(l.modifiers,
                    style: T.label.copyWith(color: AppTheme.warning)),
              Text(statusText,
                  style: T.label.copyWith(
                      color: statusColor, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        // Item still cooking: let the waiter advance it to "ready" right from
        // the table, not only from the kitchen/bar feed.
        if (state.canDeliverOrders && !l.ready && !l.done)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.warning,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => state.markOrderItemReady(order, l),
            child: Text(L.markReady,
                style: T.label.copyWith(fontWeight: FontWeight.w900)),
          ),
        if (canDeliver)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.ok,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => state.toggleOrderItemDelivered(order, l),
            child: Text(L.markDelivered,
                style: T.label.copyWith(fontWeight: FontWeight.w900)),
          ),
        // Waiter/manager can remove a sent item (wrong order, guest changed
        // their mind). Stations can't — matches the backend permission.
        if (state.canDeliverOrders && !l.done)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppTheme.danger,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: L.deleteItem,
            onPressed: () => _confirmDeleteItem(context, state, order, l),
          ),
      ]),
    );
  }

  Future<void> _confirmDeleteItem(BuildContext context, CafeState state,
      CafeOrder order, CartLine l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(L.deleteItemQ(l.item.displayName), style: T.h2),
        content: Text(L.deleteItemWarn, style: T.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.yesDelete, style: T.bodySemi),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.deleteOrderItem(order, l);
    }
  }
}
