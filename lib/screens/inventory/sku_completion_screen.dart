// Spec: specs/100-completar-skus-inventario/spec.md
//
// Vista dedicada "Completar SKUs" (patrón de Spec 097 "Completar fotos"):
// recibe la lista YA prefiltrada de referencias físicas sin código y ofrece
// por tarjeta las acciones justas — Escanear / Generar / Digitar — hasta
// vaciar la lista. Duplicados (pre-check o 409 del backend) → tarjeta de
// conflicto con el producto dueño (Omitir/Corregir): NUNCA se asigna en
// silencio (AC-04). Código GENERADO que colisiona → se regenera y reintenta
// solo (máx 3), invisible al tendero (D2). Error de red → banner honesto +
// Reintentar; la tarjeta no se marca hecha (el contador nunca miente).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/sku_generator.dart';
import '../../widgets/compact_action_button.dart';
import '../../widgets/product_image.dart';
import '../../widgets/sku_manual_code_sheet.dart';
import 'sku_scan_session_screen.dart';

/// Estado mutable por producto dentro del flujo (patrón _Row de Spec 097).
class _Row {
  _Row(this.product);
  final Map<String, dynamic> product;

  bool busy = false;
  bool leaving = false; // asignado: la tarjeta sale con animación
  _Conflict? conflict;

  String get id => (product['id'] ?? product['uuid'] ?? '').toString();
  String get name => (product['name'] ?? '').toString();
  String get presentation => (product['presentation'] ?? '').toString();
  double get price => (product['price'] as num?)?.toDouble() ?? 0;

  String? get photoUrl {
    final photo = (product['photo_url'] as String? ?? '').trim();
    final image = (product['image_url'] as String? ?? '').trim();
    final v = photo.isNotEmpty ? photo : image;
    return v.isEmpty ? null : v;
  }
}

/// El código intentado ya pertenece a otro producto del negocio.
class _Conflict {
  const _Conflict({required this.code, required this.owner});
  final String code;
  final Map<String, dynamic> owner;
}

/// Guardado fallido por red, pendiente de reintento manual.
class _PendingRetry {
  const _PendingRetry(this.row, this.code, {required this.generated});
  final _Row row;
  final String code;
  final bool generated;
}

class SkuCompletionScreen extends StatefulWidget {
  const SkuCompletionScreen({
    super.key,
    required this.products,
    @visibleForTesting this.apiOverride,
    @visibleForTesting this.scanSessionKeyboardOnly = false,
  });

  /// Referencias físicas SIN código (mapas crudos del backend), ya
  /// prefiltradas por la pantalla de inventario (sede activa, sin platos
  /// ni servicios — FR-09/FR-11).
  final List<Map<String, dynamic>> products;

  @visibleForTesting
  final ApiService? apiOverride;

  /// Solo pruebas: la sesión de ráfaga arranca en modo teclado (sin cámara).
  @visibleForTesting
  final bool scanSessionKeyboardOnly;

  @override
  State<SkuCompletionScreen> createState() => _SkuCompletionScreenState();
}

class _SkuCompletionScreenState extends State<SkuCompletionScreen> {
  late final ApiService _api;
  late final List<_Row> _rows;
  late final int _total;
  _PendingRetry? _retry;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _rows = widget.products.map(_Row.new).toList();
    _total = _rows.length;
  }

  int get _pendingCount => _rows.where((r) => !r.leaving).length;
  int get _doneCount => _total - _pendingCount;

  // ── Asignación (núcleo compartido por las 3 acciones) ─────────────────────

  String _newCodeFor(_Row row) =>
      generateSku(name: row.name, presentation: row.presentation);

  /// Guarda [code] en [row]. Pre-check de duplicado + manejo del 409 del
  /// backend (D1: doble capa). Si [generated], las colisiones se resuelven
  /// regenerando en silencio hasta 3 intentos (D2).
  Future<void> _assignCode(_Row row, String code,
      {required bool generated}) async {
    if (row.busy) return;
    setState(() {
      row.busy = true;
      row.conflict = null;
      _retry = null;
    });
    var attempt = code;
    for (var i = 0; i < 3; i++) {
      try {
        final owner = await _api.lookupProductByBarcode(attempt);
        if (!mounted) return;
        if (owner != null && (owner['id'] ?? '').toString() != row.id) {
          if (generated && i < 2) {
            attempt = _newCodeFor(row);
            continue; // colisión de código generado: regenerar en silencio
          }
          _showConflict(row, attempt, owner);
          return;
        }
        await _api.updateProduct(row.id, {'barcode': attempt});
        if (!mounted) return;
        _markDone(row, attempt);
        return;
      } on AppError catch (e) {
        if (!mounted) return;
        if (e.statusCode == 409 && e.errorCode == 'duplicate_barcode') {
          if (generated && i < 2) {
            attempt = _newCodeFor(row);
            continue;
          }
          final owner = (e.payload?['existing_product'] as Map?)
                  ?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          _showConflict(row, attempt, owner);
          return;
        }
        _handleAssignError(row, attempt, e, generated: generated);
        return;
      } catch (_) {
        if (!mounted) return;
        _fail(row, 'Algo salió mal. Intente de nuevo.');
        return;
      }
    }
    _fail(row, 'No se pudo generar un código único. Intente de nuevo.');
  }

  void _handleAssignError(_Row row, String code, AppError e,
      {required bool generated}) {
    if (e.type == AppErrorType.network) {
      // El contador nunca miente: la tarjeta NO se marca hecha.
      HapticFeedback.heavyImpact();
      setState(() {
        row.busy = false;
        _retry = _PendingRetry(row, code, generated: generated);
      });
      return;
    }
    if (e.statusCode == 404) {
      // Producto eliminado mientras la vista estaba abierta (caso borde):
      // se informa y la tarjeta se retira sin romper el flujo.
      _toast('Ese producto ya no existe en el inventario.', error: true);
      setState(() {
        row.busy = false;
        row.leaving = true;
      });
      return;
    }
    _fail(row, e.message);
  }

  void _showConflict(_Row row, String code, Map<String, dynamic> owner) {
    HapticFeedback.heavyImpact();
    setState(() {
      row.busy = false;
      row.conflict = _Conflict(code: code, owner: owner);
    });
  }

  void _markDone(_Row row, String code) {
    HapticFeedback.mediumImpact();
    setState(() {
      row.busy = false;
      row.leaving = true; // AnimatedOpacity la saca; onEnd la remueve
    });
    _toast('Código $code asignado a "${row.name}".');
  }

  void _fail(_Row row, String message) {
    setState(() => row.busy = false);
    _toast(message, error: true);
  }

  void _removeRow(_Row row) {
    if (!mounted) return;
    setState(() => _rows.remove(row));
  }

  // ── Acciones por tarjeta ───────────────────────────────────────────────────

  /// Escanear UNA tarjeta reutiliza la sesión de ráfaga con cola de 1:
  /// mismo escáner persistente, misma tarjeta de conflicto (D3/D4).
  Future<void> _scanOne(_Row row) async {
    HapticFeedback.lightImpact();
    await _openScanSession([row]);
  }

  Future<void> _openBurstMode() async {
    HapticFeedback.lightImpact();
    final pending = _rows.where((r) => !r.leaving).toList();
    if (pending.isEmpty) return;
    await _openScanSession(pending);
  }

  Future<void> _openScanSession(List<_Row> rows) async {
    final byId = {for (final r in rows) r.id: r};
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SkuScanSessionScreen(
        products: rows.map((r) => r.product).toList(),
        apiOverride: widget.apiOverride,
        keyboardOnly: widget.scanSessionKeyboardOnly,
        onAssigned: (productId, code) {
          final row = byId[productId];
          if (row != null && !row.leaving) _markDone(row, code);
        },
      ),
    ));
  }

  Future<void> _generate(_Row row) async {
    HapticFeedback.lightImpact();
    var code = _newCodeFor(row);
    final confirmed = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => _sheetFrame(
          title: 'Código para "${row.name}"',
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppUI.pageBg,
                borderRadius: BorderRadius.circular(AppUI.radius),
                border: Border.all(color: AppUI.border),
              ),
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppUI.ink),
              ),
            ),
            const SizedBox(height: AppUI.s12),
            Row(children: [
              Expanded(
                child: AppButton(
                  label: 'Generar otro',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => setSheet(() => code = _newCodeFor(row)),
                ),
              ),
              const SizedBox(width: AppUI.s8),
              Expanded(
                child: AppButton(
                  label: 'Guardar',
                  onPressed: () => Navigator.of(ctx).pop(code),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
    if (confirmed != null && mounted) {
      await _assignCode(row, confirmed, generated: true);
    }
  }

  Future<void> _typeManually(_Row row, {String? prefill}) async {
    HapticFeedback.lightImpact();
    final confirmed = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // que el teclado no tape el campo
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SkuManualCodeSheet(productName: row.name, prefill: prefill),
    );
    if (confirmed != null && mounted) {
      await _assignCode(row, confirmed, generated: false);
    }
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────

  Widget _sheetFrame({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sheetHandle(),
          Text(title,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: AppUI.title),
          const SizedBox(height: AppUI.s16),
          ...children,
        ],
      ),
    );
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  static String _formatPrice(double price) {
    final s = price.round().toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Completar SKUs'),
      ),
      body: _rows.isEmpty
          ? _allDone()
          : Column(
              children: [
                _header(),
                if (_retry != null) _retryBanner(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) => _animatedCard(_rows[i]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_doneCount de $_total completados', style: AppUI.bodyStrong),
          // FR-12: con varias pendientes, la ráfaga encadena escaneos sin
          // toques intermedios (el camino rápido frente al estante).
          if (_pendingCount > 1) ...[
            const SizedBox(height: AppUI.s8),
            AppButton(
              label: 'Modo ráfaga',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: _openBurstMode,
            ),
          ],
        ],
      ),
    );
  }

  /// Error de red honesto: qué producto no se guardó + Reintentar (D5).
  Widget _retryBanner() {
    final r = _retry!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
            'Sin conexión — el código de "${r.row.name}" no se guardó.',
            style: AppUI.bodyStrong,
          ),
        ),
        // TextButton discreto con métricas explícitas del kit — que no
        // herede el theme legacy (20px / 60×60).
        TextButton(
          onPressed: () =>
              _assignCode(r.row, r.code, generated: r.generated),
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

  /// La tarjeta asignada sale con animación (fade) y al terminar se remueve
  /// de la lista — sin Timers (seguro en pruebas y en dispose).
  Widget _animatedCard(_Row row) {
    return AnimatedOpacity(
      opacity: row.leaving ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      onEnd: () {
        if (row.leaving) _removeRow(row);
      },
      child: _card(row),
    );
  }

  Widget _card(_Row row) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(
            color: row.conflict != null
                ? AppTheme.warning.withValues(alpha: 0.5)
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
                    Text(
                      _formatPrice(row.price),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary),
                    ),
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
          if (row.conflict != null) ...[
            const SizedBox(height: AppUI.s12),
            _conflictBlock(row),
          ],
          if (!row.busy) ...[
            const SizedBox(height: AppUI.s12),
            _actions(row),
          ],
        ],
      ),
    );
  }

  Widget _thumb(_Row row) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppUI.pageBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppUI.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ProductImage(
        url: row.photoUrl,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: const Icon(Icons.inventory_2_outlined,
            color: AppUI.inkSoft, size: 24),
      ),
    );
  }

  /// Conflicto de duplicado: muestra el producto DUEÑO del código (AC-04)
  /// como tarjeta no bloqueante — Omitir descarta el código, Corregir abre
  /// el campo para digitarlo bien.
  Widget _conflictBlock(_Row row) {
    final c = row.conflict!;
    final ownerName = (c.owner['name'] ?? 'otro producto').toString();
    final ownerPres = (c.owner['presentation'] ?? '').toString();
    final ownerPhoto = (c.owner['photo_url'] as String? ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(AppUI.s8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: ProductImage(
                  url: ownerPhoto.isEmpty ? null : ownerPhoto,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  placeholder: const Icon(Icons.inventory_2_outlined,
                      color: AppUI.inkSoft, size: 22),
                ),
              ),
            ),
            const SizedBox(width: AppUI.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('El código ${c.code} ya es de "$ownerName"',
                      style: AppUI.bodyStrong),
                  if (ownerPres.isNotEmpty)
                    Text(ownerPres, style: AppUI.bodySoft),
                ],
              ),
            ),
          ]),
          const SizedBox(height: AppUI.s8),
          Row(children: [
            Expanded(
              child: AppButton(
                label: 'Omitir',
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => row.conflict = null);
                },
              ),
            ),
            const SizedBox(width: AppUI.s8),
            Expanded(
              child: AppButton(
                label: 'Corregir',
                onPressed: () {
                  final code = c.code;
                  setState(() => row.conflict = null);
                  _typeManually(row, prefill: code);
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// UNA fila horizontal de acciones compactas (icono + label corto), la
  /// altura de tarjeta de los módulos hermanos (097/101). El botón
  /// compartido lleva estilo explícito completo: el theme legacy de
  /// OutlinedButton (64dp / 22px) no participa y nada se apila ni desborda
  /// a 360dp.
  Widget _actions(_Row row) {
    return Row(children: [
      Expanded(
        child: CompactActionButton(
            icon: Icons.qr_code_scanner_rounded,
            label: 'Escanear',
            onPressed: () => _scanOne(row)),
      ),
      const SizedBox(width: AppUI.s8),
      Expanded(
        child: CompactActionButton(
            icon: Icons.auto_awesome,
            label: 'Generar',
            onPressed: () => _generate(row)),
      ),
      const SizedBox(width: AppUI.s8),
      Expanded(
        child: CompactActionButton(
            icon: Icons.keyboard_alt_outlined,
            label: 'Digitar',
            onPressed: () => _typeManually(row)),
      ),
    ]);
  }

  /// Estado vacío celebratorio (AC-05): no quedan referencias sin código.
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
            const Text('¡Todo completo!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppUI.ink)),
            const SizedBox(height: 8),
            const Text(
              'Todas sus referencias ya tienen código. El escáner del POS '
              'las encontrará al venderlas.',
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
