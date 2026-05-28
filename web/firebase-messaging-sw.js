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

// REEMPLAZAR con los valores reales de Firebase Console → Web App.
// El stub deja vacío `apiKey` para que el SW falle el init y la app
// detecte que push no está configurado.
firebase.initializeApp({
  apiKey: '',
  authDomain: '',
  projectId: '',
  storageBucket: '',
  messagingSenderId: '',
  appId: '',
});

const messaging = firebase.messaging();

// Background handler: cuando la PWA NO está abierta (o está en
// otra pestaña), el browser entrega el push aquí. Mostramos la
// notificación nativa del OS con el título/cuerpo del payload.
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
