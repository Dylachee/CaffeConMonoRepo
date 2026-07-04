import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

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
    final lines = state.tableCart(table.id);
    final total = lines.fold(0.0, (sum, l) => sum + l.total);

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
                    Text('Стол ${table.number}',
                        style: T.screenTitle),
                    Text(_tableSubtitle(table), style: T.subtitle),
                  ],
                ),
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
                Row(
                  children: [
                    Text('Заказ', style: T.sectionTitle),
                    const SizedBox(width: 10),
                    if (lines.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.ok.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${lines.where((l) => l.done).length}/${lines.length} отдано',
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
                if (lines.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long,
                              size: 48, color: AppTheme.separator),
                          const SizedBox(height: 16),
                          const Text('Чек пуст', style: T.bodySemi),
                          const SizedBox(height: 16),
                          AppButton(
                              label: 'Добавить блюдо',
                              kind: ButtonKind.secondary,
                              onPressed: () =>
                                  GoRouter.of(context).push('/waiter-menu')),
                        ],
                      ),
                    ),
                  )
                else
                  // Unsent (draft) lines can be swiped away or deleted with
                  // the explicit button; sent lines are already on the
                  // kitchen/bar screens and can only be marked as delivered.
                  ...lines.map((l) => l.sent
                      ? _orderItemRow(context, state, table, l)
                      : Dismissible(
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
                if (lines.isNotEmpty) ...[
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ИТОГО',
                          style: T.h2),
                      Text(total.rub,
                          style: T.h2.copyWith(color: AppTheme.cta)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                      label: 'Очистить стол',
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
                              'Очистить стол ${table.number}?',
                              style: T.h2,
                            ),
                            content: const Text(
                              'Заказ будет удалён. Убедитесь, что оплата прошла в кассе.',
                              style: T.body,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Отмена'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.danger,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Да, очистить',
                                    style: T.bodySemi),
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
                      label: 'Сдача / Оплата',
                      icon: Icons.calculate,
                      kind: ButtonKind.ghost,
                      onPressed: () => _showChangeCalculator(context, total)),
                ],
                const SizedBox(height: 32),
                const SectionTitle('Заметки'),
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
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add, size: 14, color: AppTheme.ink2),
                              const SizedBox(width: 4),
                              Text('Добавить',
                                  style: T.priceSmall.copyWith(color: AppTheme.ink2))
                            ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const SectionTitle('Статус стола'),
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
                const SizedBox(height: 40),
              ],
            ),
          ),
          BlurBar(
            child: Row(
              children: [
                Expanded(
                    child: AppButton(
                        label: 'Добавить',
                        icon: Icons.add,
                        onPressed: () =>
                            GoRouter.of(context).push('/waiter-menu'))),
                const SizedBox(width: 12),
                Expanded(
                    child: AppButton(
                        label: 'Отправить',
                        icon: Icons.send,
                        color: AppTheme.warning,
                        onPressed: () => _sendUnsent(context, state, table))),
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

  /// Send everything not yet sent; kitchen/bar routing happens by station.
  /// Always answers with a snackbar — silence («нажал и ничего») is a bug.
  Future<void> _sendUnsent(
      BuildContext context, CafeState state, CafeTable table) async {
    final messenger = ScaffoldMessenger.of(context);
    final pending = state.tableCart(table.id).where((l) => !l.sent).toList();
    if (pending.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Нет новых позиций — всё уже отправлено')));
      return;
    }
    final kitchen = pending.where((l) => !l.isBar).fold(0, (s, l) => s + l.quantity);
    final bar = pending.where((l) => l.isBar).fold(0, (s, l) => s + l.quantity);
    final order = await state.submitOrder(tableId: table.id);
    if (!context.mounted) return;
    if (order != null) {
      messenger.showSnackBar(SnackBar(
          content: Text('Отправлено · Кухня $kitchen · Бар $bar'),
          backgroundColor: AppTheme.success));
    } else {
      messenger.showSnackBar(SnackBar(
          content: Text(state.backendError == null
              ? 'Не удалось отправить'
              : 'Не отправлено: ${state.backendError}'),
          backgroundColor: AppTheme.danger));
    }
  }

  /// Real header data instead of the hardcoded «Открыт 14:05 · Елена».
  String _tableSubtitle(CafeTable table) {
    final parts = <String>[];
    if (table.openedAt != null) {
      final t = table.openedAt!;
      parts.add(
          'Открыт ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
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
            child: Text('Гостей за столом',
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
        child: Icon(icon, size: 15, color: primary ? Colors.white : AppColors.ink),
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
        onLongPress: () => state.toggleItemDone(table, line),
        onTap: () => _showNotePresets(context, state, line),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => state.toggleItemDone(table, line),
              child: Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: line.done ? AppColors.ok : Colors.white,
                  border: Border.all(
                      color: line.done ? AppColors.ok : const Color(0xFFD8D3C7),
                      width: 2),
                ),
                child: line.done
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 9),
            Text('${line.quantity}×',
                style: AppTypography.mono(
                        size: 14,
                        weight: FontWeight.w700,
                        color: line.done ? AppColors.ink40 : AppColors.ink)
                    .copyWith(
                        decoration: line.done
                            ? TextDecoration.lineThrough
                            : null)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.item.name,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: line.done ? AppColors.ink40 : AppColors.ink,
                          decoration: line.done
                              ? TextDecoration.lineThrough
                              : null)),
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
                        child: Text('черновик — не отправлено',
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
                            const Icon(Icons.check, size: 10, color: AppColors.ok),
                            const SizedBox(width: 4),
                            Text('готово на ${isBar ? "баре" : "кухне"}',
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
                        ...notes.map(
                            (n) => _noteChip(n, () => state.removeItemNote(line, n))),
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 11, color: AppColors.amber),
            SizedBox(width: 3),
            Text('примечание',
                style: TextStyle(
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
    const presets = [
      'Без лука',
      'Без льда',
      'На соевом',
      'Остро',
      'Не остро',
      'Навынос',
      'Без сахара',
      'Хорошо прожарить'
    ];
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
            Text('${line.quantity}× ${line.item.name}', style: AppTypography.h3()),
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
              const Text('Новая заметка',
                  style: T.h2),
              const SizedBox(height: 16),
              AppTextField(
                  controller: noteController,
                  label: 'Текст заметки',
                  hint: 'Аллергия, ДР, VIP...'),
              const SizedBox(height: 20),
              AppButton(
                  label: 'Добавить',
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
                Text('Калькулятор сдачи',
                    style: T.h1.copyWith(fontSize: 22)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('К оплате:',
                        style: T.bodySemi.copyWith(fontSize: 16)),
                    Text(total.rub,
                        style: T.h2.copyWith(color: AppTheme.cta)),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: cashController,
                  label: 'Получено наличных',
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
                      Text('СДАЧА:',
                          style: T.label.copyWith(
                              fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      Text(change.rub,
                          style: T.h1.copyWith(
                              fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.success)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AppButton(
                    label: 'Готово', onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
