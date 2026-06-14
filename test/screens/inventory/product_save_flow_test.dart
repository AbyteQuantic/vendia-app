// Spec: specs/047-offline-sync-contract/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/inventory/product_save_flow.dart';

void main() {
  group('persistProductOfflineFirst — el producto NUNCA se pierde', () {
    test('ONLINE: server OK → guarda local, NO marca pendiente', () async {
      var localSaved = false, marked = false, serverCalled = false;
      final out = await persistProductOfflineFirst(
        serverWrite: () async => serverCalled = true,
        saveLocal: () async => localSaved = true,
        markPending: () async => marked = true,
      );

      expect(serverCalled, isTrue);
      expect(localSaved, isTrue, reason: 'siempre persiste local');
      expect(marked, isFalse, reason: 'online no marca pendiente');
      expect(out.serverOk, isTrue);
      expect(out.markedPending, isFalse);
    });

    test('OFFLINE: serverWrite lanza → IGUAL guarda local y marca pendiente',
        () async {
      var localSaved = false, marked = false;
      final out = await persistProductOfflineFirst(
        serverWrite: () async => throw Exception('sin conexión'),
        saveLocal: () async => localSaved = true,
        markPending: () async => marked = true,
      );

      // Este es el bug original: antes, una excepción de red saltaba el
      // guardado local y el producto se perdía mostrando "guardado".
      expect(localSaved, isTrue, reason: 'el producto NO se pierde offline');
      expect(marked, isTrue, reason: 'se marca para subir al reconectar');
      expect(out.serverOk, isFalse);
      expect(out.savedLocally, isTrue);
      expect(out.markedPending, isTrue);
    });

    test('el orden es: server → local → markPending', () async {
      final order = <String>[];
      await persistProductOfflineFirst(
        serverWrite: () async {
          order.add('server');
          throw Exception('offline');
        },
        saveLocal: () async => order.add('local'),
        markPending: () async => order.add('pending'),
      );
      expect(order, ['server', 'local', 'pending']);
    });

    test('si saveLocal lanza, el outcome no miente (propaga el error real)',
        () async {
      // saveLocal es la persistencia crítica: un fallo aquí SÍ debe verse.
      expect(
        () => persistProductOfflineFirst(
          serverWrite: () async {},
          saveLocal: () async => throw Exception('Isar caído'),
          markPending: () async {},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('isOnline — sin red NO se intenta el servidor (evita el delay de ~30s)',
      () {
    test('isOnline=false → serverWrite NUNCA se llama; guarda local + pendiente',
        () async {
      var serverCalled = false, localSaved = false, marked = false;
      final out = await persistProductOfflineFirst(
        serverWrite: () async => serverCalled = true,
        saveLocal: () async => localSaved = true,
        markPending: () async => marked = true,
        isOnline: () async => false,
      );

      expect(serverCalled, isFalse,
          reason: 'offline no debe tocar la red (sin espera de timeout)');
      expect(localSaved, isTrue);
      expect(marked, isTrue);
      expect(out.serverOk, isFalse);
    });

    test('isOnline=true → sí intenta el servidor', () async {
      var serverCalled = false;
      final out = await persistProductOfflineFirst(
        serverWrite: () async => serverCalled = true,
        saveLocal: () async {},
        markPending: () async {},
        isOnline: () async => true,
      );
      expect(serverCalled, isTrue);
      expect(out.serverOk, isTrue);
    });

    test('isOnline ausente → asume online (retrocompatible)', () async {
      var serverCalled = false;
      await persistProductOfflineFirst(
        serverWrite: () async => serverCalled = true,
        saveLocal: () async {},
        markPending: () async {},
      );
      expect(serverCalled, isTrue);
    });

    test('isOnline=false NO espera por serverWrite lento (responde rápido)',
        () async {
      // Si la red estuviera caída, serverWrite tardaría; con isOnline=false ni
      // se invoca, así que el flujo termina al instante.
      final sw = Stopwatch()..start();
      await persistProductOfflineFirst(
        serverWrite: () async =>
            await Future<void>.delayed(const Duration(seconds: 5)),
        saveLocal: () async {},
        markPending: () async {},
        isOnline: () async => false,
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000),
          reason: 'no debe esperar el serverWrite lento');
    });
  });
}
