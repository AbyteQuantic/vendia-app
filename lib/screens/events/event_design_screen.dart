// Spec: specs/042-modulo-eventos/spec.md
//
// Editor visual de escarapela / certificado con IA (F042, T-42/T-43).
// El organizador genera una propuesta con Gemini, la previsualiza y puede
// regenerar hasta quedar conforme (loop generar/regenerar/usar). El backend
// persiste el diseño en la plantilla del evento en cada generación; "Usar
// este diseño" simplemente cierra con el último generado.

import 'dart:convert';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';

/// Qué se está diseñando.
enum EventDesignKind { poster, badge, certificate }

class EventDesignScreen extends StatefulWidget {
  final String eventId;
  final EventDesignKind kind;

  /// URL del diseño actual (si ya existe), para mostrarlo al abrir.
  final String? currentImageUrl;
  final ApiService? apiOverride;

  const EventDesignScreen({
    super.key,
    required this.eventId,
    required this.kind,
    this.currentImageUrl,
    this.apiOverride,
  });

  @override
  State<EventDesignScreen> createState() => _EventDesignScreenState();
}

class _EventDesignScreenState extends State<EventDesignScreen> {
  late final ApiService _api;
  String? _imageUrl;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _imageUrl = widget.currentImageUrl;
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final url = switch (widget.kind) {
        EventDesignKind.poster => await _api.generateEventPoster(widget.eventId),
        EventDesignKind.badge => await _api.generateEventBadge(widget.eventId),
        EventDesignKind.certificate =>
          await _api.generateEventCertificate(widget.eventId),
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
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _generating
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Generando el diseño con IA…',
                              style: TextStyle(fontSize: 16)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('design_generate'),
                    onPressed: _generating ? null : _generate,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(hasImage ? 'Generar otra' : 'Generar con IA'),
                  ),
                ),
                if (hasImage) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('design_use'),
                      onPressed: _generating
                          ? null
                          : () => Navigator.of(context).pop(_imageUrl),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Usar este diseño'),
                    ),
                  ),
                ],
              ],
            ),
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
