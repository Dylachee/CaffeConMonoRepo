import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alert_platform.dart';

/// What kind of guest event is alerting. `ready` is reserved for kitchen/bar
/// "order ready" chimes (tone only, no ladder).
enum AlertKind { call, bill, order }

/// One unhandled guest event this device is escalating.
class ActiveAlert {
  ActiveAlert({
    required this.id,
    required this.kind,
    required this.tableNumber,
    required this.startedAt,
  });

  /// Also the OS-banner tag — matches the backend push tags
  /// (`attention-<pk>` / `order-<pk>`) so web-push banners and in-app
  /// banners replace/close each other.
  final String id;
  final AlertKind kind;
  final int tableNumber;
  final DateTime startedAt;

  /// 1 = first chime, 2 = +25s unacked, 3 = +60s escalated.
  int level = 1;

  /// Set when ANY on-shift device (this one or another) reached L3 — the
  /// event is highlighted for everyone.
  bool escalatedShared = false;

  Timer? _l2Timer;
  Timer? _l3Timer;
  Timer? _repeatTimer;

  void _cancelTimers() {
    _l2Timer?.cancel();
    _l3Timer?.cancel();
    _repeatTimer?.cancel();
  }
}

/// The calm escalation ladder. L1: one short two-note chime + double buzz +
/// in-app banner (+ OS banner only when the tab is hidden). L2 (+25s): one
/// repeat + app-bar accent pulse. L3 (+60s): repeat every 20s and flag the
/// event server-side so every on-shift device highlights it. Deliberately
/// NEVER a continuous siren — repeats are single chimes, spaced out.
class AlertService extends ChangeNotifier {
  AlertService({required this.platform});

  final AlertPlatform platform;

  static const _l2Delay = Duration(seconds: 25);
  static const _l3Delay = Duration(seconds: 60);
  static const _l3Repeat = Duration(seconds: 20);

  /// Wired by CafeState: alerts fire only on on-shift devices outside quiet
  /// mode; volume is the per-device slider.
  bool Function() isEnabled = () => false;
  double Function() volume = () => 0.6;

  /// Reaching L3 locally flags the event server-side (idempotent endpoint) —
  /// fire and forget, errors logged by the caller.
  Future<void> Function(ActiveAlert alert)? onEscalate;

  /// i18n strings for the OS banner, provided by the caller (the service
  /// stays free of UI/i18n imports).
  (String, String) Function(ActiveAlert alert) osBannerText =
      (alert) => ('CafeConnect', 'Table ${alert.tableNumber}');

  final Map<String, ActiveAlert> _alerts = {};

  List<ActiveAlert> get active => _alerts.values.toList(growable: false);
  bool get hasActive => _alerts.isNotEmpty;
  bool get hasEscalated =>
      _alerts.values.any((alert) => alert.level >= 3 || alert.escalatedShared);

  AlertTone _toneFor(AlertKind kind) => switch (kind) {
        AlertKind.call => AlertTone.call,
        AlertKind.bill => AlertTone.call,
        AlertKind.order => AlertTone.order,
      };

  void _fire(ActiveAlert alert, {bool banner = true}) {
    if (!isEnabled()) return; // quiet mode / shift-off mid-ladder: stay silent
    platform.playTone(_toneFor(alert.kind), volume());
    platform.vibrate(const [120, 90, 120]); // double buzz, then silence
    if (banner && !platform.appVisible) {
      final (title, body) = osBannerText(alert);
      platform.showOsBanner(tag: alert.id, title: title, body: body);
    }
  }

  /// Start (or refresh) the ladder for a guest event. Off-shift / quiet
  /// devices never even track it.
  void trigger({
    required String id,
    required AlertKind kind,
    required int tableNumber,
    bool escalatedShared = false,
  }) {
    if (!isEnabled()) return;
    final existing = _alerts[id];
    if (existing != null) {
      if (escalatedShared && !existing.escalatedShared) {
        existing.escalatedShared = true;
        notifyListeners();
      }
      return; // one ladder per signal id — never duplicate alarms
    }

    final alert = ActiveAlert(
      id: id,
      kind: kind,
      tableNumber: tableNumber,
      startedAt: DateTime.now(),
    )..escalatedShared = escalatedShared;
    _alerts[id] = alert;
    _fire(alert);

    alert._l2Timer = Timer(_l2Delay, () {
      if (!_alerts.containsKey(id)) return;
      alert.level = 2;
      _fire(alert); // one repeat; the app bar pulses via [hasActive]+level
      notifyListeners();
    });
    alert._l3Timer = Timer(_l3Delay, () {
      if (!_alerts.containsKey(id)) return;
      alert.level = 3;
      notifyListeners();
      final escalate = onEscalate;
      if (escalate != null) {
        escalate(alert).catchError((Object error) {
          debugPrint('escalate flag failed: $error');
        });
      }
      alert._repeatTimer = Timer.periodic(_l3Repeat, (_) {
        if (!isEnabled()) return;
        _fire(alert);
      });
    });
    notifyListeners();
  }

  /// Another device reached L3 first: highlight here too. Devices that were
  /// not tracking the event (came on shift late) join at level 3.
  void markEscalated({
    required String id,
    required AlertKind kind,
    required int tableNumber,
  }) {
    final existing = _alerts[id];
    if (existing != null) {
      existing.escalatedShared = true;
      notifyListeners();
      return;
    }
    trigger(
      id: id,
      kind: kind,
      tableNumber: tableNumber,
      escalatedShared: true,
    );
  }

  /// The event was handled anywhere (ack, confirm, guest cancel): stop
  /// everything for it on this device and close its OS banner.
  void resolve(String id) {
    final alert = _alerts.remove(id);
    if (alert == null) return;
    alert._cancelTimers();
    platform.closeOsBanner(id);
    notifyListeners();
  }

  /// Shift-off / logout: total silence, all banners closed.
  void silenceAll() {
    for (final alert in _alerts.values) {
      alert._cancelTimers();
      platform.closeOsBanner(alert.id);
    }
    _alerts.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    silenceAll();
    super.dispose();
  }
}
