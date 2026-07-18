import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/alerts/alert_platform.dart';
import '../../core/alerts/alert_service.dart';
import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../state/cafe_state.dart';

/// Station mode: the "on shift" idle screen for a counter/pass tablet.
/// A dark clock, kept alive with a Wake Lock; on an alert the screen glows
/// softly (~1 Hz breathing, never a strobe) in the venue accent and shows a
/// huge table number. Tapping opens the relevant screen.
class StationModeScreen extends StatefulWidget {
  const StationModeScreen({super.key});
  @override
  State<StationModeScreen> createState() => _StationModeScreenState();
}

class _StationModeScreenState extends State<StationModeScreen>
    with SingleTickerProviderStateMixin {
  Timer? _clock;
  late final AnimationController _glow;
  late final AlertPlatform _platform; // captured: context is gone in dispose()

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _glow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true); // the soft ~1 Hz breathing
    _platform = context.read<CafeState>().alertPlatform;
    _platform.acquireWakeLock();
    // The browser drops wake locks when the tab hides — re-acquire on return.
    _platform.onVisibilityChange((visible) {
      if (visible && mounted) _platform.acquireWakeLock();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _glow.dispose();
    // Fire-and-forget: releasing must not block navigation.
    _platform.releaseWakeLock();
    super.dispose();
  }

  void _open(ActiveAlert? alert) {
    final state = context.read<CafeState>();
    final router = GoRouter.of(context);
    router.pop(); // leave station mode first
    if (alert == null) return;
    final table =
        state.tables.firstWhereOrNull((t) => t.number == alert.tableNumber);
    if (table != null) {
      state.currentTable = table;
      state.refresh();
      router.push('/table-details');
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final alerts = state.alertService.active
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final alert = alerts.firstOrNull; // oldest unhandled first
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.espresso,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(alert),
        child: AnimatedBuilder(
          animation: _glow,
          builder: (context, _) {
            final glowStrength =
                alert == null ? 0.0 : 0.10 + 0.16 * _glow.value;
            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: alert == null
                    ? null
                    : RadialGradient(
                        radius: 1.1,
                        colors: [
                          AppColors.gold.withValues(alpha: glowStrength),
                          AppColors.espresso,
                        ],
                      ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${_two(now.hour)}:${_two(now.minute)}',
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 96,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.isOnShift ? L.onShift : L.offShift,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    if (alert != null) ...[
                      const SizedBox(height: 42),
                      Text(
                        L.tableN(alert.tableNumber),
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        switch (alert.kind) {
                          AlertKind.call => L.guestCalling,
                          AlertKind.bill => L.guestBill,
                          AlertKind.order => L.guestOrder,
                        },
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        L.tapToOpen,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
