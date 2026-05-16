// Spec: specs/003-trabajos-muebles/spec.md
//
// Pie del formulario de trabajo (Feature 003): totales, botón de guardar
// y acciones del ciclo de vida (avanzar, anticipo, cancelar). Extraído de
// `work_order_form_screen.dart` para mantener cada archivo bajo el límite
// de 800 líneas (Constitución Art. IX).

import 'package:flutter/material.dart';

import '../../models/work_order.dart';
import '../../theme/app_theme.dart';
import 'work_order_widgets.dart';

/// Pie de pantalla del formulario/detalle de un trabajo.
///
/// En modo creación/edición muestra el total y el botón "Guardar". En
/// modo detalle de un trabajo no editable muestra los totales (total /
/// abonado / saldo) y los botones de transición, anticipo y cancelar.
class WorkOrderFooter extends StatelessWidget {
  /// Trabajo vivo; `null` si aún no se ha guardado (modo creación).
  final WorkOrder? order;

  /// Total computado de los ítems en el formulario (mientras se arma).
  final double computedTotal;

  /// `true` mientras se está guardando (deshabilita el botón).
  final bool saving;

  /// `true` mientras una acción del ciclo de vida está en curso.
  final bool busy;

  /// `true` si el formulario está editando un trabajo existente.
  final bool isEditing;

  final VoidCallback onSave;
  final VoidCallback onAdvance;
  final VoidCallback onAddPayment;
  final VoidCallback onCancelOrder;

  const WorkOrderFooter({
    super.key,
    required this.order,
    required this.computedTotal,
    required this.saving,
    required this.busy,
    required this.isEditing,
    required this.onSave,
    required this.onAdvance,
    required this.onAddPayment,
    required this.onCancelOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(color: AppTheme.borderColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          _totalsRow(),
          const SizedBox(height: 12),
          SafeArea(
            minimum: const EdgeInsets.only(bottom: 24),
            child: _footerActions(),
          ),
        ],
      ),
    );
  }

  Widget _totalsRow() {
    final o = order;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total del trabajo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              workOrderMoney(
                  o != null && o.total > 0 ? o.total : computedTotal),
              key: const Key('text_work_total'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        if (o != null && (o.paid > 0 || o.balance > 0)) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Abonado ${workOrderMoney(o.paid)}',
                style: const TextStyle(
                    fontSize: 18, color: AppTheme.textSecondary),
              ),
              Text(
                'Saldo ${workOrderMoney(o.balance)}',
                key: const Key('text_work_balance'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: o.balance > 0
                      ? AppTheme.warning
                      : AppTheme.success,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// En modo creación/edición es "Guardar"; en modo detalle ofrece
  /// avanzar el ciclo, registrar anticipo y cancelar.
  Widget _footerActions() {
    final o = order;
    if (o == null || o.isEditable) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              key: const Key('btn_save_work_order'),
              onPressed: saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isEditing ? 'Guardar cambios' : 'Guardar trabajo',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          if (o != null) ...[
            const SizedBox(height: 12),
            _lifecycleButtons(o),
          ],
        ],
      );
    }
    return _lifecycleButtons(o);
  }

  /// Botones de avance del ciclo, anticipo y cancelar — modo detalle.
  Widget _lifecycleButtons(WorkOrder o) {
    final next = o.nextStatus;
    return Column(
      children: [
        if (next != null)
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              key: const Key('btn_advance_work_order'),
              onPressed: (busy || !o.canAdvance) ? null : onAdvance,
              icon: const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 24),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                disabledBackgroundColor: AppTheme.borderColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              label: Text(
                'Pasar a "${WorkOrder.statusLabels[next]}"',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (o.balance > 0)
              Expanded(
                child: _SecondaryAction(
                  keyValue: 'btn_add_payment',
                  label: 'Anticipo',
                  icon: Icons.payments_rounded,
                  color: AppTheme.success,
                  onPressed: busy ? null : onAddPayment,
                ),
              ),
            if (o.balance > 0 && o.canCancel) const SizedBox(width: 12),
            if (o.canCancel)
              Expanded(
                child: _SecondaryAction(
                  keyValue: 'btn_cancel_work_order',
                  label: 'Cancelar',
                  icon: Icons.close_rounded,
                  color: AppTheme.error,
                  onPressed: busy ? null : onCancelOrder,
                ),
              ),
          ],
        ),
        if (o.isTerminal)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Este trabajo ya está cerrado.',
              style:
                  TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// Botón secundario con borde de color semántico (anticipo / cancelar).
class _SecondaryAction extends StatelessWidget {
  final String keyValue;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _SecondaryAction({
    required this.keyValue,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        key: Key(keyValue),
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 22),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
