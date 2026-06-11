// Spec: specs/042-modulo-eventos/spec.md
//
// Diseñador WYSIWYG del certificado (F042). El organizador:
//  - genera el FONDO con IA (moderno, marca de agua alusiva) o sube el suyo,
//  - sube/limpia con IA su FIRMA (sin fondo) y su LOGO,
//  - arrastra y redimensiona cada elemento (título, nombre del asistente,
//    nombre del firmante, firma, logo, QR…) sobre un preview en vivo.
// El layout (posiciones normalizadas + tamaño) se guarda en certificate_config
// y el carné del asistente lo renderiza idéntico.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'event_feedback.dart';

const _accent = Color(0xFF0EA5E9);
const _certAspect = 1.414; // horizontal (apaisado)

// Elementos del diploma, en orden de pintado.
const _elementKeys = [
  'title',
  'intro',
  'name',
  'body',
  'date',
  'signatory',
  'signature',
  'logo',
  'qr',
];

const Map<String, CertElementPos> _defaultLayout = {
  'title': CertElementPos(x: 0.5, y: 0.15, scale: 0.045),
  'intro': CertElementPos(x: 0.5, y: 0.29, scale: 0.018),
  'name': CertElementPos(x: 0.5, y: 0.42, scale: 0.08),
  'body': CertElementPos(x: 0.5, y: 0.56, scale: 0.022),
  'date': CertElementPos(x: 0.5, y: 0.68, scale: 0.017),
  'signatory': CertElementPos(x: 0.32, y: 0.86, scale: 0.02),
  'signature': CertElementPos(x: 0.32, y: 0.78, scale: 0.18),
  'logo': CertElementPos(x: 0.82, y: 0.80, scale: 0.16),
  'qr': CertElementPos(x: 0.9, y: 0.85, scale: 0.1),
};

String _elementLabel(String k) => switch (k) {
      'title' => 'Título',
      'intro' => 'Frase',
      'name' => 'Nombre del asistente',
      'body' => 'Cuerpo',
      'date' => 'Fecha',
      'signatory' => 'Nombre de quien firma',
      'signature' => 'Firma',
      'logo' => 'Logo',
      'qr' => 'QR',
      _ => k,
    };

class EventCertificateDesignerScreen extends StatefulWidget {
  final Event event;
  final ApiService? apiOverride;

  const EventCertificateDesignerScreen({
    super.key,
    required this.event,
    this.apiOverride,
  });

  @override
  State<EventCertificateDesignerScreen> createState() =>
      _EventCertificateDesignerScreenState();
}

class _EventCertificateDesignerScreenState
    extends State<EventCertificateDesignerScreen> {
  late final ApiService _api;
  final AuthService _auth = AuthService();
  late String _bgUrl;

  final _titleCtrl = TextEditingController();
  final _introCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _signatoryCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();

  String _signatureUrl = '';
  String _logoUrl = '';
  String _businessLogoUrl = ''; // logo del negocio (default y botón "usar")
  bool _logoCleared = false; // el organizador quitó el logo a propósito
  XFile? _sigFile;

  late Map<String, CertElementPos> _layout;
  String? _selected;

  bool _bgBusy = false;
  bool _sigBusy = false;
  bool _logoBusy = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _bgUrl = widget.event.certificateUrl;
    final cc = widget.event.certificateConfig;
    _titleCtrl.text = cc.title;
    _introCtrl.text = cc.intro;
    _bodyCtrl.text = cc.body;
    _signatoryCtrl.text = cc.signatory;
    _footerCtrl.text = cc.footer;
    _signatureUrl = cc.signatureImage;
    _logoUrl = cc.logoImage;
    _logoCleared = cc.logoCleared;
    _layout = {
      for (final k in _elementKeys)
        k: cc.layout[k] ?? _defaultLayout[k] ?? const CertElementPos(),
    };
    _loadBusinessLogo();
  }

  // Trae el logo del negocio: lo deja disponible para el botón "Logo del
  // negocio" y lo muestra por defecto si aún no hay logo y el organizador no
  // lo quitó a propósito.
  Future<void> _loadBusinessLogo() async {
    try {
      final logo = (await _auth.getLogoUrl())?.trim() ?? '';
      if (!mounted || logo.isEmpty) return;
      setState(() {
        _businessLogoUrl = logo;
        if (_logoUrl.isEmpty && !_logoCleared) _logoUrl = logo;
      });
    } catch (_) {
      // Sin logo en caché: el organizador puede subir uno.
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _introCtrl.dispose();
    _bodyCtrl.dispose();
    _signatoryCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  // ── Acciones de fondo / firma / logo ──────────────────────────────────
  Future<void> _generateBg() async {
    HapticFeedback.lightImpact();
    setState(() => _bgBusy = true);
    try {
      final url = await _api.generateEventCertificate(widget.event.id);
      if (mounted) setState(() => _bgUrl = url);
    } catch (_) {
      _snack('No pudimos generar el fondo. Intenta de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _bgBusy = false);
    }
  }

  Future<void> _uploadBg() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (picked == null) return;
    setState(() => _bgBusy = true);
    try {
      final url = await _api.uploadEventAsset(widget.event.id, 'certificate', picked);
      if (mounted) setState(() => _bgUrl = url);
    } catch (_) {
      _snack('No pudimos subir el fondo.', error: true);
    } finally {
      if (mounted) setState(() => _bgBusy = false);
    }
  }

  Future<void> _pickSignature(ImageSource source) async {
    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 92);
    if (picked == null) return;
    setState(() {
      _sigFile = picked;
      _sigBusy = true;
    });
    try {
      final url = await _api.uploadEventImage(picked);
      if (mounted) setState(() => _signatureUrl = url);
    } catch (_) {
      _snack('No pudimos subir la firma.', error: true);
    } finally {
      if (mounted) setState(() => _sigBusy = false);
    }
  }

  Future<void> _cleanSignature() async {
    if (_sigFile == null) {
      _snack('Primero sube o toma la foto de la firma.');
      return;
    }
    setState(() => _sigBusy = true);
    try {
      final url = await _api.cleanEventSignature(_sigFile!);
      if (mounted) setState(() => _signatureUrl = url);
      _snack('Firma limpiada con IA.', ok: true);
    } catch (_) {
      _snack('No pudimos limpiar la firma. Intenta con otra.', error: true);
    } finally {
      if (mounted) setState(() => _sigBusy = false);
    }
  }

  Future<void> _uploadLogo() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (picked == null) return;
    setState(() => _logoBusy = true);
    try {
      final url = await _api.uploadEventImage(picked);
      if (mounted) {
        setState(() {
          _logoUrl = url;
          _logoCleared = false;
        });
      }
    } catch (_) {
      _snack('No pudimos subir el logo.', error: true);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  // Usa el logotipo del negocio (ya cargado en el perfil) como logo del
  // certificado. Reactiva el default si el organizador lo había quitado.
  void _useBusinessLogo() {
    if (_businessLogoUrl.isEmpty) return;
    setState(() {
      _logoUrl = _businessLogoUrl;
      _logoCleared = false;
    });
  }

  // Quita el logo del diseño y lo recuerda, para no reinyectar el del negocio.
  void _removeLogo() {
    setState(() {
      _logoUrl = '';
      _logoCleared = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final config = EventCertificateConfig(
        title: _titleCtrl.text.trim(),
        intro: _introCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        signatory: _signatoryCtrl.text.trim(),
        footer: _footerCtrl.text.trim(),
        signatureImage: _signatureUrl,
        logoImage: _logoUrl,
        logoCleared: _logoCleared,
        layout: _layout,
      );
      final result =
          await _api.updateEventCertificateConfig(widget.event.id, config.toJson());
      if (!mounted) return;
      Navigator.of(context).pop(Event.fromJson(result));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No pudimos guardar el diseño.', error: true);
    }
  }

  void _snack(String msg, {bool error = false, bool ok = false}) {
    if (!mounted) return;
    showEventSnack(context, msg,
        kind: error
            ? EventSnackKind.error
            : ok
                ? EventSnackKind.success
                : EventSnackKind.info);
  }

  // ── Render de cada elemento ───────────────────────────────────────────
  String _textFor(String key) => switch (key) {
        'title' => _orEmpty(_titleCtrl.text, 'Certificado de Participación'),
        'intro' => _orEmpty(_introCtrl.text, 'Se otorga el presente certificado a'),
        'name' => 'Nombre del Asistente',
        'body' => _orEmpty(_bodyCtrl.text,
            'por haber participado satisfactoriamente en ${widget.event.title}'),
        'date' => 'Ciudad, 00 de mes de 0000',
        'signatory' =>
          'Otorgado por ${_orEmpty(_signatoryCtrl.text, "Nombre del firmante")}',
        _ => '',
      };

  String _orEmpty(String v, String fallback) =>
      v.trim().isEmpty ? fallback : v.trim();

  String _imageUrlFor(String key) =>
      key == 'signature' ? _signatureUrl : (key == 'logo' ? _logoUrl : '');

  Widget _imageWidget(String url, double width) {
    if (url.startsWith('data:')) {
      final b64 = url.substring(url.indexOf(',') + 1);
      return Image.memory(base64Decode(b64), width: width, fit: BoxFit.contain);
    }
    return Image.network(url, width: width, fit: BoxFit.contain);
  }

  Widget _renderElement(String key, double w) {
    final pos = _layout[key]!;
    if (key == 'signature' || key == 'logo') {
      final url = _imageUrlFor(key);
      if (url.isEmpty) return const SizedBox.shrink();
      return _imageWidget(url, pos.scale * w);
    }
    if (key == 'qr') {
      final s = pos.scale * w;
      return Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black54),
        ),
        child: const Icon(Icons.qr_code_2_rounded, color: Colors.black54),
      );
    }
    // Texto: blanco-negro con halo blanco para leerse en cualquier fondo.
    final fontSize = (pos.scale * w).clamp(7.0, 80.0);
    final isName = key == 'name';
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: w * 0.82),
      child: Text(
        _textFor(key),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'serif',
          fontStyle: isName || key == 'intro' || key == 'date'
              ? FontStyle.italic
              : FontStyle.normal,
          fontWeight: key == 'title' || isName
              ? FontWeight.w800
              : FontWeight.w500,
          fontSize: fontSize,
          height: 1.1,
          color: const Color(0xFF2e2415),
          letterSpacing: key == 'title' ? 1.2 : 0,
          shadows: const [
            Shadow(color: Colors.white, offset: Offset(-1, -1), blurRadius: 1),
            Shadow(color: Colors.white, offset: Offset(1, -1), blurRadius: 1),
            Shadow(color: Colors.white, offset: Offset(-1, 1), blurRadius: 1),
            Shadow(color: Colors.white, offset: Offset(1, 1), blurRadius: 2),
          ],
        ),
      ),
    );
  }

  Widget _positioned(String key, double bw, double bh) {
    final pos = _layout[key]!;
    if (pos.hidden) return const SizedBox.shrink();
    final child = _renderElement(key, bw);
    if (child is SizedBox) return const SizedBox.shrink(); // imagen sin subir
    final selected = _selected == key;
    return Positioned(
      left: pos.x * bw,
      top: pos.y * bh,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = key),
          onPanStart: (_) => setState(() => _selected = key),
          onPanUpdate: (d) => setState(() {
            final p = _layout[key]!;
            _layout[key] = p.copyWith(
              x: (p.x + d.delta.dx / bw).clamp(0.02, 0.98),
              y: (p.y + d.delta.dy / bh).clamp(0.02, 0.98),
            );
          }),
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    border: Border.all(color: _accent, width: 1.5),
                    color: _accent.withValues(alpha: 0.06),
                  )
                : null,
            padding: const EdgeInsets.all(2),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diseñar certificado'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Fondo ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _bgBusy ? null : _generateBg,
                  icon: _bgBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Fondo con IA'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _bgBusy ? null : _uploadBg,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Subir fondo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Preview WYSIWYG ────────────────────────────────────
          LayoutBuilder(builder: (context, c) {
            final bw = c.maxWidth;
            final bh = bw / _certAspect;
            return Container(
              width: bw,
              height: bh,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F1E7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (_bgUrl.isNotEmpty)
                    Positioned.fill(
                      child: _bgUrl.startsWith('data:')
                          ? Image.memory(
                              base64Decode(
                                  _bgUrl.substring(_bgUrl.indexOf(',') + 1)),
                              fit: BoxFit.cover)
                          : Image.network(_bgUrl, fit: BoxFit.cover),
                    )
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Genera o sube el fondo del certificado',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black45),
                        ),
                      ),
                    ),
                  for (final k in _elementKeys) _positioned(k, bw, bh),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          Text('Toca un elemento para seleccionarlo y arrástralo. Usa el '
              'control de abajo para el tamaño.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          // ── Control del elemento seleccionado ──────────────────
          if (_selected != null) _selectedControls(),
          const SizedBox(height: 12),
          // ── Firma ──────────────────────────────────────────────
          _assetSection(
            title: 'Firma',
            url: _signatureUrl,
            busy: _sigBusy,
            onRemove: () => setState(() {
              _signatureUrl = '';
              _sigFile = null;
            }),
            extra: _sigFile != null
                ? TextButton.icon(
                    onPressed: _sigBusy ? null : _cleanSignature,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Limpiar IA'),
                  )
                : null,
            buttons: [
              ('Tomar foto', Icons.photo_camera_rounded,
                  () => _pickSignature(ImageSource.camera)),
              ('Subir', Icons.upload_rounded,
                  () => _pickSignature(ImageSource.gallery)),
            ],
          ),
          const SizedBox(height: 12),
          // ── Logo ───────────────────────────────────────────────
          _assetSection(
            title: 'Logo del negocio',
            url: _logoUrl,
            busy: _logoBusy,
            onRemove: _removeLogo,
            buttons: [
              if (_businessLogoUrl.isNotEmpty)
                ('Logo del negocio', Icons.storefront_rounded, _useBusinessLogo),
              (
                _businessLogoUrl.isEmpty ? 'Subir logo' : 'Subir otro',
                Icons.upload_rounded,
                _uploadLogo
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Textos ─────────────────────────────────────────────
          const Text('Textos del certificado',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _field(_titleCtrl, 'Título', 'Certificado de Participación'),
          _field(_introCtrl, 'Frase', 'Se otorga el presente certificado a'),
          _field(_bodyCtrl, 'Cuerpo',
              'por haber participado satisfactoriamente en…',
              maxLines: 2),
          _field(_signatoryCtrl, 'Nombre de quien firma',
              'Por defecto: el nombre de tu negocio'),
          _field(_footerCtrl, 'Nota al pie (opcional)',
              'Ej: acredita 8 horas de formación', maxLines: 2),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _selectedControls() {
    final key = _selected!;
    final pos = _layout[key]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Tamaño · ${_elementLabel(key)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              IconButton(
                tooltip: pos.hidden ? 'Mostrar' : 'Ocultar',
                onPressed: () => setState(() =>
                    _layout[key] = pos.copyWith(hidden: !pos.hidden)),
                icon: Icon(
                    pos.hidden
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: _accent),
              ),
            ],
          ),
          Slider(
            value: pos.scale.clamp(0.01, 0.5),
            min: 0.01,
            max: 0.5,
            onChanged: (v) => setState(
                () => _layout[key] = pos.copyWith(scale: v)),
          ),
        ],
      ),
    );
  }

  Widget _assetSection({
    required String title,
    required String url,
    required bool busy,
    required VoidCallback onRemove,
    required List<(String, IconData, VoidCallback)> buttons,
    Widget? extra,
  }) {
    final has = url.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (has)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                    child: SizedBox(height: 48, child: _imageWidget(url, 120))),
                if (extra != null) extra,
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626)),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              for (final b in buttons) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : b.$3,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(b.$2, size: 18),
                    label: Text(b.$1),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
          {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          minLines: 1,
          maxLines: maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration:
              InputDecoration(labelText: label, hintText: hint, isDense: true),
        ),
      );
}
