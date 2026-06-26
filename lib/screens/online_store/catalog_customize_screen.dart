// Spec: specs/082-catalogo-online-personalizacion/spec.md
//
// Personalizar mi catálogo: identidad (nombre, eslogan, portada), apariencia
// (color de marca), contacto y horario, y el enlace (URL). UI normalizada al
// kit AppUI (SoftCard + sectionLabel). Se ve en la tienda en línea pública.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';

class CatalogCustomizeScreen extends StatefulWidget {
  final ApiService? api;
  const CatalogCustomizeScreen({super.key, this.api});

  @override
  State<CatalogCustomizeScreen> createState() => _CatalogCustomizeScreenState();
}

class _CatalogCustomizeScreenState extends State<CatalogCustomizeScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  String _brandColor = '';
  String _coverUrl = '';
  String _initialSlug = '';
  bool _loading = true;
  bool _saving = false;
  bool _coverBusy = false;
  String _coverBusyMsg = '';
  String? _error;

  // Horario estructurado: días (1=Lun..7=Dom) + apertura/cierre.
  final Set<int> _days = {};
  TimeOfDay? _open;
  TimeOfDay? _close;
  static const _dayLabels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  static const _swatches = <String>[
    '#1A2FA0', '#0D9668', '#D97706', '#DC2626',
    '#7C3AED', '#0EA5E9', '#DB2777', '#111827',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taglineCtrl.dispose();
    _hoursCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.fetchBusinessProfile();
      final d = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = (d['business_name'] as String?) ?? '';
        _taglineCtrl.text = (d['store_tagline'] as String?) ?? '';
        _hoursCtrl.text = (d['store_hours'] as String?) ?? '';
        _initialSlug = (d['store_slug'] as String?) ?? '';
        _slugCtrl.text = _initialSlug;
        _brandColor = (d['brand_color'] as String?) ?? '';
        _coverUrl = (d['store_cover_url'] as String?) ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar la personalización.';
        _loading = false;
      });
    }
  }

  // Sube una foto tal cual (a R2) y la usa como portada.
  Future<void> _uploadCover() async {
    final XFile? img = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (img == null || !mounted) return;
    await _runCover('Subiendo portada…', () async {
      final res = await _api.previewLogoUpload(img);
      return (res['logo_url'] as String?) ?? (res['url'] as String?) ?? '';
    });
  }

  // Genera una portada con IA desde cero (nombre + tipo de negocio).
  Future<void> _generateCover() async {
    await _runCover('Generando portada con IA…',
        () => _api.generateStoreCover());
  }

  // Pide una foto y la MEJORA con IA para usarla como portada.
  Future<void> _enhanceCover() async {
    final XFile? img = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 90);
    if (img == null || !mounted) return;
    await _runCover('Mejorando su foto con IA…',
        () => _api.generateStoreCover(image: img));
  }

  Future<void> _runCover(String msg, Future<String> Function() action) async {
    setState(() {
      _coverBusy = true;
      _coverBusyMsg = msg;
    });
    try {
      final url = await action();
      if (url.isEmpty) throw 'sin url';
      if (!mounted) return;
      setState(() => _coverUrl = url);
    } catch (_) {
      _snack('No se pudo procesar la portada. Intente con otra imagen (máx 5MB).');
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('El nombre de la tienda es obligatorio.');
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await _api.updateBusinessProfile({
        'business_name': _nameCtrl.text.trim(),
        'store_tagline': _taglineCtrl.text.trim(),
        'store_hours': _hoursCtrl.text.trim(),
        'brand_color': _brandColor,
        'store_cover_url': _coverUrl,
      });

      final newSlug = _normalizeSlug(_slugCtrl.text);
      if (newSlug.isNotEmpty && newSlug != _initialSlug) {
        try {
          await _api.updateStoreSlug(newSlug);
          _initialSlug = newSlug;
        } catch (e) {
          if (!mounted) return;
          setState(() => _saving = false);
          _snack('Se guardó todo, pero el enlace "$newSlug" no está disponible. '
              'Pruebe otro.');
          return;
        }
      }

      if (!mounted) return;
      _snack('Catálogo personalizado ✓', ok: true);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No se pudo guardar: $e');
    }
  }

  String _normalizeSlug(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');

  void _snack(String m, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: ok ? AppTheme.success : AppTheme.error));
  }

  Color get _previewColor {
    final hex = _brandColor.replaceFirst('#', '');
    if (hex.length == 6) {
      final v = int.tryParse('FF$hex', radix: 16);
      if (v != null) return Color(v);
    }
    return AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Personalizar mi catálogo', style: AppUI.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(AppUI.s24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center, style: AppUI.bodySoft),
                    const SizedBox(height: AppUI.s8),
                    TextButton(onPressed: _load, child: const Text('Reintentar')),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.all(AppUI.s16),
                  children: [
                    _previewCard(),
                    const SizedBox(height: AppUI.s16),

                    _section('Identidad', [
                      _label('Nombre de la tienda'),
                      _input(_nameCtrl, 'Ej: Don Brayan'),
                      const SizedBox(height: AppUI.s12),
                      _label('Eslogan / descripción corta'),
                      _input(_taglineCtrl, 'Ej: Frutas y verduras frescas a domicilio',
                          maxLines: 2, maxLength: 140, onChanged: (_) => setState(() {})),
                      const SizedBox(height: AppUI.s12),
                      _label('Portada (imagen de cabecera)'),
                      const SizedBox(height: 6),
                      _coverPicker(),
                    ]),
                    const SizedBox(height: AppUI.s16),

                    _section('Apariencia', [
                      _label('Color de marca'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [for (final hex in _swatches) _swatch(hex)],
                      ),
                    ]),
                    const SizedBox(height: AppUI.s16),

                    _section('Contacto y enlace', [
                      _label('Horario de atención'),
                      const SizedBox(height: 8),
                      _hoursEditor(),
                      const SizedBox(height: AppUI.s12),
                      _label('Enlace de su tienda (URL)'),
                      _input(_slugCtrl, 'mi-tienda', prefixText: 'tienda.vendia.store/'),
                      const SizedBox(height: 4),
                      Text('Solo minúsculas, números y guiones. Debe estar disponible.',
                          style: AppUI.bodySoft.copyWith(fontSize: 12)),
                    ]),
                    const SizedBox(height: AppUI.s24),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Guardar',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
    );
  }

  // ── Helpers de UI (AppUI) ──────────────────────────────────────────────

  Widget _section(String title, List<Widget> children) {
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: AppUI.sectionLabel),
        const SizedBox(height: AppUI.s12),
        ...children,
      ]),
    );
  }

  Widget _label(String t) => Text(t, style: AppUI.bodyStrong.copyWith(fontSize: 14));

  Widget _input(TextEditingController c, String hint,
      {int maxLines = 1, int? maxLength, String? prefixText, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefixText,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _previewCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _previewColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_coverUrl.isNotEmpty)
          SizedBox(
            height: 90,
            width: double.infinity,
            child: Image.network(_coverUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        Padding(
          padding: const EdgeInsets.all(AppUI.s16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Así se ve su tienda en línea',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Text(_nameCtrl.text.trim().isEmpty ? 'Su tienda' : _nameCtrl.text.trim(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            if (_taglineCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_taglineCtrl.text.trim(),
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _coverPicker() {
    if (_coverBusy) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: AppUI.card(),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: AppUI.s8),
          Text(_coverBusyMsg, style: AppUI.bodySoft),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // PREVIEW grande de la portada (o placeholder si no hay).
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          child: _coverUrl.isNotEmpty
              ? Image.network(_coverUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverPlaceholder())
              : _coverPlaceholder(),
        ),
      ),
      const SizedBox(height: AppUI.s8),
      // Acciones: subir / generar IA / mejorar IA.
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('cover_upload'),
          onPressed: _uploadCover,
          icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
          label: const Text('Subir foto'),
        ),
        OutlinedButton.icon(
          key: const Key('cover_generate'),
          onPressed: _generateCover,
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('Generar con IA'),
        ),
        OutlinedButton.icon(
          key: const Key('cover_enhance'),
          onPressed: _enhanceCover,
          icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
          label: const Text('Mejorar foto con IA'),
        ),
        if (_coverUrl.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _coverUrl = ''),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Quitar'),
          ),
      ]),
    ]);
  }

  Widget _coverPlaceholder() => Container(
        color: AppUI.pageBg,
        alignment: Alignment.center,
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.image_outlined, color: AppUI.inkSoft, size: 32),
          SizedBox(height: 4),
          Text('Sin portada', style: AppUI.bodySoft),
        ]),
      );

  // ── Horario (selector elegante: días + apertura/cierre) ─────────────────

  Widget _hoursEditor() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < 7; i++)
          FilterChip(
            label: Text(_dayLabels[i]),
            selected: _days.contains(i + 1),
            showCheckmark: false,
            selectedColor: AppTheme.primary.withValues(alpha: 0.15),
            onSelected: (s) => setState(() {
              if (s) {
                _days.add(i + 1);
              } else {
                _days.remove(i + 1);
              }
              _composeHours();
            }),
          ),
      ]),
      const SizedBox(height: AppUI.s12),
      Row(children: [
        Expanded(child: _timeBtn('Abre', _open, (t) => setState(() {
              _open = t;
              _composeHours();
            }))),
        const SizedBox(width: AppUI.s12),
        Expanded(child: _timeBtn('Cierra', _close, (t) => setState(() {
              _close = t;
              _composeHours();
            }))),
      ]),
      if (_hoursCtrl.text.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 16, color: AppUI.inkSoft),
          const SizedBox(width: 6),
          Expanded(child: Text(_hoursCtrl.text, style: AppUI.bodyStrong.copyWith(fontSize: 14))),
        ]),
      ],
    ]);
  }

  Widget _timeBtn(String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPick) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? const TimeOfDay(hour: 8, minute: 0),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
      ),
      child: Text(value == null ? '$label: --' : '$label: ${_fmtTime(value)}',
          style: const TextStyle(fontSize: 15)),
    );
  }

  // Compone el texto legible ("Lun a Vie 8:00 a.m.–6:00 p.m.") y lo deja en
  // _hoursCtrl, que es lo que se guarda en store_hours.
  void _composeHours() {
    if (_days.isEmpty || _open == null || _close == null) return;
    final sorted = _days.toList()..sort();
    final daysStr = _daysLabel(sorted);
    _hoursCtrl.text = '$daysStr ${_fmtTime(_open!)}–${_fmtTime(_close!)}';
  }

  String _daysLabel(List<int> days) {
    // Rango contiguo → "Lun a Vie"; si no, lista separada por comas.
    final contiguous = days.length > 2 &&
        days.last - days.first == days.length - 1;
    if (contiguous) {
      return '${_dayLabels[days.first - 1]} a ${_dayLabels[days.last - 1]}';
    }
    return days.map((d) => _dayLabels[d - 1]).join(', ');
  }

  String _fmtTime(TimeOfDay t) {
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'a.m.' : 'p.m.';
    return '$h12:$mm $suffix';
  }

  Widget _swatch(String hex) {
    final selected = _brandColor.toUpperCase() == hex.toUpperCase();
    final v = int.tryParse('FF${hex.replaceFirst('#', '')}', radix: 16);
    final color = v != null ? Color(v) : AppTheme.primary;
    return GestureDetector(
      onTap: () => setState(() => _brandColor = hex),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? AppTheme.textPrimary : Colors.transparent, width: 3),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}
