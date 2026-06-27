// Spec: specs/086-branding-estacional/spec.md
//
// Verifica la CONFIG NATIVA del cambio de ícono estacional sin necesitar un
// build (analyze/tests no la cubren). Protege invariantes críticas: la
// impresora ESC/POS (USB filter en MainActivity) y la estructura de aliases.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/seasonal_icons.dart';

void main() {
  // Variantes con ícono nativo PRE-EMPAQUETADO (deben tener alias + plist + assets).
  const bundled = ['navidad', 'mundial', 'dia_mujer', 'dia_madre', 'dia_padre'];

  group('seasonal_icons (map variant→nativo)', () {
    test('cada variante empaquetada mapea a su nombre nativo', () {
      for (final v in bundled) {
        expect(nativeIconName(v), v);
      }
    });
    test('default/desconocido → null (ícono primario)', () {
      expect(nativeIconName('default'), isNull);
      expect(nativeIconName(null), isNull);
      expect(nativeIconName('inexistente'), isNull);
      // amor_amistad es válida en config pero sin ícono empaquetado aún → null.
      expect(nativeIconName('amor_amistad'), isNull);
    });
  });

  group('AndroidManifest — invariantes', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('MainActivity conserva el USB_DEVICE_ATTACHED (impresora ESC/POS)', () {
      expect(m.contains('android.hardware.usb.action.USB_DEVICE_ATTACHED'), isTrue);
      expect(m.contains('@xml/device_filter'), isTrue);
    });

    test('MainActivity conserva su LAUNCHER (ícono por defecto)', () {
      expect(m.contains('.MainActivity'), isTrue);
      expect(m.contains('android.intent.category.LAUNCHER'), isTrue);
    });

    test('service del plugin presente', () {
      expect(m.contains('FlutterDynamicIconPlusService'), isTrue);
    });

    test('cada alias: deshabilitado, targetActivity MainActivity', () {
      for (final v in bundled) {
        expect(m.contains('android:name=".$v"'), isTrue, reason: 'alias .$v');
        expect(m.contains('@mipmap/ic_launcher_$v'), isTrue);
        final idx = m.indexOf('android:name=".$v"');
        final around = m.substring(idx, (idx + 400).clamp(0, m.length));
        expect(around.contains('android:enabled="false"'), isTrue);
        expect(around.contains('android:targetActivity=".MainActivity"'), isTrue);
      }
    });
  });

  group('iOS Info.plist — íconos alternos', () {
    final p = File('ios/Runner/Info.plist').readAsStringSync();
    test('CFBundleAlternateIcons con cada variante', () {
      expect(p.contains('CFBundleAlternateIcons'), isTrue);
      for (final v in bundled) {
        expect(p.contains('<key>$v</key>'), isTrue, reason: 'plist key $v');
        expect(p.contains('AppIcon-$v'), isTrue);
      }
    });
  });

  group('assets de íconos presentes (cada variante)', () {
    test('iOS PNGs + Android mipmaps + adaptive xml', () {
      for (final v in bundled) {
        expect(File('ios/Runner/AppIcon-$v@2x.png').existsSync(), isTrue);
        expect(File('ios/Runner/AppIcon-$v@3x.png').existsSync(), isTrue);
        expect(
            File('android/app/src/main/res/mipmap-xxhdpi/ic_launcher_$v.png')
                .existsSync(),
            isTrue);
        expect(
            File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_$v.xml')
                .existsSync(),
            isTrue);
      }
    });
  });
}
