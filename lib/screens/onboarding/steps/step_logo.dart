import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso final post-registro: la imagen del negocio.
///
/// Este paso SOLO se muestra después de que `OnboardingStepperController.submit()`
/// haya creado el tenant (status == success). En ese punto el JWT ya tiene
/// `tenant_id`, así que las llamadas a `/api/v1/tenant/generate-logo` y
/// `/api/v1/tenant/upload-logo` pueden ejecutarse — algo que NO funcionaba
/// cuando este step vivía pre-registro.
///
/// La IA recibe nombre del negocio + tipo de negocio (su prompt en el
/// backend ahora prescribe estilo plano vectorial, paleta limitada, sin texto,
/// safe-area, ícono industrial — ver gemini_service.go GenerateLogo).
class StepLogo extends StatefulWidget {
  const StepLogo({super.key});

  @override
  State<StepLogo> createState() => _StepLogoState();
}

enum _LogoStatus { idle, generating, ready, uploading, error }

class _StepLogoState extends State<StepLogo> {
  late final ApiService _api;

  _LogoStatus _status = _LogoStatus.idle;
  String? _logoUrl; // generated or uploaded — final URL
  String? _localPreviewPath; // for gallery uploads, before upload completes
  String? _errorMsg;

  // Free-text context the merchant types to steer the IA. Fed verbatim
  // into the prompt as a "BRAND TONE" line so the model can pick
  // industry-appropriate symbology (e.g. "vendo helados artesanales con
  // sabores de frutas" pushes the model toward an ice-cream cone with
  // mango / strawberry accents instead of a generic storefront).
  late final TextEditingController _detailsCtrl;

  // Below this character count we consider the description too thin
  // to feed the IA a meaningful symbol — "tienda" alone is not enough
  // to differentiate from the rubro default. 12 chars is roughly
  // "vendo X" — short but specific.
  static const int _minDetailsLength = 12;

  bool get _detailsValid =>
      _detailsCtrl.text.trim().length >= _minDetailsLength;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _detailsCtrl = TextEditingController()
      // Rebuild on every keystroke so the IA button enables / disables
      // and the helper-text counter updates in real time.
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateWithAI() async {
    HapticFeedback.lightImpact();
    setState(() {
      _status = _LogoStatus.generating;
      _errorMsg = null;
    });
    try {
      final ctrl = context.read<OnboardingStepperController>();
      final data = await _api.generateLogoAI(
        businessName: ctrl.businessName,
        businessType: ctrl.businessType,
        details: _detailsCtrl.text.trim(),
      );
      final url = data['logo_url'] as String?;
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() {
          _status = _LogoStatus.error;
          _errorMsg = 'La IA no devolvió un logo válido.';
        });
        return;
      }
      setState(() {
        _logoUrl = url;
        _status = _LogoStatus.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _LogoStatus.error;
        _errorMsg = 'No se pudo generar el logo. Intente de nuevo.';
      });
    }
  }

  Future<void> _uploadFromGallery() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _status = _LogoStatus.uploading;
      _localPreviewPath = picked.path;
      _errorMsg = null;
    });
    try {
      final data = await _api.uploadLogo(File(picked.path));
      final url = data['logo_url'] as String?;
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() {
          _status = _LogoStatus.error;
          _errorMsg = 'No se pudo subir la imagen.';
        });
        return;
      }
      setState(() {
        _logoUrl = url;
        _status = _LogoStatus.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _LogoStatus.error;
        _errorMsg = 'No se pudo subir la imagen. Intente de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        _status == _LogoStatus.generating || _status == _LogoStatus.uploading;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¡Su cuenta está lista! 🎉',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Para terminar, dele identidad a su negocio. Para generarlo con IA '
            'cuéntenos qué hace especial a su negocio — la IA lo necesita para '
            'acertar. También puede subir una imagen propia o saltar el paso.',
            style:
                TextStyle(fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          // ── Preview ────────────────────────────────────────────────
          Center(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: AppTheme.borderColor, width: 1.5),
              ),
              clipBehavior: Clip.hardEdge,
              child: _buildPreview(busy),
            ),
          ),
          const SizedBox(height: 20),

          // ── Brand-tone (REQUIRED for the IA) ──────────────────────
          // Validation lifted to a contract: the IA button is disabled
          // until the merchant types at least _minDetailsLength chars.
          // Without this guardrail the model produced unrelated blobs
          // (the demo phone hit "Llaveros y utensilios de moda" → a
          // brown shape with no relation to keys or fashion). Backend
          // also rejects empty / too-short details with a 400 — the
          // UI gate is just the friendlier first line of defense.
          Row(children: [
            const Text(
              '¿Qué hace especial a su negocio?',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          ]),
          const SizedBox(height: 4),
          const Text(
            'Cuéntenos en una frase qué vende, qué lo distingue, '
            'colores que le gusten… La IA usa esto para acertar.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _detailsCtrl,
            maxLines: 3,
            minLines: 2,
            maxLength: 240,
            enabled: !busy,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Ej: Tienda de barrio que también vende helados '
                  'artesanales de frutas naturales. Me gusta el color verde.',
              hintStyle: TextStyle(
                  fontSize: 14, color: Colors.grey.shade500),
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
          // Inline helper: doubles as character counter + validation.
          // Switches to a green check + "¡Listo!" once the threshold
          // is met so the merchant has a clear "I can press the
          // button now" signal.
          _detailsValid
              ? Row(children: const [
                  Icon(Icons.check_circle_rounded,
                      color: AppTheme.success, size: 18),
                  SizedBox(width: 6),
                  Text('¡Listo! Ya puede generar el logo.',
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

          if (_errorMsg != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(
                          fontSize: 16, color: AppTheme.error),
                    ),
                  ),
                ],
              ),
            ),
          if (_errorMsg != null) const SizedBox(height: 16),

          // ── Acciones ───────────────────────────────────────────────
          // IA button gated on _detailsValid — without a usable
          // description the model cannot pick an industry-appropriate
          // symbol and we'd burn a Gemini credit on a generic blob.
          ElevatedButton.icon(
            onPressed: (busy || !_detailsValid) ? null : _generateWithAI,
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
              _status == _LogoStatus.generating
                  ? 'Diseñando...'
                  : (_logoUrl != null ? 'Regenerar con IA' : 'Generar Logo con IA'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : _uploadFromGallery,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              minimumSize: const Size(double.infinity, 60),
              side: const BorderSide(color: AppTheme.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.photo_library_rounded, size: 22),
            label: Text(
              _status == _LogoStatus.uploading
                  ? 'Subiendo...'
                  : 'Subir foto de mi galería',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _logoUrl == null
                  ? 'También puede saltar este paso y configurarlo después en Ajustes.'
                  : '¡Listo! Toque "Entrar" para ir al panel.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(bool busy) {
    if (_status == _LogoStatus.generating || _status == _LogoStatus.uploading) {
      return const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    if (_logoUrl != null) {
      return Image.network(_logoUrl!, fit: BoxFit.cover);
    }
    if (_localPreviewPath != null) {
      return Image.file(File(_localPreviewPath!), fit: BoxFit.cover);
    }
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storefront_rounded,
              size: 56, color: AppTheme.textSecondary),
          SizedBox(height: 6),
          Text('Su logo aquí',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
