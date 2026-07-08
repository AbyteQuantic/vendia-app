// Spec: specs/098-aporte-automatico-fotos-colaborativo/spec.md
//
// Texto de los Términos y Servicios de VendIA, incluida la cláusula de uso
// colaborativo de imágenes de producto (Spec 098, Fase 1). Se mantiene como una
// constante única para que tanto la pantalla de registro como el modal de
// re-aceptación en el login muestren EXACTAMENTE el mismo contenido.

const String kVendiaTermsText = '''
TÉRMINOS Y SERVICIOS DE VENDIA

Al crear una cuenta y usar VendIA usted acepta estos términos.

1. Uso del servicio. VendIA es un punto de venta y herramientas para su negocio. Usted es responsable de la información que registra.

2. Uso colaborativo de imágenes de producto. Usted autoriza que las fotos de producto que cargue o genere, cuando correspondan a productos identificados por código de barras, puedan ofrecerse como sugerencia a otras tiendas de la red VendIA para ese mismo producto. Recíprocamente, usted puede usar las fotos que otras tiendas hayan aportado. VendIA NO comparte precios, inventario, datos de clientes ni información comercial: únicamente la imagen asociada a un código de barras. Usted declara tener los derechos sobre las fotos que cargue. NO cargue fotos sobre las que no tenga derechos —por ejemplo, imágenes tomadas de Google, de catálogos de otras marcas o de bancos de imágenes—. Solo cargue fotos que usted haya tomado o cuyos derechos posea. Puede solicitar la baja de una foto aportada escribiendo a soporte.

3. Datos. Sus datos de negocio son suyos. Tratamos su información conforme a la ley aplicable.

4. Responsabilidad por las fotos. Usted es el único responsable de las fotos que carga y declara tener los derechos para usarlas y compartirlas. Usted mantendrá indemne a VendIA frente a cualquier reclamo, daño o gasto (incluidos honorarios legales) que surja de las fotos que usted cargue, en particular por infracción de derechos de autor u otros derechos de terceros. VendIA podrá retirar en cualquier momento una foto del catálogo compartido ante un reclamo de derechos.

5. Cambios. Podemos actualizar estos términos; se lo notificaremos y podrá revisarlos al ingresar.
''';

/// Resumen corto (para el modal de re-aceptación) — remite al texto completo.
const String kVendiaTermsReacceptSummary =
    'Actualizamos nuestros Términos y Servicios. Ahora incluyen el uso '
    'colaborativo de imágenes de producto: sus fotos de productos con código '
    'de barras pueden sugerirse a otras tiendas de la red VendIA, y usted '
    'puede usar las de otras. No se comparten precios, inventario ni datos de '
    'clientes. Además, no debe subir fotos de terceros (por ejemplo tomadas de '
    'Google o de catálogos de otras marcas): usted es el único responsable de '
    'las fotos que carga y mantiene indemne a VendIA por cualquier reclamo de '
    'derechos sobre ellas. Revise y acepte para continuar.';
