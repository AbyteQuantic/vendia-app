import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso 5 — La imagen de su negocio.
///
/// IMPORTANT: this step now sits BEFORE registration. The merchant
/// asked for "no se debería crear la cuenta sin un logo" — so the
/// flow is reordered to: data collection (1-4) → logo (5) → empleados
/// + Crear cuenta (6).
///
/// Both the IA endpoint and the upload endpoint require a tenant_id,
/// which doesn't exist yet at this point in the flow. We capture the
/// merchant's intent locally on the controller (`logoIntent` +
/// `logoDescription` / `logoLocalPath`) and replay the API calls in
/// submit() AFTER registerTenantFull() lands a real JWT. From the
/// merchant's POV the logo is "applied" by the same "Crear cuenta"
/// click as the registration itself — atomic from their perspective.
class StepLogo extends StatefulWidget {
  const StepLogo({super.key});

  @override
  State<StepLogo> createState() => _StepLogoState();
}

class _StepLogoState extends State<StepLogo> {
  static const int _minDetailsLength = 12;

  late final TextEditingController _detailsCtrl;
  String? _localPreviewPath;

  bool get _detailsValid =>
      _detailsCtrl.text.trim().length >= _minDetailsLength;

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<OnboardingStepperController>();
    // Hydrate from any prior visit so the merchant doesn't have to
    // retype after going Back.
    _detailsCtrl =
        TextEditingController(text: ctrl.logoDescription)
          ..addListener(() {
            ctrl.logoDescription = _detailsCtrl.text.trim();
            setState(() {});
          });
    _localPreviewPath =
        ctrl.logoLocalPath.isNotEmpty ? ctrl.logoLocalPath : null;
  }

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickGallery() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;
    setState(() => _localPreviewPath = picked.path);
    context.read<OnboardingStepperController>().setLogoFile(picked.path);
  }

  void _commitIntentIA() {
    HapticFeedback.lightImpact();
    if (!_detailsValid) return;
    context.read<OnboardingStepperController>()
        .setLogoIA(_detailsCtrl.text.trim());
    setState(() => _localPreviewPath = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      content: Text(
        '✓ Logo se diseñará al crear la cuenta',
        style: TextStyle(fontSize: 16),
      ),
    ));
  }

  void _clearChoice() {
    setState(() => _localPreviewPath = null);
    context.read<OnboardingStepperController>().clearLogoIntent();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<OnboardingStepperController>();
    final intent = ctrl.logoIntent;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'La imagen de su negocio',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Antes de crear la cuenta, dele identidad a su negocio. La IA '
            'la diseñará usando lo que cuente abajo, o puede subir una '
            'imagen propia. También puede saltar este paso.',
            style: TextStyle(
                fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          // ── Preview / status ──────────────────────────────────────
          Center(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                    color: intent.isNotEmpty
                        ? AppTheme.success
                        : AppTheme.borderColor,
                    width: intent.isNotEmpty ? 2.5 : 1.5),
              ),
              clipBehavior: Clip.hardEdge,
              child: _buildPreview(intent),
            ),
          ),
          const SizedBox(height: 6),
          if (intent == 'ai')
            Center(
              child: Text(
                '✨ La IA diseñará su logo al crear la cuenta',
                style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600),
              ),
            )
          else if (intent == 'gallery')
            Center(
              child: Text(
                '✓ Imagen lista para subir al crear la cuenta',
                style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 18),

          // ── Title row (Wrap so the obligatorio pill drops cleanly) ─
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '¿Qué hace especial a su negocio?',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Obligatorio para IA',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.error,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Cuéntenos qué vende, qué lo distingue, colores que le '
            'gusten… La IA usa esto para acertar.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsCtrl,
            maxLines: 3,
            minLines: 2,
            maxLength: 240,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Ej: Tienda de barrio que también vende helados '
                  'artesanales de frutas naturales. Me gusta el color verde.',
              hintStyle:
                  TextStyle(fontSize: 14, color: Colors.grey.shade500),
              filled: true,
              fillColor: AppTheme.surfaceGrey,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
              counterText: '',
            ),
          ),
          const SizedBox(height: 6),
          _detailsValid
              ? Row(children: const [
                  Icon(Icons.check_circle_rounded,
                      color: AppTheme.success, size: 18),
                  SizedBox(width: 6),
                  Text('¡Listo! Ya puede elegir IA.',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600)),
                ])
              : Text(
                  'Escriba al menos $_minDetailsLength caracteres '
                  '(${_detailsCtrl.text.trim().length}/$_minDetailsLength) '
                  'para activar la generación con IA.',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 16),

          // ── IA option ─────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _detailsValid ? _commitIntentIA : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF7C3AED).withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 22),
            label: Text(
              intent == 'ai'
                  ? '✓ Listo para diseñar con IA'
                  : 'Diseñar Logo con IA',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),

          // ── Gallery upload option ─────────────────────────────────
          OutlinedButton.icon(
            onPressed: _pickGallery,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              minimumSize: const Size(double.infinity, 60),
              side: const BorderSide(color: AppTheme.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.photo_library_rounded, size: 22),
            label: Text(
              intent == 'gallery'
                  ? '✓ Cambiar imagen'
                  : 'Subir foto de mi galería',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          if (intent.isNotEmpty)
            Center(
              child: TextButton.icon(
                onPressed: _clearChoice,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Quitar elección'),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary),
              ),
            )
          else
            Center(
              child: Text(
                'También puede saltar este paso y configurarlo después.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview(String intent) {
    if (intent == 'gallery' && _localPreviewPath != null) {
      return Image.file(File(_localPreviewPath!), fit: BoxFit.cover);
    }
    if (intent == 'ai') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.auto_awesome_rounded,
                size: 56, color: Color(0xFF7C3AED)),
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Lista para IA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF7C3AED),
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.storefront_rounded,
              size: 56, color: AppTheme.textSecondary),
          SizedBox(height: 6),
          Text('Su logo aquí',
              style:
                  TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
