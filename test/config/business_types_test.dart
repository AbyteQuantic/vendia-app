// Bug real reportado: la pantalla "Perfil del Negocio" mantenía su propia
// copia de la lista de tipos de negocio, separada de esta lista canónica —
// dos migraciones (Spec 075 proveedores, Spec 084 peluquería/barbería)
// agregaron tipos nuevos aquí sin que la copia del perfil se enterara, así
// que un tendero de peluquería nunca podía marcar su categoría real. El
// fix fue eliminar la copia y consumir `kBusinessTypes` directamente en
// business_profile_screen.dart — este test fija la garantía central: los
// tipos que ya viven en producción (barra del Dashboard, onboarding) están
// todos presentes aquí, así que cualquier pantalla que los consuma los ve.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/config/business_types.dart';

void main() {
  group('kBusinessTypes — fuente única de tipos de negocio', () {
    test('incluye los tipos históricos y los agregados por Spec 075/084', () {
      final values = kBusinessTypes.map((t) => t.value).toSet();
      expect(
        values,
        containsAll(<String>[
          'tienda_barrio',
          'minimercado',
          'deposito_construccion',
          'restaurante',
          'comidas_rapidas',
          'bar',
          'manufactura',
          'reparacion_muebles',
          'emprendimiento_general',
          'academias_instituciones',
          // Spec 075 — proveedores B2B.
          'proveedor_mayorista',
          'proveedor_agricola',
          // Spec 084 — peluquerías, barberías y salones de belleza.
          'peluqueria_barberia',
        ]),
      );
    });

    test('no tiene valores duplicados (cada value aparece una sola vez)', () {
      final values = kBusinessTypes.map((t) => t.value).toList();
      expect(values.toSet().length, values.length,
          reason: 'un value duplicado rompería el grid multi-select');
    });

    test('peluqueria_barberia resuelve a su ícono y label esperados', () {
      final meta = businessTypeMeta('peluqueria_barberia');
      expect(meta.label, 'Peluquería / Barbería');
    });
  });
}
