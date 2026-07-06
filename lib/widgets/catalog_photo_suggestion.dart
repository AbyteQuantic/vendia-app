// Spec: specs/096-foto-referencia-verificada/spec.md
//
// Sugerencia OPCIONAL de foto de catálogo (Open Food Facts, verificada por
// código de barras) al crear/editar un producto. Nunca reemplaza ni se
// aplica sola — "Mejorar con IA" y "Recortar el fondo con IA" (Specs
// 017/094) no se tocan; esta es una tercera fuente de imagen distinta. Sin
// match o sin conexión, el widget queda vacío (AC-04) — cero fricción.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class CatalogPhotoSuggestion extends StatefulWidget {
  const CatalogPhotoSuggestion({
    super.key,
    required this.barcode,
    required this.onAccept,
    this.apiOverride,
  });

  final String barcode;

  /// Se llama con la URL de la foto cuando el tendero confirma usarla.
  final ValueChanged<String> onAccept;
  final ApiService? apiOverride;

  @override
  State<CatalogPhotoSuggestion> createState() =>
      _CatalogPhotoSuggestionState();
}

class _CatalogPhotoSuggestionState extends State<CatalogPhotoSuggestion> {
  late final ApiService _api = widget.apiOverride ?? ApiService(AuthService());
  Map<String, dynamic>? _photo;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _api.fetchCatalogReferencePhoto(widget.barcode);
      if (!mounted || result == null) return;
      setState(() => _photo = result);
    } catch (_) {
      // Cualquier falla (red, servicio no inicializado, etc.) simplemente
      // no muestra la sugerencia — nunca debe romper el formulario del
      // tendero por una foto opcional (AC-04).
    }
  }

  Future<void> _showConfirmation() async {
    HapticFeedback.lightImpact();
    final imageUrl = _photo!['image_url'] as String;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(imageUrl,
                    height: 120, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        height: 120,
                        child: Icon(Icons.image_not_supported_outlined,
                            size: 40, color: AppTheme.textSecondary))),
              ),
              const SizedBox(height: 12),
              const Text(
                'Esta foto es de un catálogo público, no una foto de SU '
                'producto. El empaque, tamaño o etiqueta pueden verse '
                'distintos al que usted vende.',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Usar esta foto'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Tomar la mía'),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true) {
      widget.onAccept(imageUrl);
      if (mounted) setState(() => _dismissed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_photo == null || _dismissed) return const SizedBox.shrink();

    final imageUrl = _photo!['image_url'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: imageUrl.isEmpty
                  ? const Icon(Icons.image_outlined)
                  : Image.network(imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_not_supported_outlined)),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '📷 Encontramos una foto de este producto — ¿la quiere usar?',
              style: TextStyle(fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: _showConfirmation,
            child: const Text('Ver foto'),
          ),
          TextButton(
            onPressed: () => setState(() => _dismissed = true),
            child: const Text('No, gracias'),
          ),
        ],
      ),
    );
  }
}
