// Spec: specs/042-modulo-eventos/spec.md
//
// Editor visual de afiche / escarapela / certificado (F042, T-42/T-43).
// El organizador tiene DOS caminos para cada pieza: (a) generarla con IA
// (Gemini) y regenerar hasta quedar conforme, o (b) subir su propia imagen.
// El backend persiste el diseño en la plantilla del evento en cada paso;
// "Usar este diseño" simplemente cierra con el último resultado.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Qué se está diseñando.
enum EventDesignKind { poster, badge, certificate }

class EventDesignScreen extends StatefulWidget {
  final String eventId;
  final EventDesignKind kind;

  /// URL del diseño actual (si ya existe), para mostrarlo al abrir.
  final String? currentImageUrl;

  /// Texto inicial del brief (típicamente la descripción del evento), para
  /// que el organizador no parta de cero al guiar a la IA.
  final String? initialBrief;
  final ApiService? apiOverride;

  const EventDesignScreen({
    super.key,
    required this.eventId,
    required this.kind,
    this.currentImageUrl,
    this.initialBrief,
    this.apiOverride,
  });

  @override
  State<EventDesignScreen> createState() => _EventDesignScreenState();
}

class _EventDesignScreenState extends State<EventDesignScreen> {
  late final ApiService _api;
  late final TextEditingController _briefCtrl;
  String? _imageUrl;
  XFile? _faceRef; // foto de rostro opcional para anclar la identidad
  bool _generating = false;
  bool _uploading = false;
  bool _enhancing = false;
  String? _error;

  bool get _busy => _generating || _uploading || _enhancing;

  /// Segmento de ruta del backend para esta pieza.
  String get _assetSlug => switch (widget.kind) {
        EventDesignKind.poster => 'poster',
        EventDesignKind.badge => 'badge',
        EventDesignKind.certificate => 'certificate',
      };

  /// Pista del campo de indicaciones según la pieza.
  String get _briefHint => switch (widget.kind) {
        EventDesignKind.poster =>
          'Describa la escena que quiere. Si sube una foto y toca "Mejorar con '
              'IA", la IA usará a la persona de la foto y recreará la escena '
              'según esto. Ej: "La docente enseñando a un grupo de alumnas a '
              'aplicar tinte color ámbar a una modelo, salón profesional".',
        EventDesignKind.badge =>
          'Estilo y colores de la escarapela. Ej: "Elegante, azul y dorado, '
              'logo del curso de repostería".',
        EventDesignKind.certificate =>
          'Estilo del certificado. Ej: "Formal, marco clásico, tonos sobrios '
              'acordes a un curso de repostería".',
      };

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _imageUrl = widget.currentImageUrl;
    _briefCtrl = TextEditingController(text: widget.initialBrief?.trim() ?? '');
  }

  @override
  void dispose() {
    _briefCtrl.dispose();
    super.dispose();
  }

  /// Elige una foto clara de rostro para anclar la identidad en el "Mejorar".
  Future<void> _pickFaceRef() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked != null) setState(() => _faceRef = picked);
  }

  /// Camino B: el organizador sube su propia imagen para la pieza.
  Future<void> _upload() async {
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await _api.uploadEventAsset(widget.eventId, _assetSlug, picked);
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'No pudimos subir la imagen. Intente con otra.';
      });
    }
  }

  /// Mejora con IA la imagen actual (la generada o la subida).
  Future<void> _enhance() async {
    setState(() {
      _enhancing = true;
      _error = null;
    });
    try {
      final url = await _api.enhanceEventAsset(widget.eventId, _assetSlug,
          brief: _briefCtrl.text.trim(), faceReference: _faceRef);
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _enhancing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enhancing = false;
        _error = 'No pudimos mejorar la imagen. Intente de nuevo.';
      });
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    final brief = _briefCtrl.text.trim();
    try {
      final url = switch (widget.kind) {
        EventDesignKind.poster =>
          await _api.generateEventPoster(widget.eventId, brief: brief),
        EventDesignKind.badge =>
          await _api.generateEventBadge(widget.eventId, brief: brief),
        EventDesignKind.certificate =>
          await _api.generateEventCertificate(widget.eventId, brief: brief),
      };
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _generating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error =
            'No pudimos generar el diseño. Verifique su conexión e intente de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      EventDesignKind.poster => 'Diseñar afiche',
      EventDesignKind.badge => 'Diseñar escarapela',
      EventDesignKind.certificate => 'Diseñar certificado',
    };
    final hasImage = _imageUrl != null && _imageUrl!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _busy
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            _uploading
                                ? 'Subiendo tu imagen…'
                                : _enhancing
                                    ? 'Mejorando la imagen con IA…'
                                    : 'Generando el diseño con IA…',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      )
                    : hasImage
                        ? _DesignPreview(url: _imageUrl!)
                        : _EmptyState(kind: widget.kind),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            // Brief: indicación para la IA. Pre-cargado con la descripción del
            // evento; el organizador puede ajustarlo para guiar la pieza.
            TextField(
              key: const Key('design_brief'),
              controller: _briefCtrl,
              enabled: !_busy,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Indicaciones para la IA',
                alignLabelWithHint: true,
                hintText: _briefHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            // Dos caminos lado a lado: generar con IA o subir imagen propia.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('design_generate'),
                    onPressed: _busy ? null : _generate,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(hasImage ? 'Generar otra' : 'Generar con IA'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('design_upload'),
                    onPressed: _busy ? null : _upload,
                    icon: const Icon(Icons.upload_rounded),
                    label: Text(hasImage ? 'Subir otra' : 'Subir mi imagen'),
                  ),
                ),
              ],
            ),
            if (hasImage) ...[
              const SizedBox(height: 10),
              // Foto de rostro opcional: ancla la identidad al "Mejorar con IA".
              InkWell(
                key: const Key('design_face_ref'),
                onTap: _busy ? null : _pickFaceRef,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFDDD6FE)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          _faceRef == null
                              ? Icons.face_retouching_natural_rounded
                              : Icons.check_circle_rounded,
                          size: 18,
                          color: const Color(0xFF7C3AED)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _faceRef == null
                              ? 'Foto de rostro (opcional, mejor parecido)'
                              : 'Rostro adjunto — la IA lo respetará',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      if (_faceRef != null)
                        GestureDetector(
                          onTap: () => setState(() => _faceRef = null),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Mejorar con IA la imagen actual (generada o subida), como el
              // "mejorar foto" del inventario.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('design_enhance'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                  ),
                  onPressed: _busy ? null : _enhance,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Mejorar con IA'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('design_use'),
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(_imageUrl),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Usar este diseño'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renderiza el diseño desde una URL de almacenamiento o un data URL base64.
class _DesignPreview extends StatelessWidget {
  final String url;
  const _DesignPreview({required this.url});

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (url.startsWith('data:image')) {
      final b64 = url.substring(url.indexOf(',') + 1);
      img = Image.memory(base64Decode(b64), fit: BoxFit.contain);
    } else {
      img = Image.network(url, fit: BoxFit.contain);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: img,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final EventDesignKind kind;
  const _EmptyState({required this.kind});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text) = switch (kind) {
      EventDesignKind.poster => (
          Icons.campaign_outlined,
          'Genere un afiche llamativo con IA para promocionar el evento en su '
              'catálogo.\nLuego puede regenerarlo hasta que le guste.'
        ),
      EventDesignKind.badge => (
          Icons.badge_outlined,
          'Genere una escarapela profesional con IA.\nLuego puede regenerarla '
              'hasta que le guste.'
        ),
      EventDesignKind.certificate => (
          Icons.workspace_premium_outlined,
          'Genere un certificado elegante con IA.\nLuego puede regenerarlo '
              'hasta que le guste.'
        ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 72, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ],
    );
  }
}
