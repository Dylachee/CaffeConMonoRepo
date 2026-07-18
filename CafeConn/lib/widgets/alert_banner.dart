import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/alerts/alert_service.dart';
import '../core/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../state/cafe_state.dart';

/// Compact footer action for starting/ending a shift. Managers choose the
/// areas they are covering; their previous selection is prefilled next time.
class ShiftFooterControl extends StatefulWidget {
  const ShiftFooterControl({super.key});
  @override
  State<ShiftFooterControl> createState() => _ShiftFooterControlState();
}

class _ShiftFooterControlState extends State<ShiftFooterControl> {
  bool _busy = false;

  Future<List<String>?> _pickAreas(CafeState state) async {
    final choices = <(String, String, IconData)>[
      if (state.capWait) ('floor', L.tables, Icons.table_restaurant_outlined),
      if (state.capBar) ('bar', L.bar, Icons.local_bar_outlined),
      if (state.capKitchen) ('kitchen', L.kitchen, Icons.soup_kitchen_outlined),
    ];
    if (choices.length == 1) return [choices.first.$1];
    final selected = <String>{
      ...(state.lastShiftAreas.isNotEmpty
          ? state.lastShiftAreas
          : choices.map((choice) => choice.$1)),
    }..removeWhere((area) => !choices.any((choice) => choice.$1 == area));
    return showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(L.t('Where are you working?', 'Dove lavori?'),
                    style: T.h2),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  L.t('Your previous selection is remembered.',
                      'La selezione precedente viene ricordata.'),
                  style: T.small.copyWith(color: AppTheme.ink2),
                ),
              ),
              const SizedBox(height: 12),
              for (final choice in choices)
                CheckboxListTile(
                  value: selected.contains(choice.$1),
                  onChanged: (value) => setSheetState(() {
                    value == true
                        ? selected.add(choice.$1)
                        : selected.remove(choice.$1);
                  }),
                  secondary: Icon(choice.$3, color: AppTheme.ink2),
                  title: Text(choice.$2, style: T.bodySemi),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, selected.toList()),
                  child: Text(L.onShift),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    final state = context.read<CafeState>();
    final areas = on ? await _pickAreas(state) : null;
    if (on && areas == null) return;
    setState(() => _busy = true);
    final error = await state.setOnShift(on, areas: areas);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final pulsing = state.alertService.active.any((alert) => alert.level >= 2);

    Widget bar = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: state.backendConnected && !_busy
            ? () => _toggle(!state.isOnShift)
            : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 104),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: state.isOnShift
                ? AppColors.ok.withValues(alpha: 0.10)
                : AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.separator),
          ),
          child: Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: state.isOnShift ? AppColors.ok : AppColors.free,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              state.isOnShift ? L.onShift : L.offShift,
              style: T.smallSemi.copyWith(
                  color: state.isOnShift ? AppColors.ok : AppTheme.ink2),
            ),
            const SizedBox(width: 8),
            if (_busy)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.expand_less_rounded, size: 18),
          ]),
        ),
      ),
    );

    if (pulsing) {
      // L2 accent pulse: a calm ~1 Hz breathing tint — never a strobe.
      bar = bar
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .tint(
              color: AppTheme.warning.withValues(alpha: 0.18),
              duration: 500.ms);
    }
    return bar;
  }
}

/// In-app alert banners (L1+): one card per unhandled guest event, newest
/// first, with the big Accept action. Lives above the shell's PageView.
class AlertBannerStack extends StatelessWidget {
  const AlertBannerStack({super.key});

  (IconData, Color, String) _styleFor(ActiveAlert alert) =>
      switch (alert.kind) {
        AlertKind.call => (
            Icons.pan_tool_rounded,
            AppTheme.warning,
            L.guestCalling
          ),
        AlertKind.bill => (
            Icons.receipt_long_rounded,
            AppColors.bill,
            L.guestBill
          ),
        AlertKind.order => (
            Icons.room_service_rounded,
            AppColors.kitchen,
            L.guestOrder
          ),
      };

  void _accept(BuildContext context, ActiveAlert alert) {
    final state = context.read<CafeState>();
    if (alert.kind == AlertKind.order) {
      // Handling a guest order = reviewing it: jump to the table, where the
      // pending-approval sheet lives. The alert resolves on confirm/reject.
      final table =
          state.tables.where((t) => t.number == alert.tableNumber).firstOrNull;
      if (table != null) {
        state.currentTable = table;
        state.refresh();
        GoRouter.of(context).push('/table-details');
      }
      return;
    }
    state.acceptAlert(alert);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final alerts = state.alertService.active
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final alert in alerts.take(3))
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (alert.level >= 3 || alert.escalatedShared)
                    ? AppTheme.danger
                    : _styleFor(alert).$2.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: const [AppTheme.shadowCard],
            ),
            child: Row(children: [
              Icon(_styleFor(alert).$1, color: _styleFor(alert).$2, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${L.tableN(alert.tableNumber)} · ${_styleFor(alert).$3}',
                          style: T.bodySemi,
                          maxLines: 2),
                      if (alert.level >= 3 || alert.escalatedShared)
                        Text(L.escalatedTag,
                            style: T.label.copyWith(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w900)),
                    ]),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _accept(context, alert),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cta,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(L.accept,
                        style: T.bodySemi.copyWith(color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2, end: 0),
      ],
    );
  }
}
