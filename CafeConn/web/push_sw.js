/**
 * CafeConnect staff push service worker.
 *
 * Lives NEXT TO Flutter's own generated service worker, never instead of it:
 * index.html registers this file with the narrower scope "push-scope/", so
 * Flutter's flutter_service_worker.js keeps controlling the app shell while
 * this worker only handles Web Push. (Push subscriptions hang off a
 * registration; they do not need fetch control.)
 *
 * Payload contract (see apps/core/push.py):
 *   { kind: "attention"|"order", action: "created"|"acked"|"handled"|"escalated",
 *     table: <number>, signalId|orderId: <id>, tag: "<kind>-<id>" }
 *
 * Tag semantics: one tag per signal/order — repeats REPLACE the banner,
 * "acked"/"handled" CLOSE it. Click focuses (or opens) /staff/.
 */

'use strict';

self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

function bannerText(payload) {
  var table = payload.table ? 'Table ' + payload.table + ' · Tavolo ' + payload.table : '';
  if (payload.kind === 'attention') {
    if (payload.signalType === 'bill_request') {
      return { title: '💶 Bill requested · Conto', body: table };
    }
    return { title: '🔔 Guest calling · Chiamata', body: table };
  }
  if (payload.kind === 'order') {
    return { title: '🧾 New guest order · Nuovo ordine', body: table };
  }
  return { title: 'CafeConnect', body: table };
}

self.addEventListener('push', function (event) {
  var payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (e) {
    payload = {};
  }
  var tag = payload.tag || 'cafeconnect';

  // The alert was handled (or the guest cancelled): close, never re-notify.
  if (payload.action === 'acked' || payload.action === 'handled') {
    event.waitUntil(
      self.registration.getNotifications({ tag: tag }).then(function (notifications) {
        notifications.forEach(function (notification) { notification.close(); });
      })
    );
    return;
  }

  var text = bannerText(payload);
  event.waitUntil(
    self.registration.showNotification(text.title, {
      body: text.body,
      tag: tag,                 // same id replaces, never stacks
      renotify: payload.action === 'escalated',
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      data: { url: '/staff/', tag: tag },
    })
  );
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var target = (event.notification.data && event.notification.data.url) || '/staff/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clients) {
      for (var i = 0; i < clients.length; i++) {
        // Any open staff tab: focus it — the app itself navigates via its
        // own alert state, no URL juggling needed.
        if (clients[i].url.indexOf('/staff') !== -1 && 'focus' in clients[i]) {
          return clients[i].focus();
        }
      }
      return self.clients.openWindow(target);
    })
  );
});
