// Spec: specs/043-menu-restaurante-recetas/spec.md
//
// Pantalla inicial del módulo "Recetas y Platos" (F043). Reemplaza el arranque
// directo en el formulario manual por TRES caminos para armar el menú, todos
// asistidos por IA:
//   1. Importar menú desde la cámara (OCR de la carta → platos).  [Fase 2]
//   2. Crear plato o receta (flujo manual actual).
//   3. Dictar receta desde el micrófono (voz → IA).
// Objetivos táctiles grandes y copy claro (Art. I, tenderos 50+).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../inventory/voice_inventory_screen.dart';
import 'menu_import_screen.dart';
import 'recipe_step1_screen.dart';

class RecipesHomeScreen extends StatelessWidget {
  const RecipesHomeScreen({super.key});

  void _go(BuildContext context, Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // Fase 2 (F043): importar el menú desde una foto de la carta. Toma la foto,
  // la manda al endpoint de IA `/menu/scan-photo` y abre el editor de platos
  // (MenuImportScreen) para que el tendero revise/edite antes de publicar.
  // Web-safe: usa XFile.readAsBytes() + bytes (no dart:io File ni XFile.path).
  Future<void> _importFromCamera(BuildContext context) async {
    HapticFeedback.lightImpact();
    final source = await _pickSource(context);
    if (source == null || !context.mounted) return;

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (photo == null || !context.mounted) return;

    final bytes = await photo.readAsBytes();
    const maxBytes = 8 * 1024 * 1024; // 8 MB (igual que el backend)
    if (bytes.lengthInBytes > maxBytes) {
      if (!context.mounted) return;
      _snack(context,
          'La foto es muy pesada. Tómala con buena luz y un poco más de lejos.',
          color: AppTheme.warning);
      return;
    }
    if (!context.mounted) return;

    // Loading bloqueante mientras la IA lee la carta.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ScanningDialog(),
    );

    try {
      final api = ApiService(AuthService());
      final dishes = await api.scanMenuPhoto(
        imageBytes: bytes,
        mimeType: photo.mimeType ?? 'image/jpeg',
        filename: photo.name.isNotEmpty ? photo.name : 'menu.jpg',
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // cierra el loading

      if (dishes.isEmpty) {
        _snack(context,
            'No encontramos platos en la foto. Asegúrate de que se vea la '
            'carta con buena luz, o arma tu menú a mano.',
            color: AppTheme.warning);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MenuImportScreen(scannedDishes: dishes),
      ));
    } on AppError catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _snack(context, e.message, color: AppTheme.error);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _snack(context, 'No pudimos leer tu menú. Intenta de nuevo.',
          color: AppTheme.error);
    }
  }

  Future<ImageSource?> _pickSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('menu_source_camera'),
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppTheme.primary),
              title: const Text('Tomar foto', style: TextStyle(fontSize: 16)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('menu_source_gallery'),
              leading:
                  const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
              title: const Text('Elegir de la galería',
                  style: TextStyle(fontSize: 16)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Mi menú')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16, left: 4),
            child: Text(
              'Arma tu menú como te quede más fácil. La IA te ayuda con la foto, '
              'la descripción y las porciones — y todo lo puedes editar.',
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.3),
            ),
          ),
          _OptionCard(
            key: const Key('recipes_option_camera'),
            icon: Icons.photo_camera_rounded,
            color: const Color(0xFFEE5A24),
            title: 'Importar menú desde la cámara',
            subtitle: 'Toma una foto de tu carta y la IA arma los platos.',
            onTap: () => _importFromCamera(context),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            key: const Key('recipes_option_manual'),
            icon: Icons.restaurant_menu_rounded,
            color: AppTheme.primary,
            title: 'Crear plato o receta',
            subtitle: 'Arma un plato paso a paso y mira su costo y ganancia.',
            onTap: () => _go(context, const RecipeStep1Screen()),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            key: const Key('recipes_option_voice'),
            icon: Icons.mic_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Dictar receta desde el micrófono',
            subtitle: 'Di tus platos en voz alta y la IA los organiza.',
            onTap: () => _go(context, const VoiceInventoryScreen()),
          ),
        ],
      ),
    );
  }
}

class _ScanningDialog extends StatelessWidget {
  const _ScanningDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 20),
            Text(
              'Leyendo tu menú con IA…',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Esto puede tardar unos segundos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 13.5, color: Colors.black54, height: 1.25),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
