// Spec: specs/038-push-notifications-web-android/spec.md
//
// Web Push para iOS Safari — vía **Firebase JS SDK directo** (no
// via firebase_messaging plugin de Flutter, que falla con
// PlatformException(channel-error) en WebKit).
//
// Por qué:
// - `firebase_messaging` Flutter plugin → channel-error en iOS Safari.
// - `pushManager.subscribe` con VAPID propio + webpush-go → Apple
//   acepta el JWT (HTTP 201) pero NO entrega al iPhone. Subscripciones
//   "fantasma" o algún detalle sutil de encryption Apple-specific.
// - **Firebase JS SDK directo** → maneja todos los quirks de Apple
//   internamente. Es lo que NZT (React PWA) y Claude.ai usan y
//   funciona. El FCM token retornado se envía via FCM Admin SDK del
//   backend (que ya estaba configurado y funciona).
//
// Solo se usa cuando es iOS Safari. Resto de browsers (Chrome,
// Firefox, Android WebView) podrían usar firebase_messaging plugin
// directamente, pero acá lo unificamos a JS SDK también porque es
// más robusto cross-browser.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// VAPID public key del proyecto vendia-prod (Firebase Console →
/// Project Settings → Cloud Messaging → Web Push certificates).
/// Pública por diseño — el browser la pasa a `pushManager.subscribe`
/// vía Firebase JS SDK. La privada vive dentro de Firebase y la
/// usan ellos para firmar las Web Push messages al Apple Push
/// Service cuando enviamos vía Firebase Admin SDK.
const _firebaseVapidPublicKey =
    'BOvACmf7BcJhTd_BrFjsDZ6K1cnj0uK77MFSihwGTGqB1tNUjSxsciu3Z3FPGVZMFa3da19_qP3h5J9eIbfFOJc';

/// Token FCM + label para registrar en backend.
class WebPushSubscription {
  final String fcmToken;
  WebPushSubscription({required this.fcmToken});
}

class WebPushNative {
  WebPushNative._();
  static final WebPushNative instance = WebPushNative._();

  /// Detecta iOS Safari (cualquier browser en iPhone/iPad usa WebKit).
  static bool get isAppleSafari {
    if (!kIsWeb) return false;
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  String? _lastError;
  String? get lastError => _lastError;

  /// Pide permiso, registra el SW y obtiene un FCM token vía
  /// Firebase JS SDK. Retorna el token para mandarlo al backend.
  Future<WebPushSubscription?> requestSubscription() async {
    _lastError = null;
    try {
      // 1. Verificar que Firebase JS SDK está cargado (lo carga
      //    index.html antes de Flutter).
      final firebaseJS = web.window.getProperty<JSObject?>('firebase'.toJS);
      if (firebaseJS == null) {
        _lastError = 'Firebase JS SDK no está cargado en el navegador.';
        return null;
      }

      // 2. Pedir permiso de notificaciones al usuario.
      final permission = await _requestNotificationPermission();
      if (permission != 'granted') {
        _lastError = 'Permiso de notificaciones denegado (estado: $permission).';
        return null;
      }

      // 3. Registrar el SW (firebase-messaging-sw.js maneja eventos
      //    push de Firebase).
      final swContainer = web.window.navigator.serviceWorker;
      final regJS = await swContainer
          .register('/firebase-messaging-sw.js'.toJS)
          .toDart;
      await swContainer.ready.toDart;

      // 4. Obtener el FCM token vía Firebase Messaging JS SDK.
      //    `getToken({ vapidKey, serviceWorkerRegistration })` retorna
      //    un token estable que Firebase mapea internamente a la
      //    Web Push subscription. Firebase maneja TODOS los detalles
      //    de Apple Push Service por nosotros.
      final messaging = firebaseJS.callMethod<JSObject>('messaging'.toJS);

      final opts = JSObject();
      // VAPID public key generada en Firebase Console:
      // Project Settings → Cloud Messaging → Web Push certificates →
      // Generate key pair. Es DIFERENTE a la que webpush-go genera
      // localmente — Firebase tiene su propio par y solo expone la
      // pública. La privada queda dentro de Firebase, que firma
      // las Web Push automáticamente cuando enviamos via Admin SDK.
      opts['vapidKey'] = _firebaseVapidPublicKey.toJS;
      opts['serviceWorkerRegistration'] = regJS;

      final tokenPromise =
          messaging.callMethod<JSPromise>('getToken'.toJS, opts);
      final tokenJS = await tokenPromise.toDart;
      final token = (tokenJS as JSString?)?.toDart;

      if (token == null || token.isEmpty) {
        _lastError = 'Firebase no entregó FCM token (suscripción rechazada por el navegador).';
        return null;
      }

      return WebPushSubscription(fcmToken: token);
    } catch (e) {
      _lastError = 'Error al obtener FCM token: $e';
      debugPrint('[WEBPUSH] Firebase getToken failed: $e');
      return null;
    }
  }

  Future<String> _requestNotificationPermission() async {
    final notif = web.window.getProperty<JSObject?>('Notification'.toJS);
    if (notif == null) return 'denied';
    final reqPromise = notif.callMethod<JSPromise>('requestPermission'.toJS);
    final result = await reqPromise.toDart;
    return (result as JSString).toDart;
  }
}
