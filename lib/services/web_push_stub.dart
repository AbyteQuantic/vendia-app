// Spec: specs/038-push-notifications-web-android/spec.md
//
// Stub no-web de Web Push nativo (iOS Safari). En plataformas sin
// `dart:js_interop` (VM de tests, móvil) NO se puede importar
// `web_push_native.dart`. Este stub expone la MISMA API pública con
// comportamiento no-op, para que `push_service.dart` compile en cualquier
// plataforma vía import condicional. (Descubierto al consumir el catálogo
// dinámico F041 desde tests en la VM.)

/// Token FCM + label para registrar en backend (no-op en este stub).
class WebPushSubscription {
  final String fcmToken;
  WebPushSubscription({required this.fcmToken});
}

class WebPushNative {
  WebPushNative._();
  static final WebPushNative instance = WebPushNative._();

  /// Fuera de web nunca es iOS Safari.
  static bool get isAppleSafari => false;

  String? get lastError => null;

  /// No hay Web Push fuera del navegador → siempre null.
  Future<WebPushSubscription?> requestSubscription() async => null;
}
