import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/supabase_image.dart';

/// Spec 090 (perf): la reescritura de URL sirve MINIATURAS redimensionadas
/// desde el transformador de Supabase (`render/image`) SOLO para fotos de
/// nuestro Storage público. Fotos externas / R2 / ya-transformadas / vacías
/// se dejan intactas.
void main() {
  const proj = 'https://zwoqdbkybopctymftknr.supabase.co';
  const ownUrl =
      '$proj/storage/v1/object/public/product-photos/products/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/1234.png';

  group('snapThumbWidth', () {
    test('redondea hacia arriba al escalón de caché', () {
      expect(snapThumbWidth(1), 100);
      expect(snapThumbWidth(100), 100);
      expect(snapThumbWidth(101), 200);
      expect(snapThumbWidth(168), 200); // 56dp * 3
      expect(snapThumbWidth(200), 200);
      expect(snapThumbWidth(288), 400); // 96dp * 3
      expect(snapThumbWidth(600), 800); // 200dp * 3
    });

    test('nunca supera el máximo escalón', () {
      expect(snapThumbWidth(5000), 800);
    });
  });

  group('targetThumbWidth', () {
    test('usa la mayor dimensión finita × DPR', () {
      expect(targetThumbWidth(56, 56), 200); // 56*3=168 → 200
      expect(targetThumbWidth(48, 48), 200); // 48*3=144 → 200
      expect(targetThumbWidth(96, null), 400); // 96*3=288 → 400
    });

    test('ignora infinity (width por defecto del widget) y usa height', () {
      expect(targetThumbWidth(double.infinity, 200), 800); // 200*3=600 → 800
    });

    test('devuelve null si no hay dimensión finita útil', () {
      expect(targetThumbWidth(null, null), isNull);
      expect(targetThumbWidth(double.infinity, double.infinity), isNull);
      expect(targetThumbWidth(0, 0), isNull);
    });
  });

  group('isTransformableSupabaseUrl', () {
    test('reconoce nuestro Storage público', () {
      expect(isTransformableSupabaseUrl(ownUrl), isTrue);
    });
    test('rechaza vacía, externa, R2 y ya-transformada', () {
      expect(isTransformableSupabaseUrl(''), isFalse);
      expect(
          isTransformableSupabaseUrl(
              'https://images.openfoodfacts.org/images/products/123/front.jpg'),
          isFalse);
      expect(
          isTransformableSupabaseUrl(
              'https://acme.r2.cloudflarestorage.com/product-photos/products/x/1.png'),
          isFalse);
      expect(
          isTransformableSupabaseUrl(
              '$proj/storage/v1/render/image/public/product-photos/products/x/1.png?width=200'),
          isFalse);
    });
  });

  group('supabaseThumbUrl', () {
    test('propia → render/image con width+quality+resize', () {
      final out = supabaseThumbUrl(ownUrl, targetWidth: 200);
      expect(out, contains('/storage/v1/render/image/public/'));
      expect(out, isNot(contains('/storage/v1/object/public/')));
      expect(out, contains('width=200'));
      expect(out, contains('quality=70'));
      expect(out, contains('resize=cover'));
    });

    test('respeta quality personalizada', () {
      final out = supabaseThumbUrl(ownUrl, targetWidth: 400, quality: 60);
      expect(out, contains('width=400'));
      expect(out, contains('quality=60'));
    });

    test('externa → sin cambio', () {
      const ext =
          'https://images.openfoodfacts.org/images/products/123/front.jpg';
      expect(supabaseThumbUrl(ext, targetWidth: 200), ext);
    });

    test('ya-render → sin cambio (no doble reescritura)', () {
      const already =
          'https://x.supabase.co/storage/v1/render/image/public/b/p.png?width=200&quality=70&resize=cover';
      expect(supabaseThumbUrl(already, targetWidth: 400), already);
    });

    test('vacía → sin cambio', () {
      expect(supabaseThumbUrl('', targetWidth: 200), '');
    });

    test('targetWidth null → sin cambio', () {
      expect(supabaseThumbUrl(ownUrl, targetWidth: null), ownUrl);
    });

    test('anexa con & si la URL ya trae query', () {
      const withQuery = '$ownUrl?token=abc';
      final out = supabaseThumbUrl(withQuery, targetWidth: 200);
      expect(out, contains('?token=abc&width=200'));
    });
  });

  group('optimizedProductImageUrl (atajo del widget)', () {
    test('miniatura 56dp → width 200 render/image', () {
      final out = optimizedProductImageUrl(ownUrl, width: 56, height: 56);
      expect(out, contains('/render/image/public/'));
      expect(out, contains('width=200'));
    });

    test('detalle grande (height 200, width infinity) → width 800', () {
      final out = optimizedProductImageUrl(ownUrl,
          width: double.infinity, height: 200);
      expect(out, contains('width=800'));
    });

    test('null / vacía → string vacío sin reescribir', () {
      expect(optimizedProductImageUrl(null, width: 56, height: 56), '');
      expect(optimizedProductImageUrl('', width: 56, height: 56), '');
    });

    test('externa → intacta', () {
      const ext =
          'https://cdnx.vtexassets.com/arquivos/ids/123/pic.jpg';
      expect(optimizedProductImageUrl(ext, width: 400, height: 400), ext);
    });

    test('sin dimensión útil → intacta (no puede dimensionar)', () {
      expect(optimizedProductImageUrl(ownUrl), ownUrl);
    });
  });
}
