import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

class WaiterTableGridScreen extends StatefulWidget {
  const WaiterTableGridScreen({super.key});
  @override
  State<WaiterTableGridScreen> createState() => _WaiterTableGridScreenState();
}

class _WaiterTableGridScreenState extends State<WaiterTableGridScreen> {
  TableStatus? filter;
  String search = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final filtered = state.tables.where((t) {
      final okFilter = filter == null || t.status == filter;
      final okSearch = search.isEmpty || t.number.toString().contains(search);
      return okFilter && okSearch;
    }).toList();
    // Anything the waiter must not miss floats to the top: a guest call/bill
    // signal, a table waiting for the waiter, or a guest order pending approval.
    bool needsAttention(CafeTable t) =>
        t.attention != null ||
        t.status == TableStatus.waiting ||
        state.orders
            .any((o) => o.tableId == t.id && o.status == OrderStatus.awaiting);
    filtered.sort((a, b) {
      final pa = needsAttention(a) ? 0 : 1;
      final pb = needsAttention(b) ? 0 : 1;
      return pa != pb ? pa - pb : a.number.compareTo(b.number);
    });

    return AppScaffold(
      bottomNav: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Header(
            title: L.tables,
            subtitle:
                '${L.hall} 1 · ${state.tables.where((t) => t.status != TableStatus.free).length} ${L.active} · ${state.tables.where((t) => t.status == TableStatus.free).length} ${L.free}',
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [AppTheme.shadowCard]),
                  child: const Icon(Icons.add, color: AppTheme.cta),
                ),
                onPressed: () => _showTableForm(context),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [AppTheme.shadowCard]),
                  child: const Icon(Icons.filter_list, color: AppTheme.ink),
                ),
                onPressed: () => _showStatusPicker(context),
              ),
            ],
          ),
          // Explicit demo/offline banner: without it the local seed data was
          // routinely mistaken for the real floor.
          if (!state.backendConnected) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => GoRouter.of(context).push('/settings'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 18, color: AppTheme.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.backendConnecting ? L.connecting : L.demoBanner,
                        style: T.smallSemi.copyWith(color: AppTheme.ink),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.ink2),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Guest orders waiting for the waiter to approve them before they
          // reach the kitchen/bar (self-hides when there are none).
          const PendingApprovalBanner(),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: InputDecoration(
                hintText: L.searchTable,
                prefixIcon: const Icon(Icons.search, color: AppTheme.ink3),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                CategoryChip(
                    label: L.all,
                    active: filter == null,
                    onTap: () => setState(() => filter = null)),
                ...TableStatus.values.map((s) => CategoryChip(
                      label: statusLabel(s),
                      active: filter == s,
                      onTap: () => setState(() => filter = s),
                      dotColor: statusColor(s),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.table_restaurant_outlined,
                    title: L.nothingFound,
                    sub: L.noTablesMatch)
                : RefreshIndicator(
                    color: AppTheme.cta,
                    onRefresh: () async => context.read<CafeState>().refresh(),
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: state.tablesPerRow,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.85),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final table = filtered[i];
                        return RepaintBoundary(
                          child: TableCard(
                            table: table,
                            index: i,
                            onTap: () {
                              state.currentTable = table;
                              GoRouter.of(context).push('/table-details');
                            },
                            onLongPress: () {
                              _showQuickCheck(context, table);
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showTableForm(BuildContext context, {CafeTable? table}) {
    final numController =
        TextEditingController(text: table?.number.toString() ?? '');
    Color selectedColor = table?.color ?? AppTheme.cta;

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
                Text(table == null ? L.newTable : L.editTable,
                    style: T.h1.copyWith(fontSize: 22)),
                const SizedBox(height: 20),
                AppTextField(
                    controller: numController,
                    label: L.tableNumber,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 24),
                Text(L.tagColor, style: T.label),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Colors.black,
                      Colors.brown,
                      Colors.blueGrey,
                      Colors.deepPurple,
                      Colors.indigo,
                      Colors.blue,
                      Colors.teal,
                      Colors.green,
                      Colors.orange,
                      Colors.red
                    ]
                        .map((c) => GestureDetector(
                              onTap: () =>
                                  setModalState(() => selectedColor = c),
                              child: Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: selectedColor == c
                                        ? Border.all(
                                            color: AppTheme.ink, width: 3)
                                        : null),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 32),
                AppButton(
                  label: table == null ? L.add : L.save,
                  onPressed: () {
                    final num = int.tryParse(numController.text);
                    if (num != null) {
                      if (table == null) {
                        context.read<CafeState>().addTable(num, selectedColor);
                      } else {
                        context
                            .read<CafeState>()
                            .editTable(table, num, selectedColor);
                      }
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showStatusPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L.filterByStatus, style: T.h2.copyWith(fontSize: 20)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                AppButton(
                    label: L.allTables,
                    kind: ButtonKind.secondary,
                    onPressed: () {
                      setState(() => filter = null);
                      Navigator.pop(context);
                    }),
                ...TableStatus.values.map((s) => AppButton(
                      label: statusLabel(s),
                      kind: ButtonKind.secondary,
                      onPressed: () {
                        setState(() => filter = s);
                        Navigator.pop(context);
                      },
                    )),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class TableCard extends StatefulWidget {
  const TableCard(
      {super.key,
      required this.table,
      required this.onTap,
      required this.onLongPress,
      this.index = 0});
  final CafeTable table;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final int index;

  @override
  State<TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<TableCard> {
  Timer? _holdTimer;
  bool _held = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final table = widget.table;
    final color = statusColor(table.status);
    final hasAttention = table.attention != null;
    final accent = hasAttention ? attentionColor(table.attention!) : color;
    final pillText = hasAttention
        ? attentionLabel(table.attention!)
        : statusLabel(table.status);
    final pulse = table.status == TableStatus.waiting || hasAttention;
    // colorTag bar only shows for a non-default (custom) tag color.
    final hasTag =
        table.color != AppColors.espresso && table.color != AppColors.ink;

    return GestureDetector(
      onTapDown: (_) {
        _held = false;
        _holdTimer = Timer(const Duration(milliseconds: 380), () {
          _held = true;
          HapticFeedback.mediumImpact();
          widget.onLongPress();
        });
      },
      onTapUp: (_) {
        _holdTimer?.cancel();
        if (!_held) {
          HapticFeedback.lightImpact();
          widget.onTap();
        }
      },
      onTapCancel: () {
        _holdTimer?.cancel();
        _held = false;
      },
      child: AppCard(
        index: widget.index,
        padding: const EdgeInsets.all(12),
        borderColor: hasAttention ? accent : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Guest-attention tint wash over the card surface.
            if (hasAttention)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            // 4px color-tag bar on the top edge.
            if (hasTag)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: table.color,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                ),
              ),
            // Status dot + 4px halo, top-right.
            Positioned(
              top: 0,
              right: 0,
              child: _HaloDot(accent, pulse: pulse),
            ),
            // Big mono table number + status/attention pill.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    table.number.toString().padLeft(2, '0'),
                    style: AppTypography.mono(
                        size: 30,
                        weight: FontWeight.w800,
                        color: AppColors.ink),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      pillText,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Order total (mono) or "free" at the bottom.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  table.status == TableStatus.free
                      ? L.freeLower
                      : state.tableDisplayTotal(table.id).rub,
                  style: table.status == TableStatus.free
                      ? AppTypography.label(color: AppColors.ink40)
                      : AppTypography.mono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.ink55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A status dot with a crisp 4px halo ring, matching the design's
/// `box-shadow: 0 0 0 4px <halo>`. Pulses while the table waits for a waiter
/// or has a guest-attention badge.
class _HaloDot extends StatelessWidget {
  const _HaloDot(this.color, {this.pulse = false});
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 0,
              spreadRadius: 4),
        ],
      ),
    );
    if (pulse) {
      // RepaintBoundary keeps this endless 60fps pulse from repainting the
      // whole table grid every frame — only the tiny dot layer redraws.
      dot = RepaintBoundary(
        child: dot
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(begin: 1.0, end: 1.18, duration: 800.ms),
      );
    }
    // Reserve room so the 4px halo isn't clipped against the card edge.
    return Padding(padding: const EdgeInsets.all(4), child: dot);
  }
}

void _showQuickCheck(BuildContext context, CafeTable table) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: L.close,
    barrierColor: const Color(0x8C0D0B08),
    transitionDuration: 300.ms,
    pageBuilder: (_, __, ___) => QuickCheckOverlay(table: table),
    transitionBuilder: (context, anim, __, child) => BackdropFilter(
      filter:
          ImageFilter.blur(sigmaX: 14 * anim.value, sigmaY: 14 * anim.value),
      child: ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
    ),
  );
}

class QuickCheckOverlay extends StatelessWidget {
  const QuickCheckOverlay({super.key, required this.table});
  final CafeTable table;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final items = state.tableDisplayLines(table.id);
    final total = items.fold(0.0, (s, l) => s + l.total);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [AppTheme.shadowSheet],
                ),
                child: Column(
                  children: [
                    Container(
                        height: 6,
                        decoration: BoxDecoration(
                            color: statusColor(table.status),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24)))),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(L.tableN(table.number),
                                  style: T.screenTitle),
                              const Spacer(),
                              StatusBadge(table.status, showLabel: true),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                              table.openedAt == null
                                  ? statusLabel(table.status)
                                  : '${L.openedAt('${table.openedAt!.hour.toString().padLeft(2, '0')}:${table.openedAt!.minute.toString().padLeft(2, '0')}')}${table.waiterName != '—' && table.waiterName.isNotEmpty ? ' · ${table.waiterName}' : ''}',
                              style: T.priceSmall),
                          const Divider(height: 32),
                          if (items.isEmpty)
                            Center(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 32),
                                    child: Text(L.checkEmpty, style: T.body)))
                          else
                            ...items.map((l) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Text('${l.quantity}×',
                                          style: T.timer
                                              .copyWith(color: AppTheme.ink2)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Text(l.item.displayName,
                                              style: T.body)),
                                      Text(l.total.rub, style: T.timer),
                                    ],
                                  ),
                                )),
                          const Divider(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(L.total, style: T.h2),
                              Text(total.rub,
                                  style: T.h2.copyWith(color: AppTheme.cta)),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                  child: GhostButton(
                                      label: L.forward,
                                      icon: Icons.forward,
                                      onTap: () =>
                                          showForwardSheet(context, table))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: PrimaryButton(
                                      label: L.open,
                                      icon: Icons.table_restaurant,
                                      onTap: () {
                                        Navigator.pop(context);
                                        state.currentTable = table;
                                        GoRouter.of(context)
                                            .push('/table-details');
                                      })),
                            ],
                          ),
                          if (table.status != TableStatus.free) ...[
                            const SizedBox(height: 10),
                            AppButton(
                              label: L.clearTable,
                              icon: Icons.cleaning_services,
                              kind: ButtonKind.primary,
                              color: AppTheme.danger,
                              onPressed: () =>
                                  _confirmAndClearTable(context, state, table),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(L.tapToClose, style: T.priceSmall),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmAndClearTable(
    BuildContext context, CafeState state, CafeTable table) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(L.clearTableQ(table.number), style: T.h2),
      content: Text(L.clearTableWarn, style: T.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(L.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(L.yesClear, style: T.bodySemi),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    state.closeTable(table);
    Navigator.pop(context);
  }
}
