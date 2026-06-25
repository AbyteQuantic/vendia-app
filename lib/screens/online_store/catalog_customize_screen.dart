// Spec: specs/082-catalogo-online-personalizacion/spec.md
//
// Personalizar mi catálogo (Fase 1): nombre, eslogan y color de marca. Se ven
// en la tienda en línea pública. El logo/portada y el orden de productos llegan
// en fases siguientes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String _initialSlug = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Paleta de marca: colores legibles como fondo de cabecera (texto blanco).
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
      });

      // El enlace (slug) tiene su propio endpoint con validación de unicidad.
      // Solo lo mandamos si cambió. Si está tomado, avisamos pero el resto
      // (nombre/eslogan/horario/color) ya quedó guardado.
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

  // Enlace amigable: minúsculas, sin espacios ni acentos raros.
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
                    const Text('Nombre de la tienda', style: AppUI.sectionLabel),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                          hintText: 'Ej: Don Brayan', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: AppUI.s16),
                    const Text('Eslogan / descripción corta', style: AppUI.sectionLabel),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _taglineCtrl,
                      maxLength: 140,
                      maxLines: 2,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                          hintText: 'Ej: Frutas y verduras frescas a domicilio',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: AppUI.s8),
                    const Text('Color de marca', style: AppUI.sectionLabel),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final hex in _swatches) _swatch(hex),
                      ],
                    ),
                    const SizedBox(height: AppUI.s16),
                    const Text('Horario de atención', style: AppUI.sectionLabel),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _hoursCtrl,
                      maxLength: 160,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                          hintText: 'Ej: Lun a Sáb 8am–8pm · Dom 9am–2pm',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: AppUI.s8),
                    const Text('Enlace de su tienda (URL)', style: AppUI.sectionLabel),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _slugCtrl,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                          prefixText: 'tienda.vendia.store/',
                          hintText: 'mi-tienda',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        'Solo minúsculas, números y guiones. Debe estar disponible.',
                        style: AppUI.bodySoft.copyWith(fontSize: 12)),
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

  // Vista previa de la cabecera del catálogo con el color/nombre/eslogan.
  Widget _previewCard() {
    return Container(
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: BoxDecoration(
        color: _previewColor,
        borderRadius: BorderRadius.circular(16),
      ),
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
