// Spec: specs/100-completar-skus-inventario/spec.md (T-21, D3, FR-12)
//
// Modo ráfaga: el escáner permanece ABIERTO (no se re-inicializa la cámara
// por ítem — 1-3 s/ítem de re-init en web) y cada lectura se asigna al
// producto en turno, auto-avanzando hasta agotar la cola. Duplicado →
// pausa con tarjeta de conflicto (Omitir/Corregir); el siguiente escaneo
// válido reanuda. Degradación sin cámara: campo de texto con autofocus —
// los lectores USB de pistola emiten teclado y Enter asigna y avanza.
//
// La confirmación de éxito NUNCA depende del audio (iOS Safari bloquea
// AudioContext sin interacción): haptic + flash verde 1 s siempre.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/retail_barcode_formats.dart';
import '../../widgets/html5_qrcode_scanner.dart';
import '../../widgets/product_image.dart';

/// Conflicto de duplicado: el código leído ya pertenece a otro producto.
class _Conflict {
  const _Conflict({required this.code, required this.owner});
  final String code;
  final Map<String, dynamic> owner;
}

/// Guardado fallido por red: se reintenta con el mismo código.
class _PendingRetry {
  const _PendingRetry(this.code);
  final String code;
}

/// Flash de confirmación (verde, 1 s) tras asignar con éxito.
class _Flash {
  const _Flash({required this.code, required this.productName, required this.seq});
  final String code;
  final String productName;
  final int seq; // fuerza un TweenAnimationBuilder nuevo por asignación
}

class SkuScanSessionScreen extends StatefulWidget {
  const SkuScanSessionScreen({
    super.key,
    required this.products,
    this.onAssigned,
    @visibleForTesting this.apiOverride,
    @visibleForTesting this.keyboardOnly = false,
  });

  /// Cola de productos SIN código, en orden (mapas crudos del backend).
  final List<Map<String, dynamic>> products;

  /// Notifica cada asignación exitosa a la pantalla padre (para que
  /// sincronice su lista/contador sin esperar al pop).
  final void Function(String productId, String code)? onAssigned;

  @visibleForTesting
  final ApiService? apiOverride;

  /// true = sin cámara: solo el campo de teclado (pruebas y degradación).
  @visibleForTesting
  final bool keyboardOnly;

  @override
  State<SkuScanSessionScreen> createState() => _SkuScanSessionScreenState();
}

class _SkuScanSessionScreenState extends State<SkuScanSessionScreen> {
  late final ApiService _api;
  MobileScannerController? _scannerCtrl;
  final _kbCtrl = TextEditingController();
  final _kbFocus = FocusNode();

  /// Web: el video HTML vive SOBRE el canvas de Flutter; se oculta (pause,
  /// no re-init) para que conflicto/flash/resumen sean visibles.
  final _webScannerVisible = ValueNotifier<bool>(true);

  late final List<Map<String, dynamic>> _queue;
  int _index = 0;
  int _assignedCount = 0;
  bool _busy = false;
  bool _useKeyboard = false;
  bool _finished = false;
  _Conflict? _conflict;
  _PendingRetry? _retry;
  _Flash? _flash;
  int _flashSeq = 0;
  String? _lastCode; // dedup de relecturas del mismo encuadre

  Map<String, dynamic> get _current => _queue[_index];
  String get _currentId => (_current['id'] ?? '').toString();
  String get _currentName => (_current['name'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _queue = List.of(widget.products);
    _useKeyboard = widget.keyboardOnly;
    if (_queue.isEmpty) _finished = true;
    if (!widget.keyboardOnly && !kIsWeb) {
      // Un solo controller para TODA la sesión (D3: cámara persistente).
      _scannerCtrl = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        formats: kRetailBarcodeFormats,
        returnImage: false,
      );
    }
  }

  @override
  void dispose() {
    _scannerCtrl?.dispose();
    _kbCtrl.dispose();
    _kbFocus.dispose();
    _webScannerVisible.dispose();
    super.dispose();
  }

  // ── Entrada de códigos ─────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty || code == _lastCode) return;
    _handleCode(code);
  }

  void _onKeyboardSubmit(String value) {
    _kbCtrl.clear();
    _kbFocus.requestFocus(); // listo para la siguiente pistola/tecleo
    _handleCode(value);
  }

  Future<void> _handleCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || _busy || _finished) return;
    setState(() {
      _busy = true;
      _lastCode = code;
      _conflict = null; // el siguiente escaneo válido reanuda la sesión
      _retry = null;
    });
    try {
      final owner = await _api.lookupProductByBarcode(code);
      if (!mounted) return;
      if (owner != null && (owner['id'] ?? '').toString() != _currentId) {
        _pauseWithConflict(code, owner);
        return;
      }
      await _api.updateProduct(_currentId, {'barcode': code});
      if (!mounted) return;
      _onAssignedOk(code);
    } on AppError catch (e) {
      if (!mounted) return;
      _onAssignError(code, e);
    } catch (_) {
      if (!mounted) return;
      _fail('Algo salió mal. Intente de nuevo.');
    }
  }

  // ── Resultados ─────────────────────────────────────────────────────────────

  void _onAssignedOk(String code) {
    // Confirmación multi-canal: el beep puede estar bloqueado (iOS Safari)
    // — el haptic y el flash verde NUNCA dependen de él.
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
    widget.onAssigned?.call(_currentId, code);
    final name = _currentName;
    setState(() {
      _assignedCount++;
      _busy = false;
      _lastCode = null;
      _flash = _Flash(code: code, productName: name, seq: ++_flashSeq);
      _advance();
    });
    if (kIsWeb) _webScannerVisible.value = false; // que el flash se VEA
  }

  void _onAssignError(String code, AppError e) {
    if (e.statusCode == 409 && e.errorCode == 'duplicate_barcode') {
      final owner = (e.payload?['existing_product'] as Map?)
              ?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      _pauseWithConflict(code, owner);
      return;
    }
    if (e.statusCode == 404) {
      // Producto eliminado mientras la sesión estaba abierta: se informa
      // y la tarjeta se retira sin romper el flujo (caso borde del spec).
      _toast('Ese producto ya no existe. Se pasa al siguiente.');
      setState(() {
        _busy = false;
        _lastCode = null;
        _advance();
      });
      return;
    }
    if (e.type == AppErrorType.network) {
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _retry = _PendingRetry(code);
      });
      if (kIsWeb) _webScannerVisible.value = false;
      return;
    }
    _fail(e.message);
  }

  void _pauseWithConflict(String code, Map<String, dynamic> owner) {
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _conflict = _Conflict(code: code, owner: owner);
    });
    if (kIsWeb) _webScannerVisible.value = false; // ceder pantalla a Flutter
  }

  void _fail(String message) {
    setState(() {
      _busy = false;
      _lastCode = null;
    });
    _toast(message);
  }

  /// Avanza al siguiente producto de la cola o cierra con resumen.
  void _advance() {
    if (_index + 1 < _queue.length) {
      _index++;
    } else {
      _finished = true;
    }
  }

  void _skipCurrent() {
    HapticFeedback.selectionClick();
    setState(() {
      _conflict = null;
      _lastCode = null;
      _advance();
    });
    _resumeWebScanner();
  }

  void _correctByKeyboard() {
    HapticFeedback.selectionClick();
    setState(() {
      _conflict = null;
      _lastCode = null;
      _useKeyboard = true;
    });
    _kbFocus.requestFocus();
  }

  void _resumeWebScanner() {
    if (kIsWeb && !_finished && !_useKeyboard) {
      _webScannerVisible.value = true;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: AppTheme.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _useKeyboard || _finished ? AppUI.pageBg : Colors.black,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Escanear en ráfaga'),
        actions: [
          if (!_finished && !widget.keyboardOnly)
            IconButton(
              icon: Icon(
                  _useKeyboard
                      ? Icons.photo_camera_rounded
                      : Icons.keyboard_alt_outlined,
                  size: 24),
              tooltip: _useKeyboard ? 'Usar cámara' : 'Digitar o lector USB',
              onPressed: () {
                setState(() => _useKeyboard = !_useKeyboard);
                if (_useKeyboard) {
                  _kbFocus.requestFocus();
                } else {
                  _resumeWebScanner();
                }
              },
            ),
        ],
      ),
      body: _finished ? _summary() : _session(),
    );
  }

  Widget _session() {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _useKeyboard ? _keyboardPane() : _cameraPane()),
            _turnBanner(),
          ],
        ),
        if (_conflict != null)
          Positioned(left: 16, right: 16, bottom: 120, child: _conflictCard()),
        if (_retry != null)
          Positioned(left: 16, right: 16, bottom: 120, child: _retryBanner()),
        if (_flash != null) _flashOverlay(),
      ],
    );
  }

  Widget _cameraPane() {
    if (kIsWeb) {
      return Html5QrcodeScannerWidget(
        onDetected: _handleCode,
        visibility: _webScannerVisible,
      );
    }
    return MobileScanner(
      controller: _scannerCtrl!,
      onDetect: _onDetect,
      errorBuilder: (context, error) => _cameraError(),
    );
  }

  /// Sin cámara utilizable → nunca un callejón sin salida (AC-07).
  Widget _cameraError() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography_outlined,
              color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
            'No se pudo usar la cámara. Puede digitar el código o usar un '
            'lector USB.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              setState(() => _useKeyboard = true);
              _kbFocus.requestFocus();
            },
            icon: const Icon(Icons.keyboard_alt_outlined, size: 20),
            label: const Text('Digitar o usar lector'),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(0, 48)),
          ),
        ],
      ),
    );
  }

  /// Degradación por teclado: campo con autofocus; los lectores USB de
  /// pistola escriben el código y emiten Enter → asigna y avanza.
  Widget _keyboardPane() {
    return Padding(
      padding: const EdgeInsets.all(AppUI.s16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.keyboard_alt_outlined,
              size: 40, color: AppUI.inkSoft),
          const SizedBox(height: AppUI.s12),
          const Text(
            'Digite el código o use su lector de código de barras.',
            textAlign: TextAlign.center,
            style: AppUI.bodySoft,
          ),
          const SizedBox(height: AppUI.s16),
          TextField(
            controller: _kbCtrl,
            focusNode: _kbFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 20, letterSpacing: 1),
            onSubmitted: _onKeyboardSubmit,
            decoration: InputDecoration(
              hintText: 'Código de barras…',
              hintStyle: const TextStyle(fontSize: 18, color: AppUI.inkSoft),
              prefixIcon: const Icon(Icons.qr_code_2_rounded, size: 26),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppUI.radius),
                borderSide: const BorderSide(color: AppUI.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppUI.radius),
                borderSide: const BorderSide(color: AppUI.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner "Asignando a: <producto> (k de N)" con foto y nombre grandes.
  Widget _turnBanner() {
    final photo = (_current['photo_url'] as String? ?? '').trim();
    final image = (_current['image_url'] as String? ?? '').trim();
    final url = photo.isNotEmpty ? photo : (image.isNotEmpty ? image : null);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppUI.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: ProductImage(
                  url: url,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  placeholder: const Icon(Icons.inventory_2_outlined,
                      color: AppUI.inkSoft, size: 28),
                ),
              ),
            ),
            const SizedBox(width: AppUI.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Asignando a: (${_index + 1} de ${_queue.length})',
                      style: AppUI.bodySoft),
                  const SizedBox(height: 2),
                  Text(
                    _currentName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppUI.ink),
                  ),
                ],
              ),
            ),
            if (_busy)
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }

  /// Tarjeta de conflicto: el código leído ya es de otro producto. Pausa la
  /// sesión; Omitir salta el producto en turno, Corregir abre el teclado.
  Widget _conflictCard() {
    final c = _conflict!;
    final ownerName = (c.owner['name'] ?? 'otro producto').toString();
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppUI.s16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUI.radius),
          border:
              Border.all(color: AppTheme.warning.withValues(alpha: 0.5)),
          boxShadow: AppUI.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.warning, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('El código ${c.code} ya es de "$ownerName"',
                    style: AppUI.bodyStrong),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              'No se asignó. Escanee otro código, omita este producto o '
              'corrija a mano.',
              style: AppUI.bodySoft,
            ),
            const SizedBox(height: AppUI.s12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _skipCurrent,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44)),
                  child: const Text('Omitir'),
                ),
              ),
              const SizedBox(width: AppUI.s8),
              Expanded(
                child: FilledButton(
                  onPressed: _correctByKeyboard,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size(0, 44)),
                  child: const Text('Corregir'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Error de red: honesto, sin marcar el producto como hecho.
  Widget _retryBanner() {
    final r = _retry!;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppUI.s16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppUI.radius),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
          boxShadow: AppUI.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sin conexión — el código de $_currentName no se guardó.',
              style: AppUI.bodyStrong,
            ),
            const SizedBox(height: AppUI.s12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  setState(() => _retry = null);
                  _handleCode(r.code);
                },
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 44)),
                child: const Text('Reintentar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Flash verde de 1 s tras asignar — la confirmación visual que nunca
  /// depende del beep. TweenAnimationBuilder (sin Timer: seguro en tests).
  Widget _flashOverlay() {
    final f = _flash!;
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey('sku-flash-${f.seq}'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(seconds: 1),
          onEnd: () {
            if (!mounted) return;
            setState(() => _flash = null);
            _resumeWebScanner();
          },
          builder: (_, t, __) {
            final opacity = t < 0.2 ? t / 0.2 : 1 - ((t - 0.2) / 0.8);
            return Opacity(
              opacity: opacity.clamp(0, 1),
              child: Container(
                color: AppTheme.success.withValues(alpha: 0.85),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 72),
                    const SizedBox(height: 8),
                    Text(f.productName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Text(f.code,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Cola agotada → resumen y volver (la pantalla padre ya recibió cada
  /// asignación vía [SkuScanSessionScreen.onAssigned]).
  Widget _summary() {
    final skipped = _queue.length - _assignedCount;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_rounded,
                size: 64, color: AppTheme.success),
            const SizedBox(height: AppUI.s16),
            Text(
              _assignedCount == 1
                  ? '1 código asignado'
                  : '$_assignedCount códigos asignados',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: AppUI.ink),
            ),
            if (skipped > 0) ...[
              const SizedBox(height: 4),
              Text(
                skipped == 1
                    ? '1 producto quedó pendiente'
                    : '$skipped productos quedaron pendientes',
                style: AppUI.bodySoft,
              ),
            ],
            const SizedBox(height: AppUI.s24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(0, 48)),
                child: const Text('Volver'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
