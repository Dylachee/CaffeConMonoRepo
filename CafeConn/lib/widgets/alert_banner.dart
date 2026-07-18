import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/alerts/alert_service.dart';
import '../core/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../state/cafe_state.dart';

/// Compact one-tap footer action for starting or ending a shift.
class ShiftFooterControl extends StatefulWidget {
  const ShiftFooterControl({super.key, this.compact = false});
  final bool compact;
  @override
  State<ShiftFooterControl> createState() => _ShiftFooterControlState();
}

class _ShiftFooterControlState extends State<ShiftFooterControl> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    final state = context.read<CafeState>();
    setState(() => _busy = true);
    final error = await state.setOnShift(on);
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
          constraints:
              BoxConstraints(minHeight: 44, minWidth: widget.compact ? 44 : 78),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 11),
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
            if (!widget.compact) ...[
              const SizedBox(width: 8),
              Text(
                state.isOnShift ? L.t('On', 'On') : L.t('Off', 'Off'),
                style: T.smallSemi.copyWith(
                    color: state.isOnShift ? AppColors.ok : AppTheme.ink2),
              ),
            ],
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(left: 7),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
      ),
    );

    if (pulsing && !MediaQuery.disableAnimationsOf(context)) {
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
