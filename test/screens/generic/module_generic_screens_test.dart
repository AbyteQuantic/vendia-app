// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/generic/module_placeholder_screen.dart';
import 'package:vendia_pos/screens/generic/module_webview_screen.dart';

void main() {
  testWidgets('placeholder muestra "Próximamente"', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ModulePlaceholderScreen(title: 'Demo'),
    ));
    expect(find.text('Próximamente'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
  });

  testWidgets('webview sin URL no rompe y avisa que falta el enlace',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ModuleWebviewScreen(title: 'Externo', url: null),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('no tiene un enlace'), findsOneWidget);
  });

  testWidgets('webview con URL muestra el botón Abrir', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ModuleWebviewScreen(title: 'Externo', url: 'https://vendia.store'),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Abrir'), findsOneWidget);
  });
}
