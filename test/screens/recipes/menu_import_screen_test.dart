// Spec: specs/043-menu-restaurante-recetas/spec.md
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vendia_pos/screens/recipes/menu_import_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Doble de ApiService — descripción + foto fijas para el plato.
class _FakeMenuApi extends ApiService {
  _FakeMenuApi(this._desc, {String? imageUrl, String? enhancedUrl})
      : _imageUrl = imageUrl,
        _enhancedUrl = enhancedUrl,
        super(AuthService());
  final String _desc;
  final String? _imageUrl;
  final String? _enhancedUrl;

  String? lastGenPresentation;
  String? lastGenDescription;

  @override
  Future<String> generateMenuDescription({
    required String name,
    String category = '',
  }) async =>
      _desc;

  @override
  Future<String> generateMenuImage({
    required String name,
    String category = '',
    String description = '',
    String presentation = '',
  }) async {
    lastGenPresentation = presentation;
    lastGenDescription = description;
    return _imageUrl ?? '';
  }

  @override
  Future<String> enhanceMenuImage({
    required Uint8List imageBytes,
    required String name,
    String category = '',
    String mimeType = 'image/jpeg',
    String filename = 'plato.jpg',
  }) async =>
      _enhancedUrl ?? '';
}

/// Fake del ImagePicker: devuelve siempre una imagen en memoria (web-safe,
/// vía XFile.fromData) para poder ejercer el flujo subir→mejorar sin cámara.
class _FakePicker extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(
        Uint8List.fromList(List<int>.filled(64, 7)),
        name: 'plato.png',
        mimeType: 'image/png',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() =>
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('EditableDish (F043)', () {
    test('fromScan mapea los campos del plato escaneado', () {
      final d = EditableDish.fromScan({
        'name': 'Bandeja Paisa',
        'description': 'Frijoles, arroz, carne',
        'price': 25000,
        'portion': 'Personal',
        'category': 'Platos fuertes',
      });

      expect(d.name.text, 'Bandeja Paisa');
      expect(d.description.text, 'Frijoles, arroz, carne');
      expect(d.price.text, '25000');
      expect(d.portion.text, 'Personal');
      expect(d.category, 'Platos fuertes');
      expect(d.isValid, isTrue);
      expect(d.imageKind, DishImageKind.none);
    });

    test('toCreatePayload marca is_menu_item y omite campos vacíos', () {
      final d = EditableDish.fromScan({
        'name': 'Limonada',
        'description': '',
        'price': 8000,
        'portion': '',
        'category': 'Bebidas',
      });
      final payload = d.toCreatePayload();

      expect(payload['name'], 'Limonada');
      expect(payload['price'], 8000);
      expect(payload['is_menu_item'], true);
      expect(payload['stock'], 0);
      expect(payload.containsKey('description'), isFalse);
      expect(payload.containsKey('portion'), isFalse);
      // Sin foto → no se envía provenance.
      expect(payload.containsKey('photo_is_sample'), isFalse);
    });

    test('toCreatePayload — foto de muestra IA viaja como photo_is_sample=true',
        () {
      final d = EditableDish.fromScan({'name': 'Bandeja Paisa', 'price': 25000})
        ..imageUrl = 'https://r2/menu/abc.png'
        ..imageKind = DishImageKind.sample;
      final payload = d.toCreatePayload();
      expect(payload['image_url'], 'https://r2/menu/abc.png');
      expect(payload['photo_is_sample'], true);
    });

    test('toCreatePayload — foto real (mejorada) NO es muestra', () {
      final d = EditableDish.fromScan({'name': 'Bandeja Paisa', 'price': 25000})
        ..imageUrl = 'https://r2/menu/real.png'
        ..imageKind = DishImageKind.real
        ..photoEnhanced = true;
      final payload = d.toCreatePayload();
      expect(payload['image_url'], 'https://r2/menu/real.png');
      expect(payload['photo_is_sample'], false);
    });
  });

  group('MenuImportScreen (F043)', () {
    testWidgets('renderiza los platos escaneados con sus campos editables',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MenuImportScreen(scannedDishes: [
          {
            'name': 'Bandeja Paisa',
            'description': 'Frijoles y arroz',
            'price': 25000,
            'portion': 'Personal',
            'category': 'Platos fuertes',
          },
        ]),
      ));
      await tester.pump();

      expect(find.text('Bandeja Paisa'), findsOneWidget);
      expect(find.text('Frijoles y arroz'), findsOneWidget);
      expect(find.byKey(const Key('menu_import_save')), findsOneWidget);
      expect(find.byKey(const Key('menu_import_add')), findsOneWidget);
    });

    testWidgets('estado vacío ofrece foto real (cámara/galería) + muestra IA',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(
        home: MenuImportScreen(scannedDishes: [
          {'name': 'Bandeja Paisa', 'price': 25000},
        ]),
      ));
      await tester.pump();

      expect(find.byKey(const Key('menu_dish_photo_camera_0')), findsOneWidget);
      expect(find.byKey(const Key('menu_dish_photo_gallery_0')), findsOneWidget);
      expect(find.byKey(const Key('menu_dish_ai_photo_0')), findsOneWidget);
      // "Mejorar con IA" NO existe sin foto.
      expect(find.byKey(const Key('menu_dish_enhance_0')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Descripción con IA" llena el campo con la IA (F043)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MenuImportScreen(
          apiOverride: _FakeMenuApi('Frijoles, arroz, carne y chicharrón'),
          scannedDishes: const [
            {'name': 'Bandeja Paisa', 'price': 25000, 'category': 'Platos fuertes'},
          ],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('menu_dish_ai_desc_0')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Frijoles, arroz, carne y chicharrón'), findsOneWidget);
    });

    testWidgets('muestra IA: pregunta presentación (omitible) y pinta "Muestra (IA)"',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _FakeMenuApi('', imageUrl: 'https://r2.vendia.co/menu/abc.png');
      await tester.pumpWidget(MaterialApp(
        home: MenuImportScreen(
          apiOverride: api,
          scannedDishes: const [
            {'name': 'Bandeja Paisa', 'price': 25000},
          ],
        ),
      ));
      await tester.pump();

      expect(find.text('Muestra (IA)'), findsNothing);

      await tester.tap(find.byKey(const Key('menu_dish_ai_photo_0')));
      await tester.pumpAndSettle();
      // Hoja de presentación opcional.
      expect(find.text('¿Cómo se sirve el plato? (opcional)'), findsOneWidget);
      await tester.tap(find.text('Omitir'));
      await tester.pumpAndSettle();

      // Tras generar: badge de MUESTRA (no engaña: es ilustración IA).
      expect(find.text('Muestra (IA)'), findsOneWidget);
      // Sobre una muestra NO se ofrece "Mejorar con IA".
      expect(find.byKey(const Key('menu_dish_enhance_0')), findsNothing);
    });

    testWidgets('muestra IA: acompañamientos componen la presentación',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _FakeMenuApi('', imageUrl: 'https://r2.vendia.co/menu/abc.png');
      await tester.pumpWidget(MaterialApp(
        home: MenuImportScreen(
          apiOverride: api,
          scannedDishes: const [
            {'name': 'Bandeja Paisa', 'price': 25000},
          ],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('menu_dish_ai_photo_0')));
      await tester.pumpAndSettle();
      // Nueva sección de acompañamientos.
      expect(find.text('¿Con qué acompañamientos?'), findsOneWidget);
      await tester.tap(find.text('En plato'));
      await tester.tap(find.text('Arroz'));
      await tester.tap(find.text('Jugo'));
      await tester.pumpAndSettle();
      // Sección nueva: marcar que el jugo va en plato APARTE (el 2º 'Jugo').
      expect(find.text('¿Alguno va en plato aparte?'), findsOneWidget);
      final aparteJugo = find.text('Jugo').last;
      await tester.ensureVisible(aparteJugo);
      await tester.tap(aparteJugo);
      await tester.pumpAndSettle();
      final crear = find.text('Crear foto');
      await tester.ensureVisible(crear);
      await tester.tap(crear);
      await tester.pumpAndSettle();

      // El prompt distingue lo del plato (arroz) de lo aparte (jugo).
      expect(api.lastGenPresentation, contains('En plato'));
      expect(api.lastGenPresentation, contains('arroz en el mismo plato'));
      expect(api.lastGenPresentation, contains('jugo en plato aparte'));
    });

    testWidgets('muestra IA: ofrece agregar un acompañamiento propio',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Acompañamiento personalizado guardado antes → aparece para este plato.
      SharedPreferences.setMockInitialValues({'custom_sides': ['Chicharrón']});
      final api = _FakeMenuApi('', imageUrl: 'https://r2.vendia.co/menu/abc.png');
      await tester.pumpWidget(MaterialApp(
        home: MenuImportScreen(apiOverride: api, scannedDishes: const [
          {'name': 'Bandeja Paisa', 'price': 25000},
        ]),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('menu_dish_ai_photo_0')));
      await tester.pumpAndSettle();

      // El campo para agregar + el botón están; y el guardado previo aparece.
      expect(find.byKey(const Key('custom_side_field')), findsOneWidget);
      expect(find.byKey(const Key('add_custom_side')), findsOneWidget);
      expect(find.text('Chicharrón'), findsOneWidget); // persistió de antes
    });

    testWidgets('subir foto de galería → mejora fiel → badge "Su foto" + Mejorar',
        (tester) async {
      ImagePickerPlatform.instance = _FakePicker();
      final api = _FakeMenuApi('',
          enhancedUrl: 'https://r2.vendia.co/menu/real-mejorada.png');

      await tester.binding.setSurfaceSize(const Size(360, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: MenuImportScreen(
          apiOverride: api,
          scannedDishes: const [
            {'name': 'Bandeja Paisa', 'price': 25000},
          ],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('menu_dish_photo_gallery_0')));
      await tester.pumpAndSettle();

      // Foto real mejorada: badge "Su foto" (verde), NO "Muestra (IA)".
      expect(find.text('Su foto'), findsOneWidget);
      expect(find.text('Muestra (IA)'), findsNothing);
      // Y sí ofrece volver a mejorar.
      expect(find.byKey(const Key('menu_dish_enhance_0')), findsOneWidget);
    });
  });
}
