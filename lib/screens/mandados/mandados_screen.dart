// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/format_cop.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';

/// Mandados / Pendientes de compra (Spec 077): las listas de compra que el
/// tenant asignó (a proveedor/contacto/empleado), con su estado. Permite
/// marcar comprado/cancelado y reenviar.
class MandadosScreen extends StatefulWidget {
  final ApiService? api;
  const MandadosScreen({super.key, this.api});

  @override
  State<MandadosScreen> createState() => _MandadosScreenState();
}

class _MandadosScreenState extends State<MandadosScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _errands = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _api.fetchErrands();
      if (!mounted) return;
      setState(() {
        _errands = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar los pendientes.';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await _api.updateErrandStatus(id, status);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo actualizar.'), backgroundColor: AppTheme.error));
      }
    }
  }

  /// Marcar COMPRADO abre "¿Cuánto compró?" (default = todo; ajusta lo que faltó)
  /// e INGRESA al inventario lo realmente comprado (sube stock + costo + compra
  /// real). Lo que faltó queda pendiente. Spec 077/078 B3.
  Future<void> _markBought(Map<String, dynamic> e) async {
    final id = e['id'].toString();
    final lines = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _WhatBoughtSheet(errand: e, api: _api),
    );
    if (lines == null) return; // canceló
    try {
      final res = await _api.receiveErrand(id, lines: lines);
      await _load();
      if (mounted) {
        final msg = res.status == 'parcial'
            ? 'Ingresado lo comprado. Lo que faltó quedó pendiente.'
            : (res.received > 0
                ? 'Listo: ${res.received} producto(s) ingresado(s) al inventario.'
                : 'Mandado marcado como comprado.');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppTheme.success));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo ingresar el inventario.'), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _resend(Map<String, dynamic> e) async {
    final lines = (e['lines'] as List?) ?? [];
    final b = StringBuffer('Buenos días, necesito comprar:\n');
    for (final l in lines) {
      final m = Map<String, dynamic>.from(l as Map);
      final q = (m['qty'] as num?)?.toDouble() ?? 0;
      final qs = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
      b.writeln('• ${m['name']} — $qs ${m['unit']}');
    }
    await Share.share(b.toString(), subject: 'Lista de compra');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Pendientes de compra', style: AppUI.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : _errands.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(AppUI.s24),
                      child: Text('Aún no tiene mandados.\nEnvíe una lista de compra desde "Comprar lo que falta".',
                          textAlign: TextAlign.center, style: AppUI.bodySoft),
                    ))
                  : Column(children: [
                      const _IngresoHint(),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            key: const Key('mandados_list'),
                            padding: const EdgeInsets.all(AppUI.s16),
                            itemCount: _errands.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
                            itemBuilder: (_, i) => _card(_errands[i]),
                          ),
                        ),
                      ),
                    ]),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final id = e['id'].toString();
    final status = (e['status'] ?? 'pendiente').toString();
    final who = (e['assignee_name'] ?? '').toString();
    final total = (e['total_estimated'] as num?)?.toDouble() ?? 0;
    final lines = (e['lines'] as List?) ?? [];
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(who.isNotEmpty ? who : 'Compra de insumos', style: AppUI.bodyStrong)),
          _statusBadge(status),
        ]),
        const SizedBox(height: 4),
        Text('${lines.length} producto(s) · ${formatCOP(total)}', style: AppUI.bodySoft),
        // Detalle: QUÉ comprar (nombre · cantidad unidad). Antes solo el resumen.
        if (lines.isNotEmpty) ...[
          const SizedBox(height: AppUI.s8),
          ...lines.take(12).map((l) {
            final m = (l as Map).cast<String, dynamic>();
            final name = (m['name'] ?? '').toString();
            final qty = (m['qty'] as num?)?.toDouble() ?? 0;
            final unit = (m['unit'] ?? '').toString();
            final qtyStr = qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ', style: AppUI.bodySoft),
                Expanded(child: Text(name, style: AppUI.bodyStrong.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (qty > 0) Text('$qtyStr ${unit.isNotEmpty ? unit : ''}'.trim(), style: AppUI.bodySoft.copyWith(fontSize: 13)),
              ]),
            );
          }),
          if (lines.length > 12)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('y ${lines.length - 12} más…', style: AppUI.bodySoft.copyWith(fontSize: 12))),
        ],
        const SizedBox(height: AppUI.s8),
        // Acción PRINCIPAL de ancho completo (antes se recortaba al meterla en un
        // Row junto a Reenviar+Cancelar en 360dp → desaparecía). Spec 078.
        if (status != 'comprado' && status != 'cancelado') ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: Key('done_$id'),
              onPressed: () => _markBought(e),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(Icons.inventory_2_rounded, size: 18),
              label: const Text('Registrar compra'),
            ),
          ),
          const SizedBox(height: 2),
        ],
        Row(children: [
          TextButton.icon(
            key: Key('resend_$id'),
            onPressed: () => _resend(e),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Reenviar'),
          ),
          const Spacer(),
          if (status != 'comprado' && status != 'cancelado')
            TextButton(
              key: Key('cancel_$id'),
              onPressed: () => _setStatus(id, 'cancelado'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: const Text('Cancelar'),
            ),
        ]),
      ]),
    );
  }

  Widget _statusBadge(String s) {
    final color = s == 'comprado'
        ? AppTheme.success
        : s == 'cancelado'
            ? AppTheme.error
            : s == 'enviado'
                ? AppTheme.primary
                : AppTheme.warning;
    return MinimalBadge(label: s, color: color);
  }
}

/// Banner que deja CLARO que el registro de entrada de inventario se hace aquí:
/// al tocar "Ya compré" en un pedido, lo comprado entra al inventario. Spec 078.
class _IngresoHint extends StatelessWidget {
  const _IngresoHint();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, 0),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
      ),
      child: const Row(children: [
        Icon(Icons.inventory_2_rounded, size: 18, color: AppTheme.success),
        SizedBox(width: AppUI.s8),
        Expanded(
          child: Text(
            'Cuando tenga lo que compró, toque «Ya compré» en el pedido. Eso ingresa los productos a su inventario.',
            style: AppUI.bodySoft,
          ),
        ),
      ]),
    );
  }
}

/// "¿Cuánto compró?" — por cada línea, la cantidad realmente comprada (default =
/// la pedida). Lo que se reduzca queda pendiente. Devuelve [{line_id, received_qty}].
class _WhatBoughtSheet extends StatefulWidget {
  const _WhatBoughtSheet({required this.errand, required this.api});
  final Map<String, dynamic> errand;
  final ApiService api;
  @override
  State<_WhatBoughtSheet> createState() => _WhatBoughtSheetState();
}

class _WhatBoughtSheetState extends State<_WhatBoughtSheet> {
  late final List<Map<String, dynamic>> _raw;
  late final List<TextEditingController> _ctrls;
  bool _scanning = false;

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  String _norm(String s) => s.toLowerCase().trim();

  /// Foto de la factura (propia o la que llegó por WhatsApp): OCR Gemini lee los
  /// productos y AUTO-LLENA las cantidades por nombre. El tendero revisa y ajusta
  /// antes de ingresar (no se confía ciego). Spec 078.
  Future<void> _scanFactura() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded),
            title: const Text('Tomar foto de la factura'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Elegir de la galería (ej. WhatsApp)'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (picked == null || !mounted) return;
    setState(() => _scanning = true);
    try {
      final data = await widget.api.scanInvoiceXFile(picked);
      final products = (data['products'] as List?) ?? (data['items'] as List?) ?? [];
      var matched = 0;
      for (final p in products) {
        final pm = (p as Map).cast<String, dynamic>();
        final pname = _norm((pm['name'] ?? '').toString());
        final qty = (pm['quantity'] as num?)?.toDouble() ?? (pm['qty'] as num?)?.toDouble() ?? 0;
        if (pname.isEmpty || qty <= 0) continue;
        for (var i = 0; i < _raw.length; i++) {
          final ln = _norm((_raw[i]['name'] ?? '').toString());
          if (ln.isEmpty) continue;
          if (ln == pname || ln.contains(pname) || pname.contains(ln)) {
            final full = (_raw[i]['qty'] as num?)?.toDouble() ?? 0;
            _ctrls[i].text = _fmt(qty > full ? full : qty);
            matched++;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(matched > 0
            ? 'Factura leída: $matched producto(s) reconocido(s). Revise y ajuste.'
            : 'No reconocimos productos en la factura. Ajuste manualmente.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo leer la factura. Intente de nuevo.')));
    }
  }

  @override
  void initState() {
    super.initState();
    _raw = ((widget.errand['lines'] as List?) ?? []).map((l) => (l as Map).cast<String, dynamic>()).toList();
    _ctrls = _raw.map((m) => TextEditingController(text: _fmt((m['qty'] as num?)?.toDouble() ?? 0))).toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _all() {
    setState(() {
      for (var i = 0; i < _raw.length; i++) {
        _ctrls[i].text = _fmt((_raw[i]['qty'] as num?)?.toDouble() ?? 0);
      }
    });
  }

  void _confirm() {
    final lines = <Map<String, dynamic>>[];
    for (var i = 0; i < _raw.length; i++) {
      final id = (_raw[i]['id'] ?? '').toString();
      final full = (_raw[i]['qty'] as num?)?.toDouble() ?? 0;
      var got = double.tryParse(_ctrls[i].text.replaceAll(',', '.')) ?? full;
      if (got < 0) got = 0;
      if (got > full) got = full;
      if (id.isNotEmpty) lines.add({'line_id': id, 'received_qty': got});
    }
    Navigator.pop(context, lines);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, MediaQuery.of(context).viewInsets.bottom + AppUI.s16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppUI.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: AppUI.s16),
          const Text('¿Cuánto compró?', style: AppUI.title),
          const SizedBox(height: 2),
          const Text('Lo que marque entra al inventario. Lo que faltó queda pendiente.', style: AppUI.bodySoft),
          const SizedBox(height: AppUI.s12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('scan_factura'),
              onPressed: _scanning ? null : _scanFactura,
              icon: _scanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.receipt_long_rounded, size: 18),
              label: Text(_scanning ? 'Leyendo factura…' : 'Foto de la factura'),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('bought_all'),
              onPressed: _all,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Compré todo'),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _raw.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
              itemBuilder: (_, i) {
                final unit = (_raw[i]['unit'] ?? '').toString();
                return Row(children: [
                  Expanded(child: Text((_raw[i]['name'] ?? '').toString(), style: AppUI.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  // "Faltó": no lo consiguió → cantidad 0 → queda pendiente (re-comprar).
                  TextButton(
                    key: Key('missing_${_raw[i]['id']}'),
                    onPressed: () => setState(() => _ctrls[i].text = '0'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppTheme.error,
                    ),
                    child: const Text('Faltó'),
                  ),
                  SizedBox(
                    width: 54,
                    child: TextField(
                      key: Key('qty_${_raw[i]['id']}'),
                      controller: _ctrls[i],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                    ),
                  ),
                  if (unit.isNotEmpty) ...[const SizedBox(width: 4), Text(unit, style: AppUI.bodySoft.copyWith(fontSize: 12))],
                ]);
              },
            ),
          ),
          const SizedBox(height: AppUI.s12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('confirm_bought'),
              onPressed: _confirm,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Ingresar al inventario'),
            ),
          ),
        ]),
      ),
    );
  }
}
