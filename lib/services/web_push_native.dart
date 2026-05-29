// Spec: specs/038-push-notifications-web-android/spec.md
//
// Web Push nativo (RFC 8030/8291) — bypassing firebase_messaging.
//
// Por qué este archivo existe:
// - `firebase_messaging` 15.x + Flutter web + iOS Safari (WebKit)
//   falla con `PlatformException(channel-error)` en `Firebase.
//   initializeApp` (verificado 2026-05-29, sin fix upstream).
// - iOS Safari (≥ 16.4 con PWA agregada a pantalla de inicio) SÍ
//   soporta el estándar Web Push API del browser. Llamamos directo
//   via `navigator.serviceWorker.pushManager.subscribe` sin Firebase
//   en el medio.
//
// El backend recibe `{endpoint, p256dh_key, auth_key}` en
// `POST /devices/register` y firma los mensajes con VAPID (usando
// `webpush-go`) en vez de Firebase Admin SDK.
//
// Solo se usa cuando `WebPushNative.isAppleSafari` es true. En el
// resto de browsers (Chrome, Firefox, Edge, Android WebView) el
// PushService usa firebase_messaging que sí funciona.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Pública VAPID (la privada vive en Render como env var
/// VAPID_PRIVATE_KEY del backend). Generada con `webpush-go`
/// el 2026-05-29 para el proyecto VendIA.
const _vapidPublicKey =
    'BBxsSNDTVvOcUSTi8kwCb48xum_qmQGt_uzqm8Nro8h_elfBjEjvzQfSx35zlgzi3k9h2uIl_ajuc-ox6I9wCHE';

/// Result del subscribe: el caller (PushService) lo manda al backend
/// vía `ApiService.registerDevice`.
class WebPushSubscription {
  final String endpoint;
  final String p256dhKey;
  final String authKey;
  WebPushSubscription({
    required this.endpoint,
    required this.p256dhKey,
    required this.authKey,
  });
}

class WebPushNative {
  WebPushNative._();
  static final WebPushNative instance = WebPushNative._();

  /// Detecta iOS Safari (cualquier browser en iPhone/iPad usa WebKit
  /// — Chrome iOS y Firefox iOS también). Es el caso donde
  /// firebase_messaging NO funciona y debemos usar Web Push nativo.
  static bool get isAppleSafari {
    if (!kIsWeb) return false;
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  /// Pide permiso al usuario y suscribe el browser al servicio Web Push.
  /// Retorna la suscripción para mandarla al backend, o `null` si:
  /// - El browser no soporta Push API.
  /// - El usuario rechazó el permiso.
  /// - El Service Worker no está registrado / falló.
  Future<WebPushSubscription?> requestSubscription() async {
    _lastError = null;
    try {
      // 1) Pedir permiso explícito al usuario.
      final permission = await _requestNotificationPermission();
      if (permission != 'granted') {
        _lastError = 'Permiso de notificaciones no concedido (estado: $permission).';
        return null;
      }

      // 2) Verificar Service Worker disponible.
      final swContainer = web.window.navigator.serviceWorker;
      if ((swContainer as JSObject?) == null) {
        _lastError = 'Este navegador no soporta Service Workers.';
        return null;
      }

      // 3) Registrar nuestro SW (firebase-messaging-sw.js ya existe
      //    para FCM; reusamos por simplicidad — el SW también maneja
      //    eventos `push` nativos del Web Push protocol).
      final regJS = await swContainer
          .register('/firebase-messaging-sw.js'.toJS)
          .toDart;
      final reg = regJS as JSObject;

      // 4) Esperar a que el SW esté ready (active worker).
      await swContainer.ready.toDart;

      // 5) Verificar Push Manager.
      final pushManager = reg['pushManager'] as JSObject?;
      if (pushManager == null) {
        _lastError = 'Push API no soportado en este navegador.';
        return null;
      }

      // 6) Subscribe — pasa la VAPID public key convertida a Uint8Array.
      final keyBytes = _urlBase64ToUint8Array(_vapidPublicKey);
      final opts = JSObject();
      opts['userVisibleOnly'] = true.toJS;
      opts['applicationServerKey'] = keyBytes;

      final subResult = pushManager
          .callMethod<JSPromise>('subscribe'.toJS, opts);
      final subJS = await subResult.toDart;
      final sub = subJS as JSObject;

      final endpoint = (sub['endpoint'] as JSString).toDart;
      final keys = sub.callMethod<JSAny>('toJSON'.toJS) as JSObject;
      final keysMap = keys['keys'] as JSObject;
      final p256dh = (keysMap['p256dh'] as JSString).toDart;
      final auth = (keysMap['auth'] as JSString).toDart;

      return WebPushSubscription(
        endpoint: endpoint,
        p256dhKey: p256dh,
        authKey: auth,
      );
    } catch (e) {
      _lastError = 'Error al suscribirse: $e';
      debugPrint('[WEBPUSH] subscribe failed: $e');
      return null;
    }
  }

  String? _lastError;
  String? get lastError => _lastError;

  Future<String> _requestNotificationPermission() async {
    final notif = web.window.getProperty<JSObject?>('Notification'.toJS);
    if (notif == null) return 'denied';
    final reqPromise = notif.callMethod<JSPromise>('requestPermission'.toJS);
    final result = await reqPromise.toDart;
    return (result as JSString).toDart;
  }

  /// Decode urlBase64 → Uint8Array — formato que `applicationServerKey`
  /// del Push API espera para la clave VAPID pública.
  JSUint8Array _urlBase64ToUint8Array(String base64String) {
    final padding = (4 - base64String.length % 4) % 4;
    var base64 = base64String + '=' * padding;
    base64 = base64.replaceAll('-', '+').replaceAll('_', '/');
    final atob =
        web.window.callMethod<JSString>('atob'.toJS, base64.toJS).toDart;

    final bytes = List<int>.generate(atob.length, (i) => atob.codeUnitAt(i));
    return _toUint8Array(bytes);
  }

  JSUint8Array _toUint8Array(List<int> bytes) {
    // Crear Uint8Array desde Dart vía JS interop.
    final ctor = web.window.getProperty<JSFunction>('Uint8Array'.toJS);
    final arr = ctor.callAsConstructor<JSObject>(bytes.length.toJS);
    for (var i = 0; i < bytes.length; i++) {
      arr.setProperty(i.toJS, bytes[i].toJS);
    }
    return arr as JSUint8Array;
  }
}
