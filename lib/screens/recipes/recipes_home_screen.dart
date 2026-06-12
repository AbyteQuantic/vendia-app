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

import '../../theme/app_theme.dart';
import '../inventory/voice_inventory_screen.dart';
import 'recipe_step1_screen.dart';

class RecipesHomeScreen extends StatelessWidget {
  const RecipesHomeScreen({super.key});

  void _go(BuildContext context, Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // Fase 2 (pendiente de visto bueno del dueño — ver spec §5/§6): el OCR de menú
  // necesita un endpoint de IA dedicado. Hasta entonces, guiamos al tendero a
  // los otros dos caminos en vez de dar resultados pobres con el scanner de
  // facturas. NO rompe nada: solo informa y no navega a un flujo equivocado.
  void _cameraComingSoon(BuildContext context) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pronto: lectura de tu menú con IA desde una foto. Por ahora arma tus '
          'platos con "Crear plato o receta" o dictándolos por voz.',
          style: TextStyle(fontSize: 15),
        ),
        duration: Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            onTap: () => _cameraComingSoon(context),
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
