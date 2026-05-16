// Spec: specs/003-trabajos-muebles/spec.md
//
// Diálogos del formulario de trabajo (Feature 003): agregar material,
// agregar mano de obra y registrar un anticipo. Extraídos del formulario
// para mantener cada archivo bajo el límite de 800 líneas (Art. IX).

import 'package:flutter/material.dart';

import '../../models/work_order.dart';
import '../../theme/app_theme.dart';
import 'work_order_widgets.dart';

/// Convierte un texto del usuario a número, tolerando separadores de
/// miles (`.`) y la coma decimal colombiana.
double parseWorkAmount(String raw) {
  final clean = raw.trim().replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(clean) ?? 0;
}

/// Pide cantidad y precio de un ítem de material para el insumo/producto
/// `source`. Devuelve el `WorkOrderItem` listo o `null` si se cancela.
Future<WorkOrderItem?> promptMaterialItem(
  BuildContext context,
  WorkMaterialSource source, {
  WorkOrderItem? existing,
}) async {
  final qtyCtrl = TextEditingController(
    text: existing != null ? workOrderTrim(existing.quantity) : '',
  );
  final priceCtrl = TextEditingController(
    text: existing != null
        ? workOrderTrim(existing.unitPrice)
        : (source.unitCost > 0 ? workOrderTrim(source.unitCost) : ''),
  );
  String? err;

  final result = await showDialog<WorkOrderItem>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: Text(
          source.name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cantidad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('field_material_quantity'),
              controller: qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(hintText: '0', errorText: err),
            ),
            const SizedBox(height: 16),
            const Text('Costo por unidad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('field_material_price'),
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                prefixText: '\$ ',
                hintText: '0',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            key: const Key('btn_confirm_material'),
            onPressed: () {
              final qty = parseWorkAmount(qtyCtrl.text);
              final price = parseWorkAmount(priceCtrl.text);
              if (qty <= 0 || price <= 0) {
                setLocal(() => err =
                    'Cantidad y costo deben ser mayores que cero');
                return;
              }
              Navigator.of(ctx).pop(WorkOrderItem(
                uuid: existing?.uuid,
                kind: WorkOrderItem.kindMaterial,
                ingredientId: source.isIngredient ? source.id : null,
                productId: source.isIngredient ? null : source.id,
                description: source.name,
                quantity: qty,
                unitPrice: price,
              ));
            },
            child: const Text(
              'Agregar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  _disposeLater([qtyCtrl, priceCtrl]);
  return result;
}

/// Pide la descripción y el precio de un ítem de mano de obra. Devuelve
/// el `WorkOrderItem` listo o `null` si se cancela.
Future<WorkOrderItem?> promptLaborItem(
  BuildContext context, {
  WorkOrderItem? existing,
}) async {
  final descCtrl = TextEditingController(text: existing?.description ?? '');
  final priceCtrl = TextEditingController(
    text: existing != null ? workOrderTrim(existing.unitPrice) : '',
  );
  String? err;

  final result = await showDialog<WorkOrderItem>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: const Text(
          'Mano de obra',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Qué trabajo es?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('field_labor_description'),
              controller: descCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                hintText: 'Ej: armado y lijado',
                errorText: err,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Precio',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('field_labor_price'),
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                prefixText: '\$ ',
                hintText: '0',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            key: const Key('btn_confirm_labor'),
            onPressed: () {
              final desc = descCtrl.text.trim();
              final price = parseWorkAmount(priceCtrl.text);
              if (desc.isEmpty) {
                setLocal(() => err = 'Escriba en qué consiste el trabajo');
                return;
              }
              if (price <= 0) {
                setLocal(() => err = 'El precio debe ser mayor que cero');
                return;
              }
              Navigator.of(ctx).pop(WorkOrderItem(
                uuid: existing?.uuid,
                kind: WorkOrderItem.kindLabor,
                description: desc,
                quantity: 1,
                unitPrice: price,
              ));
            },
            child: const Text(
              'Agregar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  _disposeLater([descCtrl, priceCtrl]);
  return result;
}

/// Resultado del diálogo de anticipo: monto y método de pago.
class WorkPaymentInput {
  final double amount;
  final String method;

  const WorkPaymentInput({required this.amount, required this.method});
}

/// Métodos de pago disponibles para un anticipo (Art. V — español).
const Map<String, String> workPaymentMethods = {
  'efectivo': 'Efectivo',
  'nequi': 'Nequi',
  'daviplata': 'Daviplata',
  'transferencia': 'Transferencia',
};

/// Pide el monto y el método de un anticipo. `balance` es el saldo
/// pendiente: un anticipo no puede excederlo (spec §7, AC-02).
Future<WorkPaymentInput?> promptPayment(
  BuildContext context, {
  required double balance,
}) async {
  final amountCtrl = TextEditingController();
  String method = 'efectivo';
  String? err;

  final result = await showDialog<WorkPaymentInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: const Text(
          'Registrar anticipo',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo pendiente: ${workOrderMoney(balance)}',
              style: const TextStyle(
                  fontSize: 18, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            const Text('Monto del anticipo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('field_payment_amount'),
              controller: amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                prefixText: '\$ ',
                hintText: '0',
                errorText: err,
              ),
            ),
            const SizedBox(height: 16),
            const Text('¿Cómo pagó?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor, width: 1.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('field_payment_method'),
                  value: method,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 20,
                    color: AppTheme.textPrimary,
                    fontFamily: 'Roboto',
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 28),
                  items: workPaymentMethods.entries
                      .map((e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => method = v);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            key: const Key('btn_confirm_payment'),
            onPressed: () {
              final amount = parseWorkAmount(amountCtrl.text);
              if (amount <= 0) {
                setLocal(() => err = 'El monto debe ser mayor que cero');
                return;
              }
              if (amount > balance) {
                setLocal(() => err =
                    'El anticipo no puede pasar del saldo pendiente');
                return;
              }
              Navigator.of(ctx)
                  .pop(WorkPaymentInput(amount: amount, method: method));
            },
            child: const Text(
              'Registrar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  _disposeLater([amountCtrl]);
  return result;
}

/// Confirma una acción potencialmente irreversible (transición de estado,
/// cancelar el trabajo). Devuelve `true` si el usuario confirma.
Future<bool> confirmWorkAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Color confirmColor,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      content: Text(
        message,
        style: const TextStyle(fontSize: 18),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(
            'Cancelar',
            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            confirmLabel,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: confirmColor,
            ),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Libera los controladores tras la animación de salida del diálogo:
/// disponerlos de inmediato los deja en uso por el `AnimatedBuilder` del
/// cierre y lanza "used after being disposed".
void _disposeLater(List<TextEditingController> ctrls) {
  Future<void>.delayed(const Duration(milliseconds: 350), () {
    for (final c in ctrls) {
      c.dispose();
    }
  });
}
