// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../widgets/dispatch_sheet.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../../utils/format_cop.dart';
import '../suppliers/nearby_suppliers_screen.dart';
import '../mandados/mandados_screen.dart';
import '../../widgets/supplier_price_editor.dart';

/// Etiqueta + color del ORIGEN de un precio (Spec 077): el tenant ve de qué
/// mercado viene cada precio y si es estimado.
({String label, Color color}) _sourceBadge(String source, [String supplier = '']) {
  final s = supplier.trim();
  switch (source) {
    case 'vendia_catalog':
      return (label: 'VendIA', color: AppTheme.primary);
    case 'manual':
      return (label: s.isNotEmpty ? s : 'Mi precio', color: AppTheme.success);
    case 'invoice_ocr':
      return (label: s.isNotEmpty ? s : 'Factura', color: AppUI.inkSoft);
    case 'scraped_chain':
      // El nombre de la cadena (Éxito/Olímpica), no un genérico "Cadena".
      return (label: s.isNotEmpty ? s : 'Cadena', color: AppTheme.warning);
    case 'ultima_compra':
      return (label: 'Últ. compra', color: AppTheme.warning);
    case 'ninguno':
    case '':
      return (label: 'Sin precio', color: AppUI.inkSoft);
    default:
      return (label: 'Sin precio', color: AppUI.inkSoft);
  }
}

/// Comprar lo que falta (Spec 077 F1): de los insumos del menú menos el stock,
/// muestra el faltante + precio sugerido (con su origen) + costo estimado, y
/// lleva a comprar con proveedores cercanos o a compartir la lista.
class ShoppingListScreen extends StatefulWidget {
  final List<Map<String, dynamic>> needs; // [{ingredient_id, name, unit, qty}]
  final ApiService? api;
  const ShoppingListScreen({super.key, required this.needs, this.api});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  bool _hasEstimate = false;
  String _disclaimer = '';
  Map<String, dynamic>? _todayErrand; // pedido de hoy con los mismos insumos
  // Opción de proveedor elegida por insumo (cliente): ingredient_id → opción.
  final Map<String, Map<String, dynamic>> _chosen = {};

  /// Valores EFECTIVOS de un ítem: si el tenant eligió un proveedor, mandan los
  /// de la opción; si no, los sugeridos por el backend.
  Map<String, dynamic> _eff(Map<String, dynamic> it) {
    final ch = _chosen[(it['ingredient_id'] ?? '').toString()];
    if (ch == null) return it;
    return {
      ...it,
      'estimated_cost': ch['cost'],
      'packs': ch['packs'],
      'pack_label': ch['label'],
      'pack_unit': ch['pack_unit'],
      'leftover': ch['leftover'],
      'pack_unknown': ch['pack_unknown'],
      'price_source': ch['source'],
      'supplier': ch['supplier'],
    };
  }

  /// Total = suma de los costos EFECTIVOS (refleja las elecciones del tenant).
  double get _displayTotal {
    double t = 0;
    for (final it in _items) {
      t += (_eff(it)['estimated_cost'] as num?)?.toDouble() ?? 0;
    }
    return t;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchShoppingList(widget.needs);
      final items = (data['items'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      if (!mounted) return;
      setState(() {
        _items = items;
        _chosen.clear(); // recálculo desde el backend descarta elecciones viejas
        _hasEstimate = data['has_estimate'] == true;
        _disclaimer = (data['disclaimer'] ?? '').toString();
        _loading = false;
      });
      _loadRepeat();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos calcular la compra.';
        _loading = false;
      });
    }
  }

  /// Abre el selector de destino (Spec 077): compartir con el picker nativo
  /// (WhatsApp/contacto/otra app), enviar a un proveedor/empleado/número, o solo
  /// guardar como mandado. Tras enviar, recarga (refleja el reenviar del día).
  Future<void> _openDispatch() async {
    final sent = await showDispatchSheet(context, _items.map(_eff).toList(), _displayTotal);
    if (sent == true && mounted) _loadRepeat();
  }

  /// "Reenviar pedido del día": busca un mandado de HOY con los mismos insumos.
  Future<void> _loadRepeat() async {
    final ids = _items
        .map((it) => (it['ingredient_id'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    final e = await _api.matchTodayErrand(ids);
    if (mounted) setState(() => _todayErrand = e);
  }

  /// Reenvía el pedido del día con el selector nativo (mismo mensaje).
  Future<void> _resend(Map<String, dynamic> errand) async {
    final lines = (errand['lines'] as List?) ?? [];
    final b = StringBuffer('Buenos días, necesito comprar:\n');
    for (final l in lines) {
      final m = Map<String, dynamic>.from(l as Map);
      final q = (m['qty'] as num?)?.toDouble() ?? 0;
      b.writeln('• ${m['name']} — ${_fmt(q)} ${m['unit']}');
    }
    await Share.share(b.toString(), subject: 'Lista de compra');
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

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
        title: const Text('Comprar lo que falta', style: AppUI.title),
        actions: [
          IconButton(
            key: const Key('btn_open_mandados'),
            tooltip: 'Pendientes de compra',
            icon: const Icon(Icons.fact_check_rounded, color: AppTheme.primary),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MandadosScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(AppUI.s24),
                      child: Text('¡Tiene todo! No le falta ningún insumo para el menú.',
                          textAlign: TextAlign.center, style: AppUI.bodySoft),
                    ))
                  : _body(),
      bottomNavigationBar: _items.isEmpty || _loading ? null : _bottomBar(),
    );
  }

  Widget _body() {
    return ListView(
      key: const Key('shopping_list'),
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, 150),
      children: [
        if (_todayErrand != null) ...[_repeatCard(_todayErrand!), const SizedBox(height: AppUI.s12)],
        // Categoría: estos son INSUMOS del menú (no productos de tienda). Spec 078.
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: AppUI.s8),
          child: Row(children: [
            Text('📦 ', style: TextStyle(fontSize: 15)),
            Expanded(child: Text('Insumos para su menú — se compran para cocinar.', style: AppUI.bodySoft)),
          ]),
        ),
        Container(
          decoration: AppUI.card(r: 10),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (int i = 0; i < _items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppUI.hairline),
              _itemRow(_items[i]),
            ],
          ]),
        ),
        if (_hasEstimate) ...[
          const SizedBox(height: AppUI.s12),
          Container(
            padding: const EdgeInsets.all(AppUI.s12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppUI.radiusSm),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 18),
              const SizedBox(width: AppUI.s8),
              Expanded(child: Text(_disclaimer, style: const TextStyle(fontSize: 12, color: AppUI.ink, height: 1.3))),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _repeatCard(Map<String, dynamic> errand) {
    final who = (errand['assignee_name'] ?? '').toString();
    return Container(
      key: const Key('repeat_order_card'),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.history_rounded, color: AppTheme.primary, size: 22),
        const SizedBox(width: AppUI.s12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ya pidió esto hoy', style: AppUI.bodyStrong),
            Text(who.isNotEmpty ? 'A $who · solo reenvíelo.' : 'Solo reenvíelo.', style: AppUI.bodySoft),
          ]),
        ),
        TextButton(
          key: const Key('btn_resend'),
          onPressed: () => _resend(errand),
          child: const Text('Reenviar'),
        ),
      ]),
    );
  }

  Widget _itemRow(Map<String, dynamic> raw) {
    final it = _eff(raw); // valores efectivos (con la opción elegida si la hay)
    final shortfall = (it['shortfall'] as num?)?.toDouble() ?? 0;
    final cost = (it['estimated_cost'] as num?)?.toDouble() ?? 0;
    final unit = (it['unit'] ?? '').toString();
    final packs = (it['packs'] as num?)?.toInt();
    final packLabel = (it['pack_label'] ?? '').toString();
    final packUnit = (it['pack_unit'] ?? '').toString();
    final leftover = (it['leftover'] as num?)?.toDouble() ?? 0;
    final packUnknown = it['pack_unknown'] == true;
    final supplier = (it['supplier'] ?? '').toString();
    final source = (it['price_source'] ?? '').toString();
    final noPrice = source.isEmpty || source == 'ninguno';
    final src = _sourceBadge(source, supplier);
    // COMPRA REAL: nadie vende fracciones. Si se conoce el empaque, se compra el
    // empaque entero y queda un sobrante reservado; si no, costo aproximado.
    final String calc;
    final String? leftoverNote;
    if (noPrice) {
      // Sin precio real (sin compra previa ni proveedor) — no inventamos un número.
      calc = 'Faltan ${_fmt(shortfall)} $unit · sin precio aún';
      leftoverNote = 'Elija un proveedor o cadena para ver el costo.';
    } else if (packs != null && !packUnknown) {
      final pres = packLabel.isNotEmpty ? packLabel : 'empaque';
      calc = 'Compre $packs ${packs == 1 ? pres : '${pres}s'}';
      leftoverNote = leftover > 0
          ? 'Le sobran ~${_fmt(leftover)} ${packUnit.isNotEmpty ? packUnit : unit} para la próxima (estimado)'
          : null;
    } else {
      calc = 'Faltan ${_fmt(shortfall)} $unit · costo aproximado';
      leftoverNote = 'Sin presentación conocida; confirme con su proveedor.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(it['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppUI.bodyStrong)),
            const SizedBox(width: AppUI.s8),
            // Costo del empaque entero (o "—" si no hay precio real aún).
            Text(noPrice ? '—' : formatCOP(cost),
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: noPrice ? AppUI.inkSoft : AppTheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 3),
          Text(calc, style: AppUI.bodyStrong.copyWith(fontSize: 13)),
          if (leftoverNote != null) ...[
            const SizedBox(height: 1),
            Text(leftoverNote, style: AppUI.bodySoft),
          ],
          const SizedBox(height: 4),
          Row(children: [
            MinimalBadge(label: src.label, color: src.color),
            if (supplier.isNotEmpty && supplier != src.label) ...[
              const SizedBox(width: AppUI.s8),
              Flexible(
                child: Text('· $supplier',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppUI.bodySoft.copyWith(fontSize: 12)),
              ),
            ],
            const Spacer(),
            // Elegir de cuál proveedor/cadena comprar este producto.
            InkWell(
              key: Key('options_${raw['ingredient_id']}'),
              onTap: () => _showOptions(raw),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(_chosen.containsKey((raw['ingredient_id'] ?? '').toString()) ? 'Cambiar' : 'Elegir proveedor',
                    style: const TextStyle(fontSize: 12, color: AppTheme.primary, decoration: TextDecoration.underline)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// Selector de PROVEEDOR por producto: muestra todas las opciones (mis
  /// proveedores + cadenas + última compra), cada una con cuántos empaques
  /// comprar, el costo del empaque entero y el sobrante. El tenant elige y la
  /// fila + el total reflejan esa elección (Spec 077).
  Future<void> _showOptions(Map<String, dynamic> raw) async {
    final id = (raw['ingredient_id'] ?? '').toString();
    final name = raw['name'].toString();
    final unit = (raw['unit'] ?? '').toString();
    final shortfall = (raw['shortfall'] as num?)?.toDouble() ?? 0;

    // Estado del sheet (closure): opciones base, resultados de búsqueda y carga.
    List<Map<String, dynamic>>? baseOpts;
    List<Map<String, dynamic>>? searchResults;
    bool started = false, searching = false;
    String queryText = '';
    Timer? debounce;
    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => StatefulBuilder(
          builder: (ctx, setSheet) {
            // Carga las opciones base una sola vez.
            if (!started) {
              started = true;
              _api
                  .fetchSupplyOptions(ingredientId: id, name: name, unit: unit, shortfall: shortfall)
                  .then((r) {
                baseOpts = r;
                if (ctx.mounted) setSheet(() {});
              }).catchError((_) {
                baseOpts = [];
                if (ctx.mounted) setSheet(() {});
              });
            }

            // Busca en el catálogo + compras previas (con debounce).
            void runSearch(String q) {
              queryText = q;
              debounce?.cancel();
              if (q.trim().length < 2) {
                searchResults = null;
                setSheet(() {});
                return;
              }
              searching = true;
              setSheet(() {});
              debounce = Timer(const Duration(milliseconds: 350), () async {
                try {
                  final r = await _api.fetchSupplySearch(query: q, unit: unit, shortfall: shortfall);
                  searchResults = r;
                } catch (_) {
                  searchResults = [];
                }
                searching = false;
                if (ctx.mounted) setSheet(() {});
              });
            }

            final isSearch = queryText.trim().length >= 2;
            final showing = isSearch ? (searchResults ?? const []) : (baseOpts ?? const []);
            final loadingBase = !isSearch && baseOpts == null;

            return ListView(
              controller: scroll,
              padding: const EdgeInsets.all(AppUI.s16),
              children: [
                Text('$name · de cuál proveedor', style: AppUI.bodyStrong),
                const SizedBox(height: 2),
                const Text('Escoja de dónde lo compra, o busque otro producto para cambiar la sugerencia.',
                    style: AppUI.bodySoft),
                const SizedBox(height: AppUI.s12),
                // Buscador dinámico (catálogo de cadenas + compras previas).
                TextField(
                  key: Key('supply_search_$id'),
                  controller: searchCtrl,
                  onChanged: runSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar otro producto (ej. aguacate hass)',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: queryText.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              searchCtrl.clear();
                              runSearch('');
                            },
                          ),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: AppUI.s12),
                if (loadingBase || searching)
                  const Padding(padding: EdgeInsets.all(AppUI.s24), child: Center(child: CircularProgressIndicator()))
                else if (showing.isEmpty)
                  Text(
                      isSearch
                          ? 'Sin resultados para "$queryText". Pruebe otro nombre o registre el precio de su proveedor.'
                          : 'Aún no hay opciones para este insumo. Busque arriba o registre el precio de su proveedor.',
                      style: AppUI.bodySoft)
                else ...[
                  if (isSearch)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppUI.s8),
                      child: Text('Resultados de la búsqueda', style: AppUI.bodySoft),
                    ),
                  ...showing.map((o) => _optionTile(ctx, id, o)),
                ],
                const SizedBox(height: AppUI.s12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: Key('register_price_$id'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final saved = await showSupplierPriceEditor(context, raw);
                      if (saved == true && mounted) _load();
                    },
                    icon: const Icon(Icons.sell_rounded, size: 18),
                    label: const Text('Registrar mi precio de proveedor'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _optionTile(BuildContext ctx, String ingredientId, Map<String, dynamic> o) {
    final selected = _chosen[ingredientId]?['id'] == o['id'];
    final recommended = o['recommended'] == true;
    final packs = (o['packs'] as num?)?.toInt();
    final cost = (o['cost'] as num?)?.toDouble() ?? 0;
    final leftover = (o['leftover'] as num?)?.toDouble() ?? 0;
    final label = (o['label'] ?? '').toString();
    final supplier = (o['supplier'] ?? '').toString();
    final unknown = o['pack_unknown'] == true;
    final dropped = o['dropped'] == true;
    final src = _sourceBadge((o['source'] ?? '').toString());
    return InkWell(
      key: Key('option_${o['id']}'),
      onTap: () {
        setState(() => _chosen[ingredientId] = o);
        Navigator.pop(ctx);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppUI.s8),
        padding: const EdgeInsets.all(AppUI.s12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppTheme.primary : AppUI.border, width: selected ? 1.5 : 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? AppTheme.primary : AppUI.inkSoft, size: 22),
          const SizedBox(width: AppUI.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(supplier, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppUI.bodyStrong)),
                const SizedBox(width: AppUI.s8),
                MinimalBadge(label: src.label, color: src.color),
                if (recommended) ...[
                  const SizedBox(width: 6),
                  const MinimalBadge(label: 'Recomendado', color: AppTheme.success),
                ],
              ]),
              if (label.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppUI.bodySoft),
              ],
              const SizedBox(height: 2),
              Text(
                unknown
                    ? 'Costo aproximado (sin presentación)'
                    : 'Compre ${packs ?? 1} empaque(s)${leftover > 0 ? ' · sobran ~${_fmt(leftover)}' : ''}',
                style: AppUI.bodySoft.copyWith(fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(width: AppUI.s8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatCOP(cost),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary,
                    fontFeatures: [FontFeature.tabularFigures()])),
            if (dropped) ...[
              const SizedBox(height: 2),
              MinimalBadge(label: 'bajó ${((o['drop_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}%', color: AppTheme.success),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppUI.border)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(child: Text('Total estimado', style: AppUI.bodyStrong)),
            Text(formatCOP(_displayTotal),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: AppUI.s8),
          // Acción primaria única (sin sobreposición): enviar la lista por
          // WhatsApp (abre WhatsApp con el mensaje listo para elegir contacto).
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('btn_send_list'),
              onPressed: _openDispatch,
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Enviar por WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              key: const Key('btn_nearby_from_shopping'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NearbySuppliersScreen())),
              icon: const Icon(Icons.storefront_rounded, size: 18, color: AppTheme.primary),
              label: const Text('Ver proveedores cerca', style: TextStyle(color: AppTheme.primary)),
            ),
          ),
        ]),
      ),
    );
  }
}
