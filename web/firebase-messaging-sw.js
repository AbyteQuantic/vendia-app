// Spec: specs/038-push-notifications-web-android/spec.md
//
// Service Worker de Firebase Cloud Messaging para Web Push.
// Independiente de `flutter_service_worker.js` (la PWA shell de Flutter)
// — viven en paths distintos y no se pisan. `flutter build web` NO
// toca este archivo (verificable en CI).
//
// IMPORTANTE — los `apiKey/projectId/...` quedan en blanco hasta que
// Bryan corra `flutterfire configure` y obtenga la config web. Ese
// paso reemplaza ESTE archivo también (flutterfire detecta el SW y
// puebla las constantes). Mientras tanto el SW no se registra y la
// app degrada en silencio.

importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

// Valores reales del proyecto vendia-prod (generados por
// `flutterfire configure` el 2026-05-28). Coinciden con
// lib/firebase_options.dart → DefaultFirebaseOptions.web.
firebase.initializeApp({
  apiKey: 'AIzaSyABFUzX-6VH2gSFg7myzj5mT-fECGJ0OMw',
  authDomain: 'vendia-prod.firebaseapp.com',
  projectId: 'vendia-prod',
  storageBucket: 'vendia-prod.firebasestorage.app',
  messagingSenderId: '43323748804',
  appId: '1:43323748804:web:e787bb056c40b70eccb491',
});

const messaging = firebase.messaging();

// Background handler para mensajes vía Firebase Cloud Messaging
// (Chrome, Firefox, Edge, Android). Firebase ya decripta y nos pasa
// `payload.notification` + `payload.data`.
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};

  const title = notification.title || 'VendIA';
  const options = {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: {
      deep_link: data.deep_link || '',
    },
  };
  self.registration.showNotification(title, options);
});

// Spec 038 — Web Push protocol nativo (RFC 8030) para iOS Safari.
// El backend Go con webpush-go envía un payload JSON plano:
// { title, body, deep_link }. firebase-messaging-compat NO maneja
// este evento; lo hacemos manualmente.
//
// Detección anti-doble: si el payload viene con campo `notification`
// es FCM (ya manejado por messaging.onBackgroundMessage), no
// duplicamos. Web Push nativo viene plano sin `notification`.
self.addEventListener('push', (event) => {
  if (!event.data) return;
  let payload = {};
  try {
    payload = event.data.json();
  } catch (_) {
    payload = { title: 'VendIA', body: event.data.text() };
  }
  if (payload.notification) return; // ya manejado por FCM handler
  const title = payload.title || 'VendIA';
  const options = {
    body: payload.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { deep_link: payload.deep_link || '' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

// Tap en la notificación: si trae `deep_link`, abrir o enfocar la
// PWA en esa ruta. Si ya hay una ventana abierta, la enfocamos en vez
// de abrir otra (mejor UX).
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const deepLink = (event.notification.data && event.notification.data.deep_link) || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((windowClients) => {
        for (const client of windowClients) {
          if ('focus' in client) {
            client.postMessage({ type: 'push-deep-link', deepLink });
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow(deepLink);
        }
      })
  );
});
