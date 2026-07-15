// Spec: specs/105-hito-restaurante-comandas/spec.md — F2 (mostrador prepago).
//
// Arma el payload de la comanda PREPAGO que el POS envía a cocina tras un
// cobro exitoso de mostrador o mesa inmediata. El `sale_uuid` ata el ticket
// a la venta ya registrada: el backend lo hace nacer con `paid_at` y
// CloseOrder lo rechaza (jamás doble venta / doble stock — riesgo crítico
// del concilio 2026-07-14).
//
// Gate: SOLO cuando el pedido trae al menos un PLATO (`is_menu_item`). Una
// tienda vendiendo mecato nunca genera comandas. Cuando aplica, viajan
// TODAS las líneas de producto (plato + acompañamientos) para que el chef
// arme el pedido completo; se excluyen los servicios ad-hoc (sin inventario)
// y las líneas que no pasan la validación del backend (uuid vacío,
// precio <= 0, cantidad <= 0).
import '../../models/cart_item.dart';

/// Devuelve el body para `POST /api/v1/orders`, o `null` si el pedido no
/// lleva cocina. Función pura — el caller decide el label ("Pedido 7",
/// "Mesa 4") y el tipo ('turno' mostrador / 'mesa' inmediata).
Map<String, dynamic>? buildKitchenTicketPayload(
  List<CartItem> items, {
  required String saleUuid,
  required String label,
  String? customerName,
  String type = 'turno',
}) {
  final hasMenuItem =
      items.any((i) => !i.isService && i.product.isMenuItem);
  if (!hasMenuItem) return null;

  final lines = items
      .where((i) =>
          !i.isService &&
          i.product.uuid.isNotEmpty &&
          i.quantity > 0 &&
          i.product.price > 0)
      .map((i) => <String, dynamic>{
            'product_uuid': i.product.uuid,
            'product_name': i.product.name,
            'quantity': i.quantity,
            'unit_price': i.product.price,
          })
      .toList();
  if (lines.isEmpty) return null;

  final name = customerName?.trim() ?? '';
  return <String, dynamic>{
    'label': label,
    'type': type,
    'sale_uuid': saleUuid,
    if (name.isNotEmpty) 'customer_name': name,
    'items': lines,
  };
}
