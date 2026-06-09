// Spec: specs/038-push-notifications-web-android/spec.md
//
// ignore_for_file: prefer_const_constructors
//
// PushService es el singleton que orquesta la integración con FCM en
// Flutter (Web + Android). Responsabilidades:
//
//   1. Init de Firebase Core con `DefaultFirebaseOptions.currentPlatform`
//      — pero solo cuando hay credenciales reales (stub → no-op).
//   2. Pedir permiso al sistema al ser invocado explícitamente desde
//      `PushOptinCard` (NUNCA al arranque — Art. I: el tendero ve
//      nuestra tarjeta primero y decide).
//   3. Obtener el token FCM y registrarlo contra
//      `POST /api/v1/devices/register`.
//   4. Escuchar `onTokenRefresh` y re-registrar.
//   5. Foreground listener (`onMessage`) → `flutter_local_notifications`
//      para que la push se vea aunque la app esté abierta (FR-14 / AC-14).
//   6. `onMessageOpenedApp` y `getInitialMessage` para deep link routing
//      (FR-08).
//
// IMPORTANTE — el servicio degrada en silencio cuando:
//   - `DefaultFirebaseOptions.isConfigured == false` (stub).
//   - El navegador no soporta Web Push (iOS Safari pre-16.4 sin PWA).
//   - El usuario rechaza el permiso (AC-03).
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'auth_service.dart';
// Import condicional: en web (con dart:js_interop) usa la implementación
// real; en VM de tests / móvil usa el stub no-op. Así push_service compila
// en todas las plataformas (lo expuso el consumo del catálogo F041 en tests).
import 'web_push_stub.dart'
    if (dart.library.js_interop) 'web_push_native.dart';

/// Callback que el `app.dart` registra para que un deep link entrante
/// navegue a la pantalla correcta. PushService solo sabe extraer la
/// ruta del payload; quién navega es responsabilidad de la app
/// (separación de capas: el servicio no importa `Navigator`).
typedef DeepLinkHandler = void Function(String deepLink);

class PushService {
  PushService._();
  static final PushService _instance = PushService._();
  factory PushService() => _instance;

  bool _initialized = false;
  bool _firebaseReady = false;
  /// Future del init en curso. `requestOptInAndRegister` lo `await`
  /// para resolver la race condition: el tendero puede tocar
  /// "Activar" antes de que el init de Firebase termine (sobre todo
  /// en iPhone Safari donde el primer init puede tardar 1-2s).
  Future<void>? _initFuture;
  /// Si `_doInit` falló, guardamos el mensaje crudo para mostrarlo
  /// al tendero (no en log invisible). Sin esto era imposible saber
  /// si el problema era VAPID, SW, permiso denegado o credenciales.
  String? _lastInitError;
  /// Si `requestOptInAndRegister` falló y no fue por init (Firebase
  /// listo pero permiso rechazado / getToken vacío / register al
  /// backend falló), guardamos la razón acá para el UI.
  String? _lastOptInError;
  DeepLinkHandler? _deepLinkHandler;

  String? get lastInitError => _lastInitError;
  String? get lastOptInError => _lastOptInError;

  static const _androidChannel = AndroidNotificationChannel(
    'vendia_default',
    'VendIA',
    description: 'Notificaciones de VendIA (pedidos, abonos, alertas)',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  /// Llamar UNA vez al arranque de la app, antes de runApp si es
  /// posible. NUNCA solicita permiso — eso lo hace `requestOptInAndRegister`.
  Future<void> init({DeepLinkHandler? onDeepLink}) async {
    if (_initialized) return _initFuture ?? Future.value();
    _initialized = true;
    _deepLinkHandler = onDeepLink;
    _initFuture = _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseReady = true;
      await _setupLocalNotifications();
      _wireMessageListeners();
      await _checkInitialMessage();
    } catch (e) {
      _lastInitError = e.toString();
      debugPrint('[PUSH] init failed (push queda inactivo): $e');
    }
  }

  /// `true` si la integración está viva y se puede pedir token.
  /// - En iPhone/iPad: siempre `true` (Web Push API estándar).
  /// - En otros browsers: solo si Firebase init OK.
  bool get isAvailable => WebPushNative.isAppleSafari || _firebaseReady;

  /// Implementación para iOS Safari — usa Firebase JS SDK directo
  /// (no via firebase_messaging plugin de Flutter que falla en
  /// WebKit). Obtiene un FCM token estándar que el backend envía
  /// vía Firebase Admin SDK como cualquier otro device.
  Future<bool> _registerWebPushNative() async {
    try {
      final sub = await WebPushNative.instance.requestSubscription();
      if (sub == null) {
        _lastOptInError = WebPushNative.instance.lastError ??
            'No se pudo suscribir al servicio de notificaciones.';
        return false;
      }

      final api = ApiService(AuthService());
      await api.registerDevice(
        platform: 'web_ios',
        token: sub.fcmToken, // ← ahora es un FCM token, no endpoint
        deviceLabel: 'iPhone Safari',
      );
      return true;
    } catch (e) {
      _lastOptInError = 'Error registrando el dispositivo iOS: $e';
      return false;
    }
  }

  /// Pide permiso al usuario (dispara el prompt nativo del navegador /
  /// OS) y, si el usuario acepta, obtiene + registra el token. Es lo
  /// que llama el botón "Activar notificaciones" del `PushOptinCard`.
  ///
  /// Retorna `true` si se obtuvo y registró un token (push activo);
  /// `false` si el permiso fue denegado o el flujo falló.
  Future<bool> requestOptInAndRegister() async {
    _lastOptInError = null;

    // En iPhone/iPad → Web Push nativo (RFC 8030). Saltamos Firebase
    // entero porque firebase_messaging falla con channel-error en
    // WebKit. Web Push API estándar del browser SÍ funciona.
    if (WebPushNative.isAppleSafari) {
      return _registerWebPushNative();
    }

    // Resto de browsers: el camino firebase_messaging (Chrome, Firefox,
    // Edge, Android WebView).
    if (_initFuture == null) {
      await init();
    } else {
      await _initFuture;
    }
    if (!_firebaseReady) {
      _lastOptInError =
          'Firebase no se pudo iniciar en este navegador. '
          '${_lastInitError ?? "Causa desconocida."}';
      return false;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        _lastOptInError =
            'El navegador no concedió el permiso de notificaciones '
            '(estado: ${settings.authorizationStatus.name}).';
        return false;
      }
      return await _fetchAndRegisterToken();
    } catch (e) {
      _lastOptInError = 'Error pidiendo el permiso: $e';
      return false;
    }
  }

  /// Llama `POST /api/v1/devices/register` con el token actual. Idempotente
  /// del lado backend — si ya existe, refresca `last_seen_at`.
  Future<bool> _fetchAndRegisterToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      // En web el VAPID key sale del firebase_options autogenerado.
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        _lastOptInError =
            'El navegador no entregó un token push (puede que el '
            'Service Worker no esté registrado).';
        return false;
      }

      final api = ApiService(AuthService());
      await api.registerDevice(
        token: token,
        platform: kIsWeb ? 'web' : 'android',
        deviceLabel: _deviceLabel(),
      );

      // Re-registrar cada vez que el OS / browser refresque el token.
      messaging.onTokenRefresh.listen((newToken) async {
        try {
          await api.registerDevice(
            token: newToken,
            platform: kIsWeb ? 'web' : 'android',
            deviceLabel: _deviceLabel(),
          );
        } catch (_) {
          // Best-effort. Próximo arranque reintenta.
        }
      });
      return true;
    } catch (e) {
      _lastOptInError = 'Error registrando el dispositivo: $e';
      debugPrint('[PUSH] fetchAndRegisterToken failed: $e');
      return false;
    }
  }

  /// Revoca el token actual del backend. Llamar desde el toggle en
  /// settings (AC-12). El token FCM local sigue válido, pero el
  /// backend no lo usa más.
  Future<void> revokeFromBackend(String deviceId) async {
    final api = ApiService(AuthService());
    await api.revokeDevice(deviceId);
  }

  Future<List<Map<String, dynamic>>> listMyDevices() async {
    final api = ApiService(AuthService());
    return api.listMyDevices();
  }

  /// Pide al backend disparar un push de prueba al tenant. Retorna
  /// el número de dispositivos que recibieron la push. Si retorna 0
  /// es probable que el token no haya sido registrado todavía.
  Future<int> sendTestPush() async {
    final api = ApiService(AuthService());
    return api.sendTestPush();
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(android: androidInit);
    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          _deepLinkHandler?.call(payload);
        }
      },
    );
    if (!kIsWeb) {
      await _localNotif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  void _wireMessageListeners() {
    // Foreground (AC-14): la push del OS la entrega el browser/Android
    // automáticamente en background. En foreground el SDK NO la
    // muestra — somos nosotros quienes la disparamos via
    // flutter_local_notifications para que el tendero la vea sin
    // tener que mirar la barra de notificaciones.
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final n = msg.notification;
      if (n == null) return;
      _localNotif.show(
        n.hashCode,
        n.title,
        n.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: msg.data['deep_link'] as String?,
      );
    });

    // Tap en push entregada por el OS (app en background, no terminada).
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      final deepLink = msg.data['deep_link'] as String?;
      if (deepLink != null && deepLink.isNotEmpty) {
        _deepLinkHandler?.call(deepLink);
      }
    });
  }

  Future<void> _checkInitialMessage() async {
    // Cuando el tendero toca una push estando la app TERMINADA, el
    // OS la lanza pasando el mensaje en getInitialMessage.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial == null) return;
    final deepLink = initial.data['deep_link'] as String?;
    if (deepLink != null && deepLink.isNotEmpty) {
      // Demoramos un frame para que el Navigator esté listo.
      Future.microtask(() => _deepLinkHandler?.call(deepLink));
    }
  }

  String _deviceLabel() {
    if (kIsWeb) return 'Navegador web';
    return defaultTargetPlatform == TargetPlatform.android
        ? 'Android'
        : defaultTargetPlatform.toString();
  }
}
