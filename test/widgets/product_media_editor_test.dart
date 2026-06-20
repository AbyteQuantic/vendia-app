// Spec: specs/070-galeria-multimedia-producto/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/product_media_editor.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  List<Map<String, dynamic>> media = [
    {'id': 'm1', 'type': 'youtube', 'url': 'https://youtube.com/watch?v=abc',
     'thumbnail': 'https://i.ytimg.com/vi/abc/hqdefault.jpg'},
  ];
  String? deletedId;
  String? addedYouTube;

  @override
  Future<List<Map<String, dynamic>>> fetchProductMedia(String productId) async =>
      media;

  @override
  Future<Map<String, dynamic>> addProductMediaYouTube(
      String productId, String url) async {
    addedYouTube = url;
    return {'id': 'm2', 'type': 'youtube', 'url': url};
  }

  @override
  Future<void> deleteProductMedia(String productId, String mediaId) async {
    deletedId = mediaId;
  }
}

Future<void> _pump(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProductMediaEditor(productId: 'p1', api: api),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('muestra la media existente y los botones de agregar', (tester) async {
    await _pump(tester, _FakeApi());
    expect(find.byKey(const Key('media_thumb_m1')), findsOneWidget);
    expect(find.byKey(const Key('media_add_image')), findsOneWidget);
    expect(find.byKey(const Key('media_add_video')), findsOneWidget);
    expect(find.byKey(const Key('media_add_youtube')), findsOneWidget);
  });

  testWidgets('agregar un link de YouTube llama a la API y lo añade', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('media_add_youtube')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://youtu.be/dQw4w9WgXcQ');
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();

    expect(api.addedYouTube, 'https://youtu.be/dQw4w9WgXcQ');
    expect(find.byKey(const Key('media_thumb_m2')), findsOneWidget);
  });

  testWidgets('eliminar un elemento llama a la API y lo quita', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('media_delete_m1')));
    await tester.pumpAndSettle();

    expect(api.deletedId, 'm1');
    expect(find.byKey(const Key('media_thumb_m1')), findsNothing);
  });
}
