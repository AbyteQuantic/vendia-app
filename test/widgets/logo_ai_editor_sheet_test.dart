// Spec: specs/060-logo-ia-editor/spec.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/widgets/logo_ai_editor_sheet.dart';

Future<void> _open(
  WidgetTester tester, {
  required Future<String?> Function(String) onGenerate,
  required void Function(String) onSaved,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showLogoAiEditor(
            ctx,
            onGenerate: onGenerate,
            onSaved: onSaved,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('especificaciones cortas → error, no llama a la IA',
      (tester) async {
    var calls = 0;
    await _open(
      tester,
      onGenerate: (_) async {
        calls++;
        return 'https://logo.png';
      },
      onSaved: (_) {},
    );

    await tester.enterText(
        find.byKey(const Key('logo_ai_specs_input')), 'corto');
    await tester.tap(find.byKey(const Key('logo_ai_generate_btn')));
    await tester.pump();

    expect(calls, 0);
    expect(find.textContaining('al menos'), findsOneWidget);
  });

  testWidgets('genera con especificaciones, previsualiza y usa el logo',
      (tester) async {
    String? generatedWith;
    String? saved;
    await _open(
      tester,
      onGenerate: (specs) async {
        generatedWith = specs;
        return 'https://cdn/nuevo-logo.png';
      },
      onSaved: (url) => saved = url,
    );

    await tester.enterText(
      find.byKey(const Key('logo_ai_specs_input')),
      'colores verde y naranja, una fruta sonriente, estilo moderno',
    );
    await tester.tap(find.byKey(const Key('logo_ai_generate_btn')));
    await tester.pumpAndSettle();

    // Pasó las especificaciones a la IA.
    expect(generatedWith, contains('fruta sonriente'));
    // Vista previa con botón "Usar este logo".
    expect(find.byKey(const Key('logo_ai_use_btn')), findsOneWidget);

    await tester.tap(find.byKey(const Key('logo_ai_use_btn')));
    await tester.pumpAndSettle();

    expect(saved, 'https://cdn/nuevo-logo.png');
  });

  testWidgets('"ajustar y probar otra vez" vuelve al input', (tester) async {
    await _open(
      tester,
      onGenerate: (_) async => 'https://cdn/logo.png',
      onSaved: (_) {},
    );
    await tester.enterText(
      find.byKey(const Key('logo_ai_specs_input')),
      'algo suficientemente largo para pasar',
    );
    await tester.tap(find.byKey(const Key('logo_ai_generate_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logo_ai_retry_btn')), findsOneWidget);

    await tester.tap(find.byKey(const Key('logo_ai_retry_btn')));
    await tester.pumpAndSettle();
    // Regresó al input.
    expect(find.byKey(const Key('logo_ai_specs_input')), findsOneWidget);
    expect(find.byKey(const Key('logo_ai_generate_btn')), findsOneWidget);
  });
}
