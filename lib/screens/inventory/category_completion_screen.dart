// Spec: specs/102-completar-categorias-inventario/spec.md
//
// Vista dedicada "Organizar categorías" (4º contador de curaduría, patrón de
// 097/100/101): recibe la lista YA prefiltrada de productos sin categoría,
// pide sugerencias al endpoint de Spec 078 (que NUNCA aplica — solo
// devuelve) y agrupa por categoría sugerida. El tendero confirma por
// tarjeta, por grupo o todas (confirmación única); también hay modo de
// selección múltiple para asignar UNA categoría a varios de un tirón.
//
// Contrato de escritura: PATCH updateProduct {'category': <string>} — el
// MISMO que la edición de producto (Spec 068): string libre normalizado con
// canonicalValue contra las categorías existentes; `category_id` no
// participa en este camino. Aplicar-masivo = pool de 4 requests
// concurrentes; la tarjeta sale SOLO con 2xx — fallo → permanece +
// Reintentar (el contador nunca miente). IA caída → modo manual con banner
// suave, sin bloqueo (AC-05/FR-07).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/text_normalize.dart';
import '../../widgets/category_picker_sheet.dart';
import '../../widgets/compact_action_button.dart';
import '../../widgets/product_image.dart';
import '../../widgets/sku_manual_code_sheet.dart' show sheetHandle;

/// Acento IA (mismo morado del chip de retoque, Spec 101): la sugerencia
/// se marca visualmente como "de la IA" hasta que el tendero la corrige.
const _kAiAccent = Color(0xFF7C3AED);

/// Estado mutable por producto dentro del flujo (patrón _Row de 097/100).
class _Row {
  _Row(this.product);
  final Map<String, dynamic> product;

  /// Sugerencia de la IA (chip ✨). Nunca se aplica sola (Art. I / Spec 078).
  String? suggested;

  /// Corrección del tendero — SIEMPRE gana a la sugerencia (AC-04).
  String? manual;

  bool busy = false;
  bool leaving = false; // guardado con 2xx (o 404): la tarjeta sale
  bool failed = false; // último intento falló: permanece + Reintentar
  bool selected = false; // modo selección múltiple

  /// Categoría que se aplicaría hoy: la del tendero o, si no, la sugerida.
  String? get effective {
    final v = (manual ?? suggested)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String get id => (product['id'] ?? product['uuid'] ?? '').toString();
  String get name => (product['name'] ?? '').toString();

  String? get photoUrl {
    final photo = (product['photo_url'] as String? ?? '').trim();
    final image = (product['image_url'] as String? ?? '').trim();
    final v = photo.isNotEmpty ? photo : image;
    return v.isEmpty ? null : v;
  }
}

/// Sección visible: una categoría (aplicable) o "Por clasificar" (manual).
class _Group {
  const _Group(this.name, this.rows, {required this.applicable});
  final String name;
  final List<_Row> rows;
  final bool applicable;

  int get activeCount => rows.where((r) => !r.leaving).length;
}

class CategoryCompletionScreen extends StatefulWidget {
  const CategoryCompletionScreen({
    super.key,
    required this.products,
    this.apiOverride,
  });

  /// Productos SIN categoría (mapas crudos del backend), ya prefiltrados por
  /// Mi Inventario con [isMissingCategory] (sin borradores — FR-01).
  final List<Map<String, dynamic>> products;

  /// Inyección para pruebas de widget (mismo patrón que OrganizeCategories).
  final ApiService? apiOverride;

  @override
  State<CategoryCompletionScreen> createState() =>
      _CategoryCompletionScreenState();
}

class _CategoryCompletionScreenState extends State<CategoryCompletionScreen> {
  late final ApiService _api;
  late final List<_Row> _rows;
  late final int _total;

  bool _loading = true;
  bool _aiDown = false;
  bool _applying = false;
  bool _selectionMode = false;

  /// Categorías conocidas (las del tenant + las que nacen en la sesión):
  /// alimentan el selector y la normalización de grafía (Spec 068).
  List<String> _knownCategories = [];

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _rows = widget.products.map(_Row.new).toList();
    _total = _rows.length;
    _load();
  }

  // ── Carga de sugerencias (FR-03 / FR-07) ────────────────────────────────

  Future<void> _load() async {
    // Las categorías existentes llegan aunque la IA falle: el modo manual
    // (elegir/escribir) nunca depende de Gemini (FR-07).
    final cats = await _api.fetchProductCategories(); // degrada a [] sola
    if (!mounted) return;
    _knownCategories = cats;
    try {
      final res = await _api.suggestProductCategories();
      if (!mounted) return;
      final byId = <String, String>{
        for (final it in res)
          (it['id'] ?? '').toString(): (it['suggested'] ?? '').toString(),
      };
      setState(() {
        for (final r in _rows) {
          final s = (byId[r.id] ?? '').trim();
          // Normaliza la grafía de la sugerencia contra lo existente para
          // que la agrupación no parta "Bebidas"/"bebidas" en dos.
          if (s.isNotEmpty) r.suggested = canonicalValue(s, _knownCategories);
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // IA caída → todos a "Por clasificar" en modo manual (AC-05).
      setState(() {
        _aiDown = true;
        _loading = false;
      });
    }
  }

  // ── Derivados ────────────────────────────────────────────────────────────

  int get _pendingCount => _rows.where((r) => !r.leaving).length;
  int get _doneCount => _total - _pendingCount;

  List<_Row> get _applicableRows => _rows
      .where((r) => !r.leaving && r.effective != null)
      .toList(growable: false);

  List<_Row> get _failedRows =>
      _rows.where((r) => !r.leaving && r.failed).toList(growable: false);

  List<_Row> get _selectedRows => _rows
      .where((r) => !r.leaving && r.selected)
      .toList(growable: false);

  /// Agrupa por categoría efectiva (alfabético); sin categoría → grupo
  /// "Por clasificar" al final, en modo manual (FR-09). Incluye las tarjetas
  /// saliendo (leaving) para que su animación termine en su sitio.
  List<_Group> get _groups {
    final byCat = <String, List<_Row>>{};
    final manual = <_Row>[];
    for (final r in _rows) {
      final c = r.effective;
      if (c == null) {
        manual.add(r);
      } else {
        byCat.putIfAbsent(c, () => []).add(r);
      }
    }
    final names = byCat.keys.toList()..sort();
    return [
      for (final n in names) _Group(n, byCat[n]!, applicable: true),
      if (manual.isNotEmpty)
        _Group('Por clasificar', manual, applicable: false),
    ];
  }

  /// Opciones del selector: categorías del tenant + las vistas en la sesión.
  List<String> get _pickerOptions {
    final seen = <String>{};
    final out = <String>[];
    void add(String c) {
      final k = foldKey(c);
      if (k.isEmpty || seen.contains(k)) return;
      seen.add(k);
      out.add(c.trim());
    }

    for (final c in _knownCategories) {
      add(c);
    }
    for (final r in _rows) {
      final c = r.effective;
      if (c != null) add(c);
    }
    out.sort();
    return out;
  }

  void _rememberCategory(String cat) {
    final k = foldKey(cat);
    if (_knownCategories.any((c) => foldKey(c) == k)) return;
    _knownCategories = [..._knownCategories, cat];
  }

  // ── Aplicar (núcleo: pool de 4 updateProduct concurrentes) ──────────────

  Future<void> _applyRows(List<_Row> rows) async {
    final targets = rows
        .where((r) => !r.leaving && !r.busy && r.effective != null)
        .toList();
    if (targets.isEmpty || _applying) return;
    setState(() {
      _applying = true;
      for (final r in targets) {
        r.busy = true;
        r.failed = false;
      }
    });

    var ok = 0;
    var failed = 0;
    var gone = 0;
    var next = 0;

    Future<void> worker() async {
      while (next < targets.length) {
        final r = targets[next++];
        final cat = canonicalValue(r.effective!, _knownCategories);
        try {
          await _api.updateProduct(r.id, {'category': cat});
          if (!mounted) return;
          ok++;
          _rememberCategory(cat);
          setState(() {
            r.busy = false;
            r.selected = false;
            r.leaving = true; // sale SOLO con 2xx (FR-05)
          });
        } on AppError catch (e) {
          if (!mounted) return;
          if (e.statusCode == 404) {
            // Eliminado desde otro dispositivo (caso borde): se informa y
            // la tarjeta se retira sin romper el flujo.
            gone++;
            setState(() {
              r.busy = false;
              r.selected = false;
              r.leaving = true;
            });
          } else {
            failed++;
            setState(() {
              r.busy = false;
              r.failed = true; // permanece: el contador nunca miente (AC-07)
            });
          }
        } catch (_) {
          if (!mounted) return;
          failed++;
          setState(() {
            r.busy = false;
            r.failed = true;
          });
        }
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    if (!mounted) return;
    setState(() => _applying = false);

    // Resumen honesto (fallos parciales incluidos).
    if (gone > 0) {
      _toast(
        gone == 1
            ? 'Un producto ya no existe en el inventario; se retiró de la lista.'
            : '$gone productos ya no existen en el inventario; se retiraron.',
        error: true,
      );
    }
    if (failed > 0) {
      HapticFeedback.heavyImpact();
      _toast(
        ok > 0
            ? 'Se guardaron $ok; $failed no se guardaron. Toque Reintentar.'
            : 'No se pudo guardar. Revise su conexión y reintente.',
        error: true,
      );
    } else if (ok > 0) {
      HapticFeedback.mediumImpact();
      _toast(ok == 1
          ? 'Producto categorizado.'
          : '$ok productos categorizados.');
    }
  }

  Future<void> _applyGroup(_Group g) async {
    HapticFeedback.lightImpact();
    final n = g.activeCount;
    final confirmed = await _confirmApply(
        '¿Asignar "${g.name}" a $n producto${n == 1 ? '' : 's'}?');
    if (confirmed && mounted) await _applyRows(g.rows);
  }

  Future<void> _applyAll() async {
    HapticFeedback.lightImpact();
    final rows = _applicableRows;
    final confirmed = await _confirmApply(
        '¿Aplicar las ${rows.length} categorías revisadas?');
    if (confirmed && mounted) await _applyRows(rows);
  }

  /// Confirmación única de las acciones masivas (FR-04): 1 toque.
  Future<bool> _confirmApply(String title) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetHandle(),
            Text(title,
                maxLines: 3, overflow: TextOverflow.ellipsis, style: AppUI.title),
            const SizedBox(height: AppUI.s4),
            const Text('Solo cambia la categoría; precio, stock y fotos no se tocan.',
                style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s16),
            Row(children: [
              Expanded(
                child: AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ),
              const SizedBox(width: AppUI.s8),
              Expanded(
                child: AppButton(
                  label: 'Sí, aplicar',
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
    return ok == true;
  }

  // ── Edición y selección múltiple ─────────────────────────────────────────

  Future<void> _editCategory(_Row r) async {
    HapticFeedback.lightImpact();
    final cat = await showCategoryPickerSheet(
      context,
      title: 'Categoría para "${r.name}"',
      existing: _pickerOptions,
    );
    if (cat == null || !mounted) return;
    setState(() => r.manual = cat); // la del tendero gana a la IA (AC-04)
  }

  void _toggleSelectionMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        for (final r in _rows) {
          r.selected = false;
        }
      }
    });
  }

  void _toggleSelected(_Row r) {
    setState(() => r.selected = !r.selected);
  }

  /// FR-10: asignar UNA categoría a los N marcados en una sola acción.
  Future<void> _assignToSelection() async {
    final sel = _selectedRows;
    if (sel.isEmpty) return;
    HapticFeedback.lightImpact();
    final cat = await showCategoryPickerSheet(
      context,
      title:
          'Categoría para ${sel.length} producto${sel.length == 1 ? '' : 's'}',
      existing: _pickerOptions,
    );
    if (cat == null || !mounted) return;
    setState(() {
      for (final r in sel) {
        r.manual = cat;
      }
      _selectionMode = false;
    });
    await _applyRows(sel);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _removeRow(_Row row) {
    if (!mounted) return;
    setState(() => _rows.remove(row));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final allDone = !_loading && _pendingCount == 0;
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Organizar categorías', style: AppUI.title),
        actions: [
          if (!_loading && !allDone)
            Padding(
              padding: const EdgeInsets.only(right: AppUI.s8),
              // TextButton con métricas explícitas del kit — que no herede
              // el theme legacy (60×60 / 20px).
              child: TextButton(
                onPressed: _toggleSelectionMode,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: Text(_selectionMode ? 'Cancelar' : 'Seleccionar'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: AppUI.s16),
                Text('Analizando sus productos con IA…', style: AppUI.bodySoft),
              ]),
            )
          : allDone
              ? _allDone()
              : _content(),
      bottomNavigationBar: _bottomBar(allDone),
    );
  }

  Widget _content() {
    // Lista aplanada (header | tarjeta) con builder: inventarios de 200+
    // productos no congelan la UI (solo se construye lo visible).
    final items = <Object>[];
    for (final g in _groups) {
      items.add(g);
      items.addAll(g.rows);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child:
              Text('$_doneCount de $_total organizados', style: AppUI.bodyStrong),
        ),
      ),
      if (_aiDown) _aiDownBanner(),
      if (_failedRows.isNotEmpty) _retryBanner(),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            if (item is _Group) return _groupHeader(item);
            return _animatedCard(item as _Row);
          },
        ),
      ),
    ]);
  }

  /// Banner suave del modo manual (AC-05): la IA falló pero nada se bloquea.
  Widget _aiDownBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: const Row(children: [
        Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 22),
        SizedBox(width: AppUI.s8),
        Expanded(
          child: Text(
            'La IA no está disponible en este momento. '
            'Asigne las categorías manualmente.',
            style: AppUI.bodySoft,
          ),
        ),
      ]),
    );
  }

  /// Fallo honesto (AC-07): qué no se guardó + Reintentar. La tarjeta
  /// nunca se marcó hecha.
  Widget _retryBanner() {
    final n = _failedRows.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.wifi_off_rounded, color: AppTheme.error, size: 22),
        const SizedBox(width: AppUI.s8),
        Expanded(
          child: Text(
            n == 1
                ? 'Un producto no se guardó. Revise su conexión.'
                : '$n productos no se guardaron. Revise su conexión.',
            style: AppUI.bodyStrong,
          ),
        ),
        TextButton(
          onPressed: _applying ? null : () => _applyRows(_failedRows),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          child: const Text('Reintentar'),
        ),
      ]),
    );
  }

  /// Encabezado de grupo: nombre + conteo + "Aplicar grupo" (FR-09).
  Widget _groupHeader(_Group g) {
    if (g.activeCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppUI.s12, 0, AppUI.s8),
      child: Row(children: [
        Expanded(
          child: Text('${g.name} (${g.activeCount})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppUI.bodyStrong),
        ),
        if (g.applicable && !_selectionMode)
          CompactActionButton(
            icon: Icons.done_all_rounded,
            label: 'Aplicar grupo',
            onPressed: _applying ? null : () => _applyGroup(g),
          ),
      ]),
    );
  }

  /// La tarjeta guardada sale con animación (fade) y al terminar se remueve
  /// — sin Timers (seguro en pruebas y en dispose). Patrón Spec 100.
  Widget _animatedCard(_Row row) {
    return AnimatedOpacity(
      opacity: row.leaving ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      onEnd: () {
        if (row.leaving) _removeRow(row);
      },
      child: row.leaving ? IgnorePointer(child: _card(row)) : _card(row),
    );
  }

  Widget _card(_Row row) {
    return GestureDetector(
      onLongPress: _selectionMode
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectionMode = true;
                row.selected = true;
              });
            },
      onTap: _selectionMode ? () => _toggleSelected(row) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppUI.s8),
        padding: const EdgeInsets.all(AppUI.s12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUI.radius),
          border: Border.all(
              color: row.failed
                  ? AppTheme.error.withValues(alpha: 0.5)
                  : AppUI.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_selectionMode)
              Checkbox(
                value: row.selected,
                activeColor: AppTheme.primary,
                onChanged: (_) => _toggleSelected(row),
              ),
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
                  const SizedBox(height: AppUI.s8),
                  Row(children: [
                    Expanded(child: _categoryChip(row)),
                    if (!_selectionMode && row.effective != null) ...[
                      const SizedBox(width: AppUI.s8),
                      row.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : CompactActionButton(
                              icon: Icons.check_rounded,
                              label: 'Aplicar',
                              onPressed: _applying
                                  ? null
                                  : () => _applyRows([row]),
                            ),
                    ],
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(_Row row) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppUI.pageBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppUI.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ProductImage(
        url: row.photoUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: const Icon(Icons.inventory_2_outlined,
            color: AppUI.inkSoft, size: 22),
      ),
    );
  }

  /// Chip de categoría tocable: sugerencia ✨ (morado IA), corrección del
  /// tendero (azul marca) o "Elegir categoría" (manual). Tap → selector.
  Widget _categoryChip(_Row row) {
    final label = row.effective;
    final isSuggestion = row.manual == null && label != null;
    final color = label == null
        ? AppUI.inkSoft
        : (isSuggestion ? _kAiAccent : AppTheme.primary);
    return InkWell(
      onTap: _selectionMode ? null : () => _editCategory(row),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding:
            const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: AppUI.s8),
        decoration: BoxDecoration(
          color: label == null ? AppUI.pageBg : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(
            label == null
                ? Icons.sell_outlined
                : (isSuggestion ? Icons.auto_awesome : Icons.edit_outlined),
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppUI.s4 + 2),
          Flexible(
            child: Text(
              label ?? 'Elegir categoría',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ]),
      ),
    );
  }

  Widget? _bottomBar(bool allDone) {
    if (_loading || allDone) return null;
    if (_selectionMode) {
      final n = _selectedRows.length;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppUI.s16),
          child: AppButton(
            label: 'Asignar categoría a $n',
            icon: Icons.sell_outlined,
            onPressed: (n == 0 || _applying) ? null : _assignToSelection,
          ),
        ),
      );
    }
    final n = _applicableRows.length;
    if (n == 0) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppUI.s16),
        child: AppButton(
          label: 'Aplicar todas ($n)',
          icon: Icons.done_all_rounded,
          onPressed: _applying ? null : _applyAll,
        ),
      ),
    );
  }

  /// Estado vacío celebratorio (AC-03/FR-05): no quedan productos sueltos.
  Widget _allDone() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_rounded,
                size: 64, color: AppTheme.success),
            const SizedBox(height: AppUI.s16),
            const Text('¡Todo organizado!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppUI.ink)),
            const SizedBox(height: 8),
            const Text(
              'Todos sus productos ya tienen categoría. Su catálogo y su '
              'inventario se navegan mucho mejor.',
              textAlign: TextAlign.center,
              style: AppUI.bodySoft,
            ),
            const SizedBox(height: AppUI.s24),
            AppButton(
              label: 'Volver al inventario',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
