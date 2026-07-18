/// Platform glue for the staff alert system.
///
/// The staff app ships primarily as a web PWA (served at /staff/) and also
/// builds to Android. All browser-only machinery — Notification permission,
/// WebAudio tones, `navigator.vibrate`, Web Push subscribe, Wake Lock,
/// visibility — lives behind this interface with a conditional import, so
/// the Android/iOS build compiles without dart:html and degrades to haptics.
///
/// Platform truth (also surfaced in Settings): Android Chrome delivers push
/// with the phone locked; iOS needs 16.4+ AND the PWA added to the Home
/// Screen; `navigator.vibrate` never works on iOS Safari — every capability
/// here is feature-detected and degrades silently.
library;

import 'alert_platform_stub.dart'
    if (dart.library.html) 'alert_platform_web.dart' as impl;

/// Distinct short tones per event type, all in the 2–4 kHz band a loud
/// venue still lets through. Two quick notes each — a chime, never a siren.
enum AlertTone { call, order, ready }

/// A Web-Push subscription in wire form (what the hub stores).
class PushSubscriptionInfo {
  final String endpoint;
  final String p256dh;
  final String auth;
  const PushSubscriptionInfo({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });
}

abstract class AlertPlatform {
  /// One-gesture unlock, called from the "On shift" tap: ask notification
  /// permission, play a silent buffer (unlocks AudioContext) and vibrate 1ms
  /// (unlocks vibration on platforms that gate it). Returns true when OS
  /// notifications are permitted.
  Future<bool> unlock();

  /// Play one short two-note chime. [volume] 0..1.
  void playTone(AlertTone tone, double volume);

  /// Double-buzz (or any pattern). Silent no-op where unsupported (iOS).
  void vibrate(List<int> pattern);

  /// True when the app tab is visible — OS banners are suppressed then.
  bool get appVisible;

  /// Watch visibility so wake-lock and banners can react.
  void onVisibilityChange(void Function(bool visible) handler);

  /// Show/replace the OS banner for [tag]. No-ops without permission.
  void showOsBanner({required String tag, required String title, required String body});

  /// Close the OS banner(s) carrying [tag] — ack/cancel cleanup.
  void closeOsBanner(String tag);

  /// Subscribe this browser to Web Push via the push service worker.
  /// Returns null when unsupported/denied/unconfigured.
  Future<PushSubscriptionInfo?> subscribePush(String vapidPublicKey);

  /// Unsubscribe; returns the endpoint that was dropped (to tell the hub).
  Future<String?> unsubscribePush();

  /// Keep the screen awake (station mode). Safe to call repeatedly.
  Future<void> acquireWakeLock();
  Future<void> releaseWakeLock();
}

AlertPlatform createAlertPlatform() => impl.createPlatform();
