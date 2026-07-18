// This file is only reached through the conditional import for web, where
// dart:html is legitimate; the Notification/visibility surfaces it uses have
// no drop-in replacement worth a full package:web migration yet.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'js_util_compat.dart' as js_util;

import 'package:flutter/foundation.dart';

import 'alert_platform.dart';

/// Browser implementation. Audio, push and wake-lock go through js_util
/// (dynamic JS interop — stable across browser API generations); only the
/// long-stable Notification / visibility / vibrate surfaces use dart:html.
class WebAlertPlatform implements AlertPlatform {
  Object? _audioContext; // JS AudioContext, created inside the unlock gesture
  Object? _wakeLockSentinel;

  // The push worker is registered by index.html on this scope, next to
  // Flutter's own service worker (which keeps the default scope).
  static const _pushScope = 'push-scope/';

  // Two quick notes per event type, all in the 2–4 kHz band.
  static const _tones = <AlertTone, (double, double)>{
    AlertTone.call: (2600, 3100),
    AlertTone.order: (2100, 2600),
    AlertTone.ready: (3100, 3500),
  };

  bool get _notificationsGranted => html.Notification.permission == 'granted';

  // --- unlock -----------------------------------------------------------------

  @override
  Future<bool> unlock() async {
    // 1ms vibration inside the gesture unlocks vibration where it exists;
    // iOS Safari has no navigator.vibrate — feature-detect, stay silent.
    try {
      if (js_util.hasProperty(html.window.navigator, 'vibrate')) {
        js_util.callMethod(html.window.navigator, 'vibrate', const [1]);
      }
    } catch (_) {}

    // Creating + resuming the AudioContext inside the tap unlocks WebAudio.
    try {
      _audioContext ??= js_util.callConstructor(
          js_util.getProperty(html.window, 'AudioContext') ??
              js_util.getProperty(html.window, 'webkitAudioContext'),
          const []);
      await js_util.promiseToFuture<void>(
          js_util.callMethod(_audioContext!, 'resume', const []));
      _beep(1000, 0, 0.01, 0.0001); // effectively silent, completes the unlock
    } catch (error) {
      debugPrint('audio unlock failed: $error');
    }

    try {
      final permission = await html.Notification.requestPermission();
      return permission == 'granted';
    } catch (error) {
      debugPrint('notification permission failed: $error');
      return false;
    }
  }

  // --- tones ------------------------------------------------------------------

  void _beep(double frequency, double delay, double duration, double volume) {
    final context = _audioContext;
    if (context == null) return;
    final oscillator = js_util.callMethod(context, 'createOscillator', const []);
    final gain = js_util.callMethod(context, 'createGain', const []);
    final now =
        (js_util.getProperty(context, 'currentTime') as num?)?.toDouble() ?? 0;
    final start = now + delay;

    js_util.setProperty(oscillator, 'type', 'sine');
    js_util.callMethod(
        js_util.getProperty(oscillator, 'frequency'), 'setValueAtTime',
        [frequency, start]);
    final gainParam = js_util.getProperty(gain, 'gain');
    js_util.callMethod(gainParam, 'setValueAtTime', [0.0001, start]);
    js_util.callMethod(
        gainParam, 'linearRampToValueAtTime', [volume, start + 0.02]);
    js_util.callMethod(
        gainParam, 'exponentialRampToValueAtTime', [0.0001, start + duration]);

    js_util.callMethod(oscillator, 'connect', [gain]);
    js_util.callMethod(
        gain, 'connect', [js_util.getProperty(context, 'destination')]);
    js_util.callMethod(oscillator, 'start', [start]);
    js_util.callMethod(oscillator, 'stop', [start + duration + 0.02]);
  }

  @override
  void playTone(AlertTone tone, double volume) {
    if (volume <= 0) return;
    final notes = _tones[tone]!;
    // A short two-note chime (~0.28s total) — calm but cuts through noise.
    _beep(notes.$1, 0, 0.13, volume.clamp(0.0, 1.0));
    _beep(notes.$2, 0.15, 0.13, volume.clamp(0.0, 1.0));
  }

  @override
  void vibrate(List<int> pattern) {
    try {
      if (js_util.hasProperty(html.window.navigator, 'vibrate')) {
        js_util.callMethod(html.window.navigator, 'vibrate', [pattern]);
      }
    } catch (_) {}
  }

  // --- visibility -------------------------------------------------------------

  @override
  bool get appVisible => html.document.visibilityState == 'visible';

  @override
  void onVisibilityChange(void Function(bool visible) handler) {
    html.document.onVisibilityChange.listen((_) => handler(appVisible));
  }

  // --- OS banners -------------------------------------------------------------

  Future<Object?> _pushRegistration() async {
    try {
      final container =
          js_util.getProperty(html.window.navigator, 'serviceWorker');
      if (container == null) return null;
      var registration = await js_util.promiseToFuture<Object?>(
          js_util.callMethod(container, 'getRegistration', [_pushScope]));
      // index.html registers the worker; re-register here as a fallback so a
      // hard-refreshed tab can still subscribe (idempotent by scope).
      registration ??= await js_util.promiseToFuture<Object?>(js_util.callMethod(
          container,
          'register',
          ['push_sw.js', js_util.jsify({'scope': _pushScope})]));
      return registration;
    } catch (error) {
      debugPrint('push registration lookup failed: $error');
      return null;
    }
  }

  @override
  void showOsBanner(
      {required String tag, required String title, required String body}) {
    if (!_notificationsGranted) return;
    () async {
      final registration = await _pushRegistration();
      try {
        if (registration != null) {
          await js_util.promiseToFuture<void>(js_util.callMethod(
              registration, 'showNotification', [
            title,
            js_util.jsify({
              'body': body,
              'tag': tag, // same signal replaces its banner, never stacks
              'icon': 'icons/Icon-192.png',
              'data': {'tag': tag},
            })
          ]));
          return;
        }
      } catch (error) {
        debugPrint('sw banner failed, falling back: $error');
      }
      try {
        html.Notification(title, body: body, tag: tag);
      } catch (_) {}
    }();
  }

  @override
  void closeOsBanner(String tag) {
    () async {
      final registration = await _pushRegistration();
      if (registration == null) return;
      try {
        final list = await js_util.promiseToFuture<List<dynamic>>(
            js_util.callMethod(registration, 'getNotifications', [
          js_util.jsify({'tag': tag})
        ]));
        for (final notification in list) {
          js_util.callMethod(notification as Object, 'close', const []);
        }
      } catch (error) {
        debugPrint('closing banner failed: $error');
      }
    }();
  }

  // --- Web Push ---------------------------------------------------------------

  static Uint8List _base64UrlToBytes(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return Uint8List.fromList(base64Decode(normalized));
  }

  @override
  Future<PushSubscriptionInfo?> subscribePush(String vapidPublicKey) async {
    if (vapidPublicKey.isEmpty || !_notificationsGranted) return null;
    final registration = await _pushRegistration();
    if (registration == null) return null;
    try {
      final pushManager = js_util.getProperty(registration, 'pushManager');
      if (pushManager == null) return null;
      final subscription = await js_util.promiseToFuture<Object?>(
          js_util.callMethod(pushManager, 'subscribe', [
        js_util.jsify({
          'userVisibleOnly': true,
          'applicationServerKey': _base64UrlToBytes(vapidPublicKey),
        })
      ]));
      if (subscription == null) return null;
      final json = js_util.dartify(
              js_util.callMethod(subscription, 'toJSON', const []))
          as Map<Object?, Object?>?;
      final keys = (json?['keys'] as Map<Object?, Object?>?) ?? const {};
      final endpoint = json?['endpoint']?.toString() ?? '';
      final p256dh = keys['p256dh']?.toString() ?? '';
      final auth = keys['auth']?.toString() ?? '';
      if (endpoint.isEmpty || p256dh.isEmpty || auth.isEmpty) return null;
      return PushSubscriptionInfo(endpoint: endpoint, p256dh: p256dh, auth: auth);
    } catch (error) {
      debugPrint('push subscribe failed: $error');
      return null;
    }
  }

  @override
  Future<String?> unsubscribePush() async {
    final registration = await _pushRegistration();
    if (registration == null) return null;
    try {
      final pushManager = js_util.getProperty(registration, 'pushManager');
      final subscription = await js_util.promiseToFuture<Object?>(
          js_util.callMethod(pushManager as Object, 'getSubscription', const []));
      if (subscription == null) return null;
      final endpoint =
          js_util.getProperty(subscription, 'endpoint')?.toString();
      await js_util.promiseToFuture<void>(
          js_util.callMethod(subscription, 'unsubscribe', const []));
      return endpoint;
    } catch (error) {
      debugPrint('push unsubscribe failed: $error');
      return null;
    }
  }

  // --- Wake Lock (station mode) ----------------------------------------------

  @override
  Future<void> acquireWakeLock() async {
    try {
      final wakeLock =
          js_util.getProperty(html.window.navigator, 'wakeLock');
      if (wakeLock == null) return; // unsupported — degrade silently
      _wakeLockSentinel = await js_util.promiseToFuture<Object?>(
          js_util.callMethod(wakeLock, 'request', ['screen']));
    } catch (error) {
      debugPrint('wake lock failed: $error');
    }
  }

  @override
  Future<void> releaseWakeLock() async {
    final sentinel = _wakeLockSentinel;
    _wakeLockSentinel = null;
    if (sentinel == null) return;
    try {
      await js_util.promiseToFuture<void>(
          js_util.callMethod(sentinel, 'release', const []));
    } catch (_) {}
  }
}

AlertPlatform createPlatform() => WebAlertPlatform();
