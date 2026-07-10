// Spec: specs/097-completar-fotos-inventario/spec.md
//
// "Completar fotos": recorre las referencias SIN imagen y ayuda a ponerles
// una. Para las que tienen código de barras, sugiere la foto del catálogo
// (Spec 096) — verificada o de respaldo (marcada) — y el tendero acepta,
// rechaza o acepta todas. Además, por tarjeta: generar con IA, cargar del
// dispositivo, tomar foto o recortar el fondo. Reusa los endpoints existentes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/catalog_suggestion.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/compact_action_button.dart';
import '../legal/photo_rights_notice.dart';

class PhotoCompletionScreen extends StatefulWidget {
  const PhotoCompletionScreen({
    super.key,
    required this.products,
    @visibleForTesting this.apiOverride,
  });

  /// Productos SIN imagen (mapas crudos del backend: id, name, barcode, …).
  final List<Map<String, dynamic>> products;

  @visibleForTesting
  final ApiService? apiOverride;

  @override
  State<PhotoCompletionScreen> createState() => _PhotoCompletionScreenState();
}

/// Estado mutable por producto dentro del flujo.
class _Row {
  _Row(this.product);
  final Map<String, dynamic> product;

  CatalogSuggestion? suggestion; // del catálogo (por barcode)
  bool suggestionDiscarded = false;
  String? assignedUrl; // foto ya puesta en esta sesión (o null)
  bool busy = false;

  String get id => (product['id'] ?? product['uuid'] ?? '').toString();
  String get name => (product['name'] ?? '').toString();
  String get barcode => (product['barcode'] ?? '').toString().trim();
  String? get presentation => product['presentation'] as String?;
  String? get content => product['content'] as String?;

  String? get currentUrl {
    if (assignedUrl != null && assignedUrl!.isNotEmpty) return assignedUrl;
    final photo = (product['photo_url'] as String? ?? '').trim();
    final image = (product['image_url'] as String? ?? '').trim();
    final v = photo.isNotEmpty ? photo : image;
    return v.isEmpty ? null : v;
  }

  bool get done => currentUrl != null;
  bool get showSuggestion =>
      !done && !suggestionDiscarded && suggestion != null;
}

class _PhotoCompletionScreenState extends State<PhotoCompletionScreen> {
  late final ApiService _api;
  final _picker = ImagePicker();
  late final List<_Row> _rows;
  bool _loadingSuggestions = true;
  bool _applyingAll = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _rows = widget.products.map(_Row.new).toList();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final barcodes =
        _rows.map((r) => r.barcode).where((b) => b.isNotEmpty).toList();
    final map = await _api.fetchCatalogReferencePhotos(barcodes);
    if (!mounted) return;
    setState(() {
      for (final r in _rows) {
        if (r.barcode.isNotEmpty) r.suggestion = map[r.barcode];
      }
      _loadingSuggestions = false;
    });
  }

  int get _doneCount => _rows.where((r) => r.done).length;
  int get _pendingSuggestions =>
      _rows.where((r) => r.showSuggestion).length;

  // ── Acciones ───────────────────────────────────────────────────────────────

  Future<void> _run(_Row row, Future<String?> Function() action) async {
    if (row.busy) return;
    setState(() => row.busy = true);
    try {
      final url = await action();
      if (!mounted) return;
      setState(() {
        if (url != null && url.isNotEmpty) row.assignedUrl = url;
        row.busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => row.busy = false);
      _toast('No se pudo: ${_short(e)}', error: true);
    }
  }

  Future<void> _useSuggestion(_Row row) async {
    final s = row.suggestion;
    if (s == null) return;
    HapticFeedback.selectionClick();
    await _run(row, () async {
      await _api.updateProduct(row.id, {'image_url': s.imageUrl});
      return s.imageUrl;
    });
  }

  void _discard(_Row row) {
    HapticFeedback.selectionClick();
    setState(() => row.suggestionDiscarded = true);
  }

  Future<void> _useAllSuggestions() async {
    if (_applyingAll) return;
    setState(() => _applyingAll = true);
    var ok = 0;
    var failed = 0;
    // Secuencial para no golpear el backend; cada fallo NO frena el resto.
    for (final row in _rows.where((r) => r.showSuggestion).toList()) {
      final s = row.suggestion;
      if (s == null) continue;
      setState(() => row.busy = true);
      try {
        await _api.updateProduct(row.id, {'image_url': s.imageUrl});
        if (!mounted) return;
        ok++;
        setState(() => row.assignedUrl = s.imageUrl);
      } catch (_) {
        // La sugerencia queda disponible para reintento manual; el fallo
        // se cuenta y se INFORMA al final (auditoría 2026-07-10: antes se
        // tragaba en silencio y el tendero no sabía que quedaron fotos sin
        // guardar).
        failed++;
      } finally {
        if (mounted) setState(() => row.busy = false);
      }
    }
    if (!mounted) return;
    setState(() => _applyingAll = false);
    // Resumen honesto del lote (fallos parciales incluidos).
    if (failed > 0) {
      _toast(
        ok > 0
            ? '$ok foto${ok == 1 ? '' : 's'} aplicada${ok == 1 ? '' : 's'}; '
                '$failed no se ${failed == 1 ? 'pudo' : 'pudieron'} guardar. '
                'Puede reintentar con "Usar".'
            : 'No se pudo guardar. Revise su conexión e intente de nuevo.',
        error: true,
      );
    }
  }

  Future<void> _generateAi(_Row row) async {
    HapticFeedback.mediumImpact();
    await _run(row, () async {
      final res = await _api.generateProductImage(
        row.id,
        name: row.name,
        presentation: row.presentation,
        content: row.content,
        barcode: row.barcode.isEmpty ? null : row.barcode,
      );
      return (res['photo_url'] ?? res['image_url']) as String?;
    });
  }

  Future<void> _pickPhoto(_Row row, ImageSource source) async {
    // Adenda A (Spec 098): aviso único de derechos antes de subir foto MANUAL.
    await maybeShowPhotoRightsNotice(context);
    if (!mounted) return;
    final XFile? photo = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (photo == null) return;
    await _run(row, () async {
      final res = await _api.uploadProductPhoto(row.id, photo);
      return (res['photo_url'] ?? res['image_url']) as String?;
    });
  }

  Future<void> _removeBackground(_Row row) async {
    HapticFeedback.mediumImpact();
    await _run(row, () async {
      final res = await _api.enhanceProductPhoto(
        row.id,
        name: row.name,
        presentation: row.presentation,
        content: row.content,
      ); // mode null = quitar fondo (Spec 094, fiel)
      return (res['photo_url'] ?? res['image_url']) as String?;
    });
  }

  // ── Helpers UI ──────────────────────────────────────────────────────────────

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: error ? AppTheme.error : AppTheme.primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.length;
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Completar fotos'),
      ),
      body: Column(
        children: [
          _header(total),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: _rows.length,
              itemBuilder: (_, i) => _card(_rows[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_doneCount de $total con foto', style: AppUI.bodyStrong),
          const SizedBox(height: 8),
          if (_pendingSuggestions > 0)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _applyingAll ? null : _useAllSuggestions,
                icon: _applyingAll
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.done_all_rounded, size: 20),
                label: Text(_applyingAll
                    ? 'Aplicando…'
                    : 'Usar todas las sugeridas ($_pendingSuggestions)'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 48)),
              ),
            )
          else if (_loadingSuggestions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                // Flexible: a 360dp el texto no puede desbordar la fila.
                Flexible(
                  child: Text('Buscando fotos sugeridas…',
                      style: AppUI.bodySoft,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _card(_Row row) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: row.done
                ? AppTheme.primary.withValues(alpha: 0.4)
                : AppUI.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(row),
              const SizedBox(width: AppUI.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppUI.bodyStrong),
                    const SizedBox(height: 2),
                    if (row.done)
                      const Row(children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: AppTheme.primary),
                        SizedBox(width: 4),
                        Text('Lista',
                            style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600)),
                      ])
                    else if (row.barcode.isEmpty)
                      const Text('Sin código — use IA, cargue o tome foto',
                          style: AppUI.bodySoft),
                  ],
                ),
              ),
              if (row.busy)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          if (row.showSuggestion) ...[
            const SizedBox(height: AppUI.s12),
            _suggestionBlock(row),
          ],
          // Acciones manuales: siempre disponibles (salvo mientras trabaja).
          // Si ya tiene foto, permiten reemplazarla y aparece "Recortar fondo".
          if (!row.busy) ...[
            const SizedBox(height: AppUI.s12),
            _actions(row),
          ],
        ],
      ),
    );
  }

  Widget _thumb(_Row row) {
    final url = row.currentUrl;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppUI.pageBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppUI.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(Icons.inventory_2_outlined,
              color: AppUI.inkSoft, size: 24)
          : Image.network(url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.inventory_2_outlined,
                  color: AppUI.inkSoft,
                  size: 24)),
    );
  }

  Widget _suggestionBlock(_Row row) {
    final s = row.suggestion!;
    return Container(
      padding: const EdgeInsets.all(AppUI.s8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(s.imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.image_not_supported_outlined,
                        color: AppUI.inkSoft))),
          ),
          const SizedBox(width: AppUI.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Foto sugerida', style: AppUI.bodyStrong),
                const SizedBox(height: 2),
                _confidenceChip(s.verified),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _discard(row),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => _useSuggestion(row),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: const Text('Usar'),
          ),
        ],
      ),
    );
  }

  Widget _confidenceChip(bool verified) {
    final color = verified ? AppTheme.primary : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(verified ? Icons.verified_rounded : Icons.help_outline_rounded,
            size: 13, color: color),
        const SizedBox(width: 4),
        Text(verified ? 'Verificada' : 'Sin confirmar',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _actions(_Row row) {
    // Las 4 opciones que pidió el fundador, SIEMPRE visibles en cada tarjeta.
    // Botón compacto compartido (estilo explícito completo): el theme legacy
    // de OutlinedButton (64dp / 22px) no participa — nada gigante ni apilado.
    return Wrap(
      spacing: AppUI.s8,
      runSpacing: AppUI.s8,
      children: [
        CompactActionButton(
            icon: Icons.auto_awesome,
            label: 'Crear IA',
            onPressed: () => _generateAi(row)),
        CompactActionButton(
            icon: Icons.upload_rounded,
            label: 'Cargar',
            onPressed: () => _pickPhoto(row, ImageSource.gallery)),
        CompactActionButton(
            icon: Icons.photo_camera_rounded,
            label: 'Foto',
            onPressed: () => _pickPhoto(row, ImageSource.camera)),
        CompactActionButton(
            icon: Icons.content_cut_rounded,
            label: 'Recortar fondo',
            onPressed: () {
              if (!row.done) {
                _toast(
                    'Primero tome o cargue una foto para recortarle el fondo.');
                return;
              }
              _removeBackground(row);
            }),
      ],
    );
  }
}
