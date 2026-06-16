// Spec: specs/060-logo-ia-editor/spec.md
//
// Módulo para mejorar/editar el logo con IA desde la app/PWA. El tendero
// escribe especificaciones claras (colores, estilo, símbolos), genera,
// previsualiza y puede iterar ("probar otra vez") con nuevas
// indicaciones hasta que le guste, sin salir del flujo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Mínimo de caracteres de especificación que el backend exige
/// (`minLogoDetailsLength`); lo validamos también acá para no quemar una
/// llamada a la IA con un prompt vacío.
const int kLogoSpecsMinLength = 12;

/// Abre el editor de logo con IA. [onGenerate] recibe las
/// especificaciones y devuelve la URL del logo generado (o null si
/// falló). [onSaved] se llama con la URL cuando el tendero la acepta.
Future<void> showLogoAiEditor(
  BuildContext context, {
  String? currentLogoUrl,
  String initialSpecs = '',
  required Future<String?> Function(String specs) onGenerate,
  required void Function(String url) onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LogoAiEditorSheet(
      currentLogoUrl: currentLogoUrl,
      initialSpecs: initialSpecs,
      onGenerate: onGenerate,
      onSaved: onSaved,
    ),
  );
}

class _LogoAiEditorSheet extends StatefulWidget {
  const _LogoAiEditorSheet({
    this.currentLogoUrl,
    this.initialSpecs = '',
    required this.onGenerate,
    required this.onSaved,
  });

  final String? currentLogoUrl;
  final String initialSpecs;
  final Future<String?> Function(String specs) onGenerate;
  final void Function(String url) onSaved;

  @override
  State<_LogoAiEditorSheet> createState() => _LogoAiEditorSheetState();
}

enum _Stage { input, generating, preview }

class _LogoAiEditorSheetState extends State<_LogoAiEditorSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialSpecs);
  _Stage _stage = _Stage.input;
  String? _previewUrl;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final specs = _ctrl.text.trim();
    if (specs.length < kLogoSpecsMinLength) {
      setState(() => _error =
          'Describa su logo con al menos $kLogoSpecsMinLength caracteres '
          '(colores, estilo, símbolos…).');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _stage = _Stage.generating;
    });
    try {
      final url = await widget.onGenerate(specs);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() {
          _stage = _Stage.input;
          _error = 'No se pudo generar el logo. Intente de nuevo.';
        });
        return;
      }
      setState(() {
        _previewUrl = url;
        _stage = _Stage.preview;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.input;
        _error = 'No se pudo generar el logo: $e';
      });
    }
  }

  void _use() {
    if (_previewUrl == null) return;
    HapticFeedback.mediumImpact();
    widget.onSaved(_previewUrl!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '✨ Mejorar logo con IA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            if (_stage == _Stage.generating)
              _buildGenerating()
            else if (_stage == _Stage.preview)
              _buildPreview()
            else
              _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.currentLogoUrl != null &&
            widget.currentLogoUrl!.isNotEmpty) ...[
          Center(child: _logoThumb(widget.currentLogoUrl!)),
          const SizedBox(height: 4),
          const Center(
            child: Text('Logo actual',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'Dígale a la IA cómo quiere su logo',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('logo_ai_specs_input'),
          controller: _ctrl,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText:
                'Ej: colores verde y naranja, una fruta sonriente, estilo '
                'moderno y limpio, fondo claro',
            errorText: _error,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('logo_ai_generate_btn'),
          onPressed: _generate,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Generar logo'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            minimumSize: const Size.fromHeight(52),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildGenerating() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          CircularProgressIndicator(color: Color(0xFF8B5CF6), strokeWidth: 3),
          SizedBox(height: 20),
          Text(
            'Diseñando su logo…\nesto tomará unos segundos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _logoThumb(_previewUrl!, size: 140)),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('logo_ai_use_btn'),
          onPressed: _use,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Usar este logo'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            minimumSize: const Size.fromHeight(52),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('logo_ai_retry_btn'),
          onPressed: () => setState(() => _stage = _Stage.input),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Ajustar y probar otra vez'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _logoThumb(String url, {double size = 96}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDE8E0)),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
      ),
    );
  }
}
