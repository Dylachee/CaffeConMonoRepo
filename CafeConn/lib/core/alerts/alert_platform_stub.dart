import 'package:flutter/services.dart';

import 'alert_platform.dart';

/// Non-web builds (Android APK): no Web Notifications / Web Push / WebAudio.
/// Alerts still work in-app — haptics via the system channel and the system
/// click sound as a minimal audible cue. Background push on native builds is
/// out of scope by design (Web Push VAPID only, no FCM/APNS SDKs).
class NativeAlertPlatform implements AlertPlatform {
  @override
  Future<bool> unlock() async {
    await HapticFeedback.selectionClick();
    return false; // no OS-banner permission concept here
  }

  @override
  void playTone(AlertTone tone, double volume) {
    if (volume <= 0) return;
    SystemSound.play(SystemSoundType.alert);
  }

  @override
  void vibrate(List<int> pattern) {
    HapticFeedback.heavyImpact();
  }

  @override
  bool get appVisible => true;

  @override
  void onVisibilityChange(void Function(bool visible) handler) {}

  @override
  void showOsBanner({required String tag, required String title, required String body}) {}

  @override
  void closeOsBanner(String tag) {}

  @override
  Future<PushSubscriptionInfo?> subscribePush(String vapidPublicKey) async => null;

  @override
  Future<String?> unsubscribePush() async => null;

  @override
  Future<void> acquireWakeLock() async {}

  @override
  Future<void> releaseWakeLock() async {}
}

AlertPlatform createPlatform() => NativeAlertPlatform();
