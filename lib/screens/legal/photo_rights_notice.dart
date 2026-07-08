// Spec: specs/098-aporte-automatico-fotos-colaborativo/spec.md
//
// Adenda A (blindaje legal). Aviso ÚNICO por dispositivo de derechos sobre las
// fotos, mostrado la primera vez que el tendero sube/toma una foto MANUAL de
// producto (galería o cámara). No aplica a la generación con IA (esas fotos son
// nuestras). No es fricción por-foto: se muestra una sola vez y se recuerda con
// SharedPreferences.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

/// Clave persistente: una vez el tendero confirma el aviso, no vuelve a verlo.
const String kPhotoRightsAckKey = 'vendia_photo_rights_ack';

/// Muestra UNA sola vez (por dispositivo) el aviso de derechos sobre las fotos
/// antes de que el tendero suba/tome una foto manual. Si ya fue confirmado,
/// retorna sin hacer nada. Al cerrar el diálogo, marca la bandera en
/// SharedPreferences para no volver a mostrarlo.
///
/// No bloquea el flujo: es informativo, con un solo botón "Entendido".
Future<void> maybeShowPhotoRightsNotice(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kPhotoRightsAckKey) == true) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Sobre las fotos que sube',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      content: const SingleChildScrollView(
        child: Text(
          'Al cargar o tomar fotos de productos con código de barras, confirma '
          'que la foto es suya o que tiene derechos para usarla, y que podrá '
          'sugerirse a otras tiendas de la red VendIA. No suba fotos de '
          'terceros (Google, catálogos de otras marcas).',
          style: TextStyle(fontSize: 16, height: 1.45),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text(
            'Entendido',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  // Persistir después de mostrar (aunque cierre tocando fuera): el aviso ya se
  // vio, no debe repetirse por foto.
  await prefs.setBool(kPhotoRightsAckKey, true);
}
