// Spec: specs/044-catalogo-publico-unificado/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/inventory/create_service_screen.dart';

void main() {
  group('CreateServiceScreen (F044)', () {
    testWidgets('renderiza el formulario de servicio y el selector de foto',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: CreateServiceScreen()));
      await tester.pump();

      expect(find.text('Crear servicio'), findsOneWidget);
      expect(find.byKey(const Key('service_photo_picker')), findsOneWidget);
      expect(find.byKey(const Key('create_service_save')), findsOneWidget);
      expect(find.text('Nombre del servicio'), findsOneWidget);
      // Categoría por defecto + chips de sugerencia.
      expect(find.text('Servicios'), findsWidgets);
      expect(find.text('Reparaciones'), findsOneWidget);
    });

    testWidgets('guardar sin nombre muestra aviso y no navega', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: CreateServiceScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('create_service_save')));
      await tester.pump();

      expect(find.textContaining('nombre del servicio'), findsOneWidget);
      // Sigue en la pantalla (no navegó ni intentó red).
      expect(find.byKey(const Key('create_service_save')), findsOneWidget);
    });
  });
}
