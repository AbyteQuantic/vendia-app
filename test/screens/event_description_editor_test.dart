// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/events/event_description_editor.dart';

void main() {
  testWidgets('edita y "Guardar" devuelve el texto', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(ctx).push<String>(MaterialPageRoute(
              builder: (_) => const EventDescriptionEditorScreen(
                  initialText: 'Curso de color'),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // El editor a pantalla completa muestra el texto inicial en un campo grande.
    expect(find.byKey(const Key('desc_editor_field')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('desc_editor_field')), 'Curso de color Ámbar');
    await tester.tap(find.byKey(const Key('desc_editor_save')));
    await tester.pumpAndSettle();

    expect(result, 'Curso de color Ámbar');
  });

  testWidgets('el botón Viñeta inserta "• " en el texto', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: EventDescriptionEditorScreen(initialText: 'Temario'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desc_editor_bullet')));
    await tester.pump();

    final field =
        tester.widget<TextField>(find.byKey(const Key('desc_editor_field')));
    expect(field.controller!.text.contains('•'), isTrue);
  });

  testWidgets('"Negrita" envuelve en ** y "Título" inserta ##', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: EventDescriptionEditorScreen(initialText: ''),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desc_editor_bold')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('desc_editor_title')));
    await tester.pump();

    final field =
        tester.widget<TextField>(find.byKey(const Key('desc_editor_field')));
    expect(field.controller!.text.contains('**'), isTrue);
    expect(field.controller!.text.contains('## '), isTrue);
  });
}
