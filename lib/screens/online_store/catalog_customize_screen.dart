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
  String? _error;

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

  Future<void> _pickCover() async {
    final XFile? img = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (img == null || !mounted) return;
    setState(() => _coverBusy = true);
    try {
      final res = await _api.previewLogoUpload(img); // sube a R2 → URL
      final url = (res['logo_url'] as String?) ?? (res['url'] as String?) ?? '';
      if (url.isEmpty) throw 'sin url';
      if (!mounted) return;
      setState(() => _coverUrl = url);
    } catch (_) {
      _snack('No se pudo subir la portada (máx 2MB). Intente otra imagen.');
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
                      _input(_hoursCtrl, 'Ej: Lun a Sáb 8am–8pm · Dom 9am–2pm',
                          maxLength: 160),
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
        height: 56,
        alignment: Alignment.center,
        decoration: AppUI.card(),
        child: const SizedBox(
            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_coverUrl.isNotEmpty) {
      return Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          child: Image.network(_coverUrl, width: 64, height: 48, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_rounded, color: AppUI.inkSoft)),
        ),
        const SizedBox(width: AppUI.s12),
        TextButton.icon(
          onPressed: _pickCover,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('Cambiar'),
        ),
        TextButton(
          onPressed: () => setState(() => _coverUrl = ''),
          style: TextButton.styleFrom(foregroundColor: AppTheme.error),
          child: const Text('Quitar'),
        ),
      ]);
    }
    return OutlinedButton.icon(
      key: const Key('pick_cover'),
      onPressed: _pickCover,
      icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
      label: const Text('Subir portada'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: AppTheme.primary,
      ),
    );
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
