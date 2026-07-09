// Spec: specs/101-retocar-fotos-inventario/spec.md
//
// Tarjetas del flujo "Retocar fotos" (RetouchCompletionScreen), extraídas a
// widgets propios (Art. IX: archivos < 800 líneas; REFACTOR del patrón
// 097/100). Sin estado propio: la pantalla es la dueña del estado y pasa
// callbacks.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_ui.dart';
import 'compact_action_button.dart';
import 'product_image.dart';

/// Revisión antes/después de un ítem del lote (FR-05): el tendero ve que la
/// IA no le "inventó" otro producto y decide Confirmar o Descartar — nada se
/// aplica solo.
class RetouchReviewCard extends StatelessWidget {
  const RetouchReviewCard({
    super.key,
    required this.name,
    required this.originalUrl,
    required this.candidateUrl,
    required this.busy,
    required this.onConfirm,
    required this.onDiscard,
  });

  final String name;
  final String originalUrl;
  final String candidateUrl;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppUI.bodyStrong),
          const SizedBox(height: AppUI.s8),
          Row(children: [
            Expanded(child: _labeledPhoto('Antes', originalUrl)),
            const SizedBox(width: AppUI.s8),
            const Icon(Icons.arrow_forward_rounded,
                color: AppUI.inkSoft, size: 20),
            const SizedBox(width: AppUI.s8),
            Expanded(child: _labeledPhoto('Después', candidateUrl)),
          ]),
          const SizedBox(height: AppUI.s12),
          if (busy)
            const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            // AppButton del kit: estilo explícito, sin el theme legacy de
            // OutlinedButton (texto 22px) que inflaba Descartar/Confirmar.
            Row(children: [
              Expanded(
                child: AppButton(
                  label: 'Descartar',
                  variant: AppButtonVariant.secondary,
                  onPressed: onDiscard,
                ),
              ),
              const SizedBox(width: AppUI.s8),
              Expanded(
                child: AppButton(label: 'Confirmar', onPressed: onConfirm),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _labeledPhoto(String label, String url) {
    return Column(children: [
      Text(label, style: AppUI.bodySoft),
      const SizedBox(height: 4),
      Container(
        height: 96,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppUI.pageBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppUI.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ProductImage(
          url: url.isEmpty ? null : url,
          height: 96,
          fit: BoxFit.cover,
          placeholder: const Icon(Icons.image_outlined,
              color: AppUI.inkSoft, size: 28),
        ),
      ),
    ]);
  }
}

/// Referencia con foto cruda pendiente de retoque (FR-04): foto actual,
/// nombre y precio con la acción ÚNICA "Mejorar foto" (modo fiel vía lote
/// de 1); encolada, muestra el estado sin ansiedad.
class RetouchPendingCard extends StatelessWidget {
  const RetouchPendingCard({
    super.key,
    required this.name,
    required this.priceLabel,
    required this.photoUrl,
    required this.busy,
    required this.queued,
    required this.onRetouch,
  });

  final String name;
  final String priceLabel;
  final String? photoUrl;
  final bool busy;
  final bool queued;
  final VoidCallback onRetouch;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: AppUI.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(),
              const SizedBox(width: AppUI.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppUI.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      priceLabel,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          const SizedBox(height: AppUI.s12),
          if (queued)
            const Row(children: [
              Icon(Icons.hourglass_top_rounded,
                  color: AppUI.inkSoft, size: 18),
              SizedBox(width: AppUI.s8),
              Expanded(
                child: Text('La IA está retocando esta foto…',
                    style: AppUI.bodySoft),
              ),
            ])
          else if (!busy)
            CompactActionButton(
              icon: Icons.auto_awesome,
              label: 'Mejorar foto',
              onPressed: onRetouch,
            ),
        ],
      ),
    );
  }

  Widget _thumb() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppUI.pageBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppUI.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ProductImage(
        url: photoUrl,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: const Icon(Icons.inventory_2_outlined,
            color: AppUI.inkSoft, size: 24),
      ),
    );
  }
}
