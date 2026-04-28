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

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
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
            'Para terminar, dele identidad a su negocio. Puede generarlo con IA '
            '(usaremos su nombre y tipo de negocio) o subir una imagen suya.',
            style: TextStyle(fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
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
          ElevatedButton.icon(
            onPressed: busy ? null : _generateWithAI,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
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
