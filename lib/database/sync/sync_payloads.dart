// Spec: specs/047-offline-sync-contract/spec.md
//
// Construcción del payload de sincronización (`/sync/batch`) con NOMBRES DE
// COLUMNA del backend. El backend hace `Create(op.Data)` usando las llaves del
// mapa como columnas (sync_service.go), así que estas llaves DEBEN coincidir con
// el modelo Go — no con el `toJson` local (que usa `uuid`, `customer_uuid`,
// montos `double`, etc., ninguno de los cuales es columna).
//
// Reglas:
//   * la PK (`id`) y `tenant_id` los estampa el backend desde el JWT — no se
//     envían aquí,
//   * montos en enteros (COP no tiene centavos; las columnas son int64),
//   * UUID nullable (`sale_id`) se OMITE si está vacío (enviar "" rompe el
//     insert Postgres — regla *string del proyecto).

import '../collections/local_customer.dart';
import '../collections/local_credit.dart';

/// Columnas del modelo `Customer` (customer.go). `id`/`tenant_id` los pone el
/// backend. `total_credit`/`total_paid` NO son columnas → se omiten.
Map<String, dynamic> customerSyncPayload(LocalCustomer c) => {
      'name': c.name,
      'phone': c.phone,
      'email': c.email,
    };

/// Columnas del modelo `CreditAccount` (credit_account.go).
Map<String, dynamic> creditAccountSyncPayload(LocalCredit c) {
  final map = <String, dynamic>{
    'customer_id': c.customerUuid,
    'total_amount': c.totalAmount.round(),
    'paid_amount': c.paidAmount.round(),
    'status': c.status,
  };
  // sale_id es *string nullable: omitir cuando no hay venta asociada.
  if (c.saleUuid.isNotEmpty) {
    map['sale_id'] = c.saleUuid;
  }
  return map;
}

/// Columnas del modelo `CreditPayment` (credit_payment.go). El backend estampa
/// `id`; `paid_at` no es columna (usa CreatedAt de BaseModel).
Map<String, dynamic> creditPaymentSyncPayload({
  required String creditAccountId,
  required double amount,
  String note = '',
}) =>
    {
      'credit_account_id': creditAccountId,
      'amount': amount.round(),
      'note': note,
    };
