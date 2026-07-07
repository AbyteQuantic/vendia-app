// Spec: specs/097-completar-fotos-inventario/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/catalog_suggestion.dart';

void main() {
  group('CatalogSuggestion.fromJson (defensivo)', () {
    test('parsea una sugerencia verificada', () {
      final s = CatalogSuggestion.fromJson({
        'image_url': 'https://r2/coca.jpg',
        'name': 'Coca-Cola 400ml',
        'brand': 'Coca-Cola',
        'verified': true,
      });
      expect(s, isNotNull);
      expect(s!.imageUrl, 'https://r2/coca.jpg');
      expect(s.verified, isTrue);
      expect(s.name, 'Coca-Cola 400ml');
    });

    test('verified ausente → false (respaldo)', () {
      final s = CatalogSuggestion.fromJson({'image_url': 'https://x/y.jpg'});
      expect(s!.verified, isFalse);
    });

    test('sin image_url → null (no es sugerencia)', () {
      expect(CatalogSuggestion.fromJson({'name': 'x'}), isNull);
      expect(CatalogSuggestion.fromJson({'image_url': ''}), isNull);
      expect(CatalogSuggestion.fromJson({'image_url': '   '}), isNull);
    });

    test('no-mapa → null (nunca lanza)', () {
      expect(CatalogSuggestion.fromJson('nope'), isNull);
      expect(CatalogSuggestion.fromJson(null), isNull);
    });
  });
}
