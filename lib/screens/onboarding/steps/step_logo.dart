import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

/// Paso 5 — La imagen de su negocio.
///
/// Generates / uploads the logo BEFORE the tenant exists. Two public
/// onboarding endpoints (POST /api/v1/auth/preview-logo and
/// /preview-logo-upload) handle the work; the URL they return is
/// stored on the controller (`logoUrl`) and folded into the
/// register payload at step 6 so the merchant lands on the
/// dashboard with their brand mark already in place.
///
/// Importantly the merchant SEES the generated logo right here and
/// can hit "Regenerar" until they're happy — fixing the previous
/// dead-end where logos got applied invisibly after "Crear cuenta".
class StepLogo extends StatefulWidget {
  const StepLogo({super.key});

  @override
  State<StepLogo> createState() => _StepLogoState();
}

enum _LogoStatus { idle, generating, ready, uploading, error }

class _StepLogoState extends State<StepLogo> {
  static const int _minDetailsLength = 12;

  late final ApiService _api;
  late final TextEditingController _detailsCtrl;

  _LogoStatus _status = _LogoStatus.idle;
  String? _errorMsg;

  bool get _detailsValid =>
      _detailsCtrl.text.trim().length >= _minDetailsLength;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    final ctrl = context.read<OnboardingStepperController>();
    _detailsCtrl = TextEditingController(text: ctrl.logoDescription)
      ..addListener(() {
        ctrl.logoDescription = _detailsCtrl.text.trim();
        setState(() {});
      });
  }

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateWithAI() async {
    HapticFeedback.lightImpact();
    if (!_detailsValid) return;
    final ctrl = context.read<OnboardingStepperController>();
    setState(() {
      _status = _LogoStatus.generating;
      _errorMsg = null;
    });
    try {
      final data = await _api.previewLogoIA(
        businessName: ctrl.businessName,
        businessType: ctrl.businessType,
        details: _detailsCtrl.text.trim(),
      );
      final url = data['logo_url'] as String?;
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() {
          _status = _LogoStatus.error;
          _errorMsg = 'La IA no devolvió un logo. Intente de nuevo.';
        });
        return;
      }
      ctrl.setLogoUrl(url);
      setState(() => _status = _LogoStatus.ready);
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
      _errorMsg = null;
    });
    try {
      final data = await _api.previewLogoUpload(File(picked.path));
      final url = data['logo_url'] as String?;
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() {
          _status = _LogoStatus.error;
          _errorMsg = 'No se pudo subir la imagen.';
        });
        return;
      }
      context.read<OnboardingStepperController>().setLogoUrl(url);
      setState(() => _status = _LogoStatus.ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _LogoStatus.error;
        _errorMsg = 'No se pudo subir la imagen. Intente de nuevo.';
      });
    }
  }

  void _clearLogo() {
    HapticFeedback.lightImpact();
    context.read<OnboardingStepperController>().clearLogo();
    setState(() {
      _status = _LogoStatus.idle;
      _errorMsg = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<OnboardingStepperController>();
    final hasLogo = ctrl.logoUrl.isNotEmpty;
    final busy = _status == _LogoStatus.generating ||
        _status == _LogoStatus.uploading;

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
            'la diseñará en segundos usando lo que cuente abajo, o puede '
            'subir una imagen propia. Si no le gusta, puede regenerar.',
            style: TextStyle(
                fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          // ── Live preview ──────────────────────────────────────────
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                    color: hasLogo
                        ? AppTheme.success
                        : AppTheme.borderColor,
                    width: hasLogo ? 2.5 : 1.5),
              ),
              clipBehavior: Clip.hardEdge,
              child: _buildPreview(busy, hasLogo, ctrl.logoUrl),
            ),
          ),
          const SizedBox(height: 8),
          if (hasLogo)
            Center(
              child: TextButton.icon(
                onPressed: _clearLogo,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Empezar de cero'),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary),
              ),
            ),
          const SizedBox(height: 14),

          if (_errorMsg != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMsg!,
                        style: const TextStyle(
                            fontSize: 16, color: AppTheme.error)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Title row (Wrap so the obligatorio pill drops cleanly)─
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            'Cuéntenos qué vende, qué lo distingue, colores que le gusten… '
            'La IA usa esto para acertar.',
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

          // ── IA action ─────────────────────────────────────────────
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
                  : (hasLogo
                      ? 'Regenerar con IA'
                      : 'Generar Logo con IA'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),

          // ── Gallery upload ────────────────────────────────────────
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
                  : (hasLogo
                      ? 'Cambiar por otra imagen'
                      : 'Subir foto de mi galería'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              hasLogo
                  ? 'Su logo se aplicará automáticamente al crear la cuenta.'
                  : 'También puede saltar este paso y configurarlo después.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(bool busy, bool hasLogo, String url) {
    if (busy) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 8),
            Text(
              _status == _LogoStatus.generating
                  ? 'Diseñando con IA...'
                  : 'Subiendo imagen...',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    if (hasLogo) {
      return Image.network(url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    size: 48, color: AppTheme.textSecondary),
              ));
    }
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storefront_rounded,
              size: 56, color: AppTheme.textSecondary),
          SizedBox(height: 6),
          Text('Su logo aparecerá aquí',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
