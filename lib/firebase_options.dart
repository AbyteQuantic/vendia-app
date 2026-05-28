// Spec: specs/038-push-notifications-web-android/spec.md
//
// STUB de firebase_options.dart — Bryan debe regenerarlo con
// `flutterfire configure` después de crear el proyecto Firebase en
// console.firebase.google.com (Fase 0 del plan F038, tarea T-00).
//
// El stub permite que el código compile y el server arranque, pero
// `DefaultFirebaseOptions.currentPlatform` retorna `null` — el
// PushService lo detecta y queda en modo "inactivo": ni se muestra
// la tarjeta de opt-in, ni se registra token. El usuario igual puede
// usar la app, solo no recibe notificaciones push hasta que se
// genere el archivo real.
//
// Una vez Bryan corra `flutterfire configure`, este archivo se
// sobreescribe con los valores reales del proyecto (apiKey,
// authDomain, projectId, etc.) y el flag `isConfigured` queda en
// true automáticamente.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  /// Detecta si el archivo fue regenerado con credenciales reales.
  /// El stub deja esto en `false`; `flutterfire configure` lo flippea
  /// a `true` con los valores poblados.
  static const bool isConfigured = false;

  /// Retorna las opciones de Firebase para la plataforma actual.
  /// En el stub retorna `null` para que el caller pueda decidir si
  /// inicializar Firebase o no.
  static FirebaseOptions? get currentPlatform {
    if (!isConfigured) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[FIREBASE] stub firebase_options.dart — corra '
            '`flutterfire configure` para activar push.');
      }
      return null;
    }
    // Cuando el stub se sobreescriba, este branch retorna los valores
    // reales según defaultTargetPlatform y kIsWeb. flutterfire los
    // genera automáticamente.
    return null;
  }
}
