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

2. Uso colaborativo de imágenes de producto. Usted autoriza que las fotos de producto que cargue o genere, cuando correspondan a productos identificados por código de barras, puedan ofrecerse como sugerencia a otras tiendas de la red VendIA para ese mismo producto. Recíprocamente, usted puede usar las fotos que otras tiendas hayan aportado. VendIA NO comparte precios, inventario, datos de clientes ni información comercial: únicamente la imagen asociada a un código de barras. Usted declara tener los derechos sobre las fotos que cargue. Puede solicitar la baja de una foto aportada escribiendo a soporte.

3. Datos. Sus datos de negocio son suyos. Tratamos su información conforme a la ley aplicable.

4. Cambios. Podemos actualizar estos términos; se lo notificaremos y podrá revisarlos al ingresar.
''';

/// Resumen corto (para el modal de re-aceptación) — remite al texto completo.
const String kVendiaTermsReacceptSummary =
    'Actualizamos nuestros Términos y Servicios. Ahora incluyen el uso '
    'colaborativo de imágenes de producto: sus fotos de productos con código '
    'de barras pueden sugerirse a otras tiendas de la red VendIA, y usted '
    'puede usar las de otras. No se comparten precios, inventario ni datos de '
    'clientes. Revise y acepte para continuar.';
