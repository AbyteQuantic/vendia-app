// Spec: specs/085-vender-por-voz/spec.md
//
// Orquestador de "vender por voz". NO toca el carrito hasta applyConfirmed().
// buildPreview() es PURO (testeable). La grabación reusa voice_recorder.dart.

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../../models/product.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/voice_recorder.dart';
import '../cart_controller.dart';
import 'product_resolver.dart';
import 'voice_command.dart';

enum VoicePhase { idle, recording, uploading, resolving, review, error }

/// Una línea de la previsualización (antes de aplicar al carrito).
class PreviewLine {
  final VoiceAction action; // agregar | quitar | fijarCantidad
  final String spokenName;
  Product? product;
  int quantity; // delta a agregar/quitar, o total para fijarCantidad
  ResolveStatus status;
  List<Product> candidates;

  PreviewLine({
    required this.action,
    required this.spokenName,
    this.product,
    this.quantity = 1,
    this.status = ResolveStatus.notFound,
    this.candidates = const [],
  });

  bool get priceMissing => product != null && product!.price <= 0;
}

/// Resultado de la previsualización (inmutable para la UI).
class PreviewModel {
  final VoiceTarget? target;
  final List<PreviewLine> lines;
  final bool hasCobrar;
  final bool hasVaciar;
  final String? clarifyPrompt;

  const PreviewModel({
    this.target,
    this.lines = const [],
    this.hasCobrar = false,
    this.hasVaciar = false,
    this.clarifyPrompt,
  });

  bool get isEmpty => lines.isEmpty && target == null && !hasCobrar && !hasVaciar;
}

/// PURA: arma la previsualización desde los comandos del LLM + el catálogo.
/// No muta nada. Resuelve cada item con [resolver].
PreviewModel buildPreview(
  VoiceOrderResult result,
  List<Product> catalog,
  ProductResolver resolver,
) {
  VoiceTarget? target;
  final lines = <PreviewLine>[];
  var hasCobrar = false;
  var hasVaciar = false;

  for (final cmd in result.commands) {
    switch (cmd.action) {
      case VoiceAction.fijarMesa:
      case VoiceAction.fijarCliente:
        if (cmd.target != null) target = cmd.target;
      case VoiceAction.vaciar:
        hasVaciar = true;
      case VoiceAction.cobrar:
        hasCobrar = true;
      case VoiceAction.agregar:
      case VoiceAction.quitar:
      case VoiceAction.fijarCantidad:
        final spoken = cmd.item ?? '';
        if (spoken.isEmpty) break;
        final res = resolver.resolve(spoken, catalog);
        final qty = cmd.quantity ?? (cmd.action == VoiceAction.quitar ? 0 : 1);
        lines.add(PreviewLine(
          action: cmd.action,
          spokenName: spoken,
          product: res.product,
          quantity: qty < 0 ? 0 : qty,
          status: res.status,
          candidates: res.candidates,
        ));
      case VoiceAction.desconocido:
        break;
    }
  }
  return PreviewModel(
    target: target,
    lines: lines,
    hasCobrar: hasCobrar,
    hasVaciar: hasVaciar,
    clarifyPrompt: result.clarifyPrompt,
  );
}

/// PURA: MERGE de nuevos comandos sobre una previsualización existente
/// (corrección por voz dentro de la preview, sin tocar el carrito). agregar
/// acumula sobre la línea del mismo producto; quitar resta/elimina; fijar_cantidad
/// fija; vaciar limpia las líneas; el destino y cobrar se actualizan.
PreviewModel mergeIntoPreview(
  PreviewModel current,
  VoiceOrderResult result,
  List<Product> catalog,
  ProductResolver resolver,
) {
  var target = current.target;
  var hasCobrar = current.hasCobrar;
  var hasVaciar = current.hasVaciar;
  final lines = List<PreviewLine>.from(current.lines);

  PreviewLine? findByProduct(Product p) {
    for (final l in lines) {
      if (l.product != null && l.product!.uuid == p.uuid) return l;
    }
    return null;
  }

  for (final cmd in result.commands) {
    switch (cmd.action) {
      case VoiceAction.fijarMesa:
      case VoiceAction.fijarCliente:
        if (cmd.target != null) target = cmd.target;
      case VoiceAction.vaciar:
        lines.clear();
      case VoiceAction.cobrar:
        hasCobrar = true;
      case VoiceAction.agregar:
      case VoiceAction.quitar:
      case VoiceAction.fijarCantidad:
        final spoken = cmd.item ?? '';
        if (spoken.isEmpty) break;
        final res = resolver.resolve(spoken, catalog);
        final qty = cmd.quantity ?? (cmd.action == VoiceAction.quitar ? 0 : 1);
        if (res.status == ResolveStatus.matched && res.product != null) {
          final existing = findByProduct(res.product!);
          if (cmd.action == VoiceAction.quitar) {
            if (existing != null) {
              if (cmd.quantity == null || existing.quantity - qty <= 0) {
                lines.remove(existing);
              } else {
                existing.quantity -= qty;
              }
            }
          } else if (cmd.action == VoiceAction.fijarCantidad) {
            if (existing != null) {
              existing.quantity = qty;
            } else {
              lines.add(PreviewLine(
                  action: VoiceAction.fijarCantidad,
                  spokenName: spoken,
                  product: res.product,
                  quantity: qty,
                  status: ResolveStatus.matched));
            }
          } else {
            // agregar
            if (existing != null) {
              existing.quantity += qty;
            } else {
              lines.add(PreviewLine(
                  action: VoiceAction.agregar,
                  spokenName: spoken,
                  product: res.product,
                  quantity: qty,
                  status: ResolveStatus.matched));
            }
          }
        } else if (cmd.action != VoiceAction.quitar) {
          // Producto ambiguo / no encontrado en una corrección de agregar/fijar:
          // mostrarlo para que el tendero lo resuelva.
          lines.add(PreviewLine(
            action: cmd.action,
            spokenName: spoken,
            product: res.product,
            quantity: qty < 0 ? 0 : qty,
            status: res.status,
            candidates: res.candidates,
          ));
        }
      case VoiceAction.desconocido:
        break;
    }
  }
  return PreviewModel(
    target: target,
    lines: lines,
    hasCobrar: hasCobrar,
    hasVaciar: hasVaciar,
    clarifyPrompt: current.clarifyPrompt,
  );
}

/// Resultado de aplicar la previsualización al carrito.
class ApplyOutcome {
  final int appliedLines;
  final bool requestCheckout;
  final bool requestEmpty;
  const ApplyOutcome({
    this.appliedLines = 0,
    this.requestCheckout = false,
    this.requestEmpty = false,
  });
}

typedef VoiceOrderApi = Future<Map<String, dynamic>> Function({
  required Uint8List audioBytes,
  required String mimeType,
  required String filename,
});

class VoiceOrderController extends ChangeNotifier {
  final CartController cart;
  final ProductResolver resolver;
  final VoiceOrderApi _api;
  final AudioRecorder _recorder;
  final Future<String> Function() _resolvePath;
  final Future<RecordedAudio> Function(String) _readAudio;

  VoiceOrderController({
    required this.cart,
    ApiService? api,
    ProductResolver? resolver,
    AudioRecorder? recorder,
    VoiceOrderApi? apiCall,
    Future<String> Function()? resolvePath,
    Future<RecordedAudio> Function(String)? readAudio,
  })  : resolver = resolver ?? const ProductResolver(),
        _recorder = recorder ?? AudioRecorder(),
        _api = apiCall ?? (api ?? ApiService(AuthService())).voiceOrder,
        _resolvePath = resolvePath ?? recordingPath,
        _readAudio = readAudio ?? readRecordedAudio;

  VoicePhase _phase = VoicePhase.idle;
  VoicePhase get phase => _phase;
  String? _error;
  String? get error => _error;
  PreviewModel _preview = const PreviewModel();
  PreviewModel get preview => _preview;
  bool _consumed = false; // guard anti-doble-aplicación
  String? _activeIndexAtPreview;
  bool _correcting = false; // segunda grabación que MERGEA sobre la preview

  String? _stopPath;

  /// Inicia una corrección por voz SOBRE la preview actual ("agregue dos panes
  /// más", "quite la gaseosa", "que el agua sean tres"). Mergea, no reemplaza.
  Future<void> startCorrection() async {
    _correcting = true;
    await startRecording();
  }

  void _set(VoicePhase p, {String? error}) {
    _phase = p;
    _error = error;
    notifyListeners();
  }

  Future<void> startRecording() async {
    if (_phase == VoicePhase.recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _set(VoicePhase.error,
            error: 'Para vender hablando, permita el micrófono.');
        return;
      }
      final cfg = await resolveRecordConfig(_recorder);
      final path = await _resolvePath();
      await _recorder.start(cfg, path: path);
      _set(VoicePhase.recording);
    } catch (_) {
      _set(VoicePhase.error,
          error: 'No se pudo iniciar la grabación. Intente de nuevo.');
    }
  }

  Future<void> stopAndProcess() async {
    if (_phase != VoicePhase.recording) return;
    _set(VoicePhase.uploading);
    try {
      _stopPath = await _recorder.stop();
      if (_stopPath == null) {
        _set(VoicePhase.error, error: 'No alcancé a escucharle. Hable cerquita.');
        return;
      }
      final audio = await _readAudio(_stopPath!);
      // Audio diminuto = no se captó voz (permiso recién dado, toque muy corto,
      // mic mudo). Mejor un mensaje claro que mandar bytes vacíos a la IA y
      // recibir `degraded`.
      if (audio.bytes.length < 1200) {
        _set(VoicePhase.error,
            error: 'No alcancé a escucharle. Hable cerquita y un poco más.');
        disposeRecordedAudio(_stopPath!);
        return;
      }
      final json = await _api(
        audioBytes: audio.bytes,
        mimeType: audio.mimeType,
        filename: audio.filename,
      );
      disposeRecordedAudio(_stopPath!);
      _set(VoicePhase.resolving);

      final correcting = _correcting;
      _correcting = false;
      final result = VoiceOrderResult.fromJson(json);

      // CORRECCIÓN: mergea sobre la preview existente; nunca la pierde.
      if (correcting) {
        if (result.degraded || result.commands.isEmpty) {
          _set(VoicePhase.review,
              error: 'No entendí la corrección. Intente otra vez.');
          return;
        }
        _preview = mergeIntoPreview(_preview, result, cart.allProducts, resolver);
        _consumed = false;
        _set(VoicePhase.review);
        return;
      }

      if (result.degraded) {
        _set(VoicePhase.error,
            error:
                'No hay señal para entender la voz ahora. Puede agregar tocando los productos.');
        return;
      }
      _preview = buildPreview(result, cart.allProducts, resolver);
      _consumed = false;
      _activeIndexAtPreview = '${cart.activeIndex}';
      if (_preview.isEmpty && _preview.clarifyPrompt == null) {
        _set(VoicePhase.error,
            error:
                'No entendí bien. ¿Lo repite más despacio? Ejemplo: dos Coca-Cola y un pan.');
        return;
      }
      _set(VoicePhase.review);
    } catch (_) {
      _correcting = false;
      _set(VoicePhase.error,
          error: 'No se pudo procesar el audio. Intente de nuevo.');
    }
  }

  // ── Edición de la previsualización (no toca el carrito) ───────────────────

  void setLineQuantity(PreviewLine line, int qty) {
    line.quantity = qty < 0 ? 0 : qty;
    notifyListeners();
  }

  void removeLine(PreviewLine line) {
    _preview = PreviewModel(
      target: _preview.target,
      lines: _preview.lines.where((l) => l != line).toList(),
      hasCobrar: _preview.hasCobrar,
      hasVaciar: _preview.hasVaciar,
      clarifyPrompt: _preview.clarifyPrompt,
    );
    notifyListeners();
  }

  void chooseCandidate(PreviewLine line, Product product) {
    line.product = product;
    line.status = ResolveStatus.matched;
    line.candidates = const [];
    notifyListeners();
  }

  /// ¿El carrito activo cambió desde que se armó la preview?
  bool get activeChangedSincePreview =>
      _activeIndexAtPreview != null && _activeIndexAtPreview != '${cart.activeIndex}';

  /// Aplica la previsualización al CART ACTIVO. Idempotente (token consumido).
  /// Sólo aplica líneas resueltas (matched, con precio). Devuelve qué pedir
  /// además (vaciar/cobrar se confirman en la UI por separado).
  ApplyOutcome applyConfirmed() {
    if (_consumed) {
      return const ApplyOutcome();
    }
    _consumed = true;

    // Destino primero.
    final t = _preview.target;
    if (t != null) {
      switch (t.type) {
        case VoiceTargetType.mesa:
          if ((t.mesa ?? '').isNotEmpty) {
            cart.setContext(AccountContext(
                type: AccountType.mesa, tableLabel: t.mesa));
          }
        case VoiceTargetType.cliente:
          if ((t.cliente ?? '').isNotEmpty) {
            cart.setContext(AccountContext(
                type: AccountType.mostrador, customerName: t.cliente));
          }
        case VoiceTargetType.mostrador:
          break;
      }
    }

    var applied = 0;
    for (final line in _preview.lines) {
      final p = line.product;
      if (p == null || line.status != ResolveStatus.matched || p.price <= 0) {
        continue; // ambiguos / no encontrados / sin precio no se aplican
      }
      final current = cart.getQuantity(p);
      switch (line.action) {
        case VoiceAction.agregar:
          if (current == 0) {
            if (!cart.addProduct(p)) break; // guard price<=0
          }
          cart.setQuantity(p, current + line.quantity);
          applied++;
        case VoiceAction.fijarCantidad:
          if (current == 0 && line.quantity > 0) cart.addProduct(p);
          cart.setQuantity(p, line.quantity);
          applied++;
        case VoiceAction.quitar:
          final target = line.quantity <= 0 ? 0 : (current - line.quantity);
          cart.setQuantity(p, target < 0 ? 0 : target);
          applied++;
        default:
          break;
      }
    }
    notifyListeners();
    return ApplyOutcome(
      appliedLines: applied,
      requestCheckout: _preview.hasCobrar,
      requestEmpty: _preview.hasVaciar,
    );
  }

  void reset() {
    _preview = const PreviewModel();
    _consumed = false;
    _correcting = false;
    _activeIndexAtPreview = null;
    _set(VoicePhase.idle);
  }
}
