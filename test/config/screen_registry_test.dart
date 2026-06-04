// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/screen_registry.dart';
import 'package:vendia_pos/models/catalog/catalog_models.dart';
import 'package:vendia_pos/screens/generic/module_placeholder_screen.dart';
import 'package:vendia_pos/screens/generic/module_webview_screen.dart';
import 'package:vendia_pos/screens/pos/pos_screen.dart';

CatalogModule mod({
  required String render,
  String? screenKey,
  String? url,
}) =>
    CatalogModule(
      id: 'x',
      key: 'k',
      name: 'Demo',
      description: '',
      iconKey: '',
      color: '',
      category: 'vender',
      renderType: render,
      nativeScreenKey: screenKey,
      webviewUrl: url,
      capabilityKey: null,
      requiresPro: false,
      active: true,
      sortOrder: 0,
    );

void main() {
  test('native con clave conocida → pantalla compilada', () {
    final w = buildModuleScreen(mod(render: 'native', screenKey: 'pos'));
    expect(w, isA<PosScreen>());
    expect(hasNativeScreen('pos'), isTrue);
  });

  test('native con clave DESCONOCIDA → placeholder (FR-10)', () {
    final w = buildModuleScreen(
        mod(render: 'native', screenKey: 'no_existe_en_esta_version'));
    expect(w, isA<ModulePlaceholderScreen>());
    expect(hasNativeScreen('no_existe_en_esta_version'), isFalse);
  });

  test('webview → pantalla genérica de webview', () {
    final w = buildModuleScreen(
        mod(render: 'webview', url: 'https://vendia.store'));
    expect(w, isA<ModuleWebviewScreen>());
  });

  test('placeholder → pantalla "próximamente"', () {
    final w = buildModuleScreen(mod(render: 'placeholder'));
    expect(w, isA<ModulePlaceholderScreen>());
  });
}
