// Spec: specs/069-catalogo-unificado-eventos-inventario/spec.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vendia_pos/widgets/catalog_link_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  Widget wrap(Widget c) => MaterialApp(home: Scaffold(body: c));

  testWidgets('con slug muestra el link y los botones copiar/abrir', (tester) async {
    await tester.pumpWidget(wrap(const CatalogLinkCard(
      storeSlug: 'don-brayan-c937',
      keyPrefix: 'inventory_catalog_preview',
    )));
    expect(find.text('Su catálogo en línea'), findsOneWidget);
    expect(find.byKey(const Key('inventory_catalog_preview_copy')), findsOneWidget);
    expect(find.byKey(const Key('inventory_catalog_preview_open')), findsOneWidget);
    expect(find.textContaining('don-brayan-c937'), findsOneWidget);
  });

  testWidgets('copiar pone el link en el portapapeles', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });

    await tester.pumpWidget(wrap(const CatalogLinkCard(
      storeSlug: 'don-brayan-c937',
      keyPrefix: 'inventory_catalog_preview',
    )));
    await tester.tap(find.byKey(const Key('inventory_catalog_preview_copy')));
    await tester.pump();
    expect(copied, contains('don-brayan-c937'));
  });

  testWidgets('sin slug no se renderiza nada', (tester) async {
    await tester.pumpWidget(wrap(const CatalogLinkCard(storeSlug: '')));
    expect(find.text('Su catálogo en línea'), findsNothing);
  });
}
