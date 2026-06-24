// Spec: specs/033-difusion-promociones/spec.md
//
// Asistente de Lista de Difusión nativa de WhatsApp Business (F033 —
// spec §4.5 mejora 4, AC-06b).
//
// Para audiencias grandes (>50) la cola asistida 1-a-1 es insoportable.
// WhatsApp Business YA tiene "Listas de Difusión" gratis — pero hay que
// armarlas a mano con los contactos guardados. Esta pantalla quita esa
// fricción:
//
//   1. Genera un archivo vCard (.vcf) con todos los contactos
//      seleccionados, listo para importar a la agenda del teléfono.
//   2. Copia el mensaje pre-formateado al portapapeles.
//   3. Muestra el instructivo de 3 pasos para crear la Lista de
//      Difusión nativa.
//
// Trade-off honesto que el spec exige comunicar: WhatsApp solo entrega
// un Broadcast a contactos que tienen al dueño guardado en SU agenda.
// La pantalla lo dice claramente.
//
// Cross-platform: el .vcf se comparte con `Share.shareXFiles` +
// `XFile.fromData` (bytes en memoria) — sin tocar el sistema de
// archivos, así funciona también en Flutter web.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/customer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Construye el contenido de un archivo vCard 3.0 con los [customers].
///
/// Cada contacto que tenga teléfono produce una tarjeta `BEGIN:VCARD`.
/// Los clientes sin teléfono se omiten — no sirven para una Lista de
/// Difusión de WhatsApp. Función pura, testeable de forma aislada.
String buildVCard(List<Customer> customers) {
  final buffer = StringBuffer();
  for (final c in customers) {
    final phone = c.phone.trim();
    if (phone.isEmpty) continue;
    final name = c.name.trim().isEmpty ? 'Cliente' : c.name.trim();
    buffer
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0')
      ..writeln('FN:$name')
      ..writeln('N:$name;;;;')
      ..writeln('TEL;TYPE=CELL:$phone')
      ..writeln('END:VCARD');
  }
  return buffer.toString();
}

class BroadcastListHelperScreen extends StatelessWidget {
  /// Clientes seleccionados para la difusión.
  final List<Customer> customers;

  /// Mensaje pre-formateado (ya con el link público) que el dueño
  /// pegará en la Lista de Difusión.
  final String message;

  /// Inyectable para tests — comparte el .vcf. En producción usa
  /// `Share.shareXFiles`.
  final Future<void> Function(XFile file)? shareOverride;

  const BroadcastListHelperScreen({
    super.key,
    required this.customers,
    required this.message,
    this.shareOverride,
  });

  /// Clientes que sí tienen teléfono — los únicos exportables.
  List<Customer> get _withPhone =>
      customers.where((c) => c.phone.trim().isNotEmpty).toList();

  Future<void> _exportVCard(BuildContext context) async {
    HapticFeedback.lightImpact();
    final exportable = _withPhone;
    if (exportable.isEmpty) {
      _snack(context, 'Ningún cliente seleccionado tiene teléfono.');
      return;
    }
    final vcard = buildVCard(exportable);
    final bytes = Uint8List.fromList(utf8.encode(vcard));
    final file = XFile.fromData(
      bytes,
      name: 'clientes_vendia.vcf',
      mimeType: 'text/vcard',
    );
    if (shareOverride != null) {
      await shareOverride!(file);
    } else {
      await Share.shareXFiles(
        [file],
        text: 'Contactos para tu Lista de Difusión',
      );
    }
  }

  Future<void> _copyMessage(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: message));
    if (context.mounted) {
      _snack(context, 'Mensaje copiado — péguelo en la difusión.');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exportable = _withPhone;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: const Text(
          'Lista de Difusión',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${exportable.length} '
              '${exportable.length == 1 ? 'contacto' : 'contactos'} '
              'con teléfono',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            // Instructivo de 3 pasos.
            const _StepTile(
              number: 1,
              title: 'Importe los contactos',
              body: 'Descargue el archivo de contactos y ábralo para '
                  'agregarlos a la agenda de su teléfono.',
            ),
            const _StepTile(
              number: 2,
              title: 'Cree la difusión en WhatsApp Business',
              body: 'En WhatsApp Business toque ⋮ → "Nueva difusión" y '
                  'seleccione los contactos que acaba de importar.',
            ),
            const _StepTile(
              number: 3,
              title: 'Pegue el mensaje y envíe',
              body: 'Pegue el mensaje copiado en el chat de la '
                  'difusión y envíelo. ¡Listo!',
              isLast: true,
            ),
            const SizedBox(height: 8),
            // Trade-off honesto (spec §4.5 mejora 4).
            Container(
              key: const Key('broadcast_limitation_note'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.35)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.warning, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'WhatsApp solo entrega la difusión a clientes que '
                      'lo tengan guardado a usted en su agenda. A los '
                      'demás, avíseles con la cola asistida.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                key: const Key('broadcast_export_vcard'),
                onPressed: () => _exportVCard(context),
                icon: const Icon(Icons.download_rounded, size: 24),
                label: const Text(
                  'Descargar contactos (.vcf)',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: OutlinedButton.icon(
                key: const Key('broadcast_copy_message'),
                onPressed: () => _copyMessage(context),
                icon: const Icon(Icons.copy_rounded, size: 22),
                label: const Text(
                  'Copiar mensaje',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una fila del instructivo numerado.
class _StepTile extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final bool isLast;

  const _StepTile({
    required this.number,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 16 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
