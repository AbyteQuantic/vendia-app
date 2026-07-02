import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../database/collections/local_product.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../promotions/promo_builder_screen.dart';

/// Marketing Hub — lista de promociones reales del tenant + link
/// público del catálogo y acciones de compartir (WhatsApp / share
/// nativo).
///
/// Antes de este refactor la pantalla mostraba 3 ofertas quemadas
/// (Perro Caliente, Hamburguesa, Jugo). Ahora consume:
///   * `GET /api/v1/store/slug` — enlace público del catálogo
///     (se autogenera en el backend la primera vez).
///   * `GET /api/v1/promotions` — promociones del tenant (con items
///     preloaded, ya filtradas por `is_active=true`).
///
/// Exposed as a StatefulWidget con un [ApiService] opcional para que
/// los widget tests puedan inyectar un fake sin montar todo el grafo
/// de Auth/Dio.
class PromoManagementScreen extends StatefulWidget {
  /// Inyectable solo en tests. En runtime se construye un [ApiService]
  /// a partir del [AuthService] por defecto.
  final ApiService? apiService;

  /// Loader opcional de productos próximos a vencer. En tests se
  /// inyecta para no depender del endpoint real. Devuelve la lista de
  /// filas tal como las entrega `ApiService.fetchExpiringProducts`
  /// (shape: `[{id|uuid, ...}]`).
  final Future<List<Map<String, dynamic>>> Function()? expiringLoader;

  /// Loader opcional de productos "seed" para precargar el
  /// `PromoBuilderScreen`. En tests se inyecta para no tocar Isar.
  final Future<List<LocalProduct>> Function(List<Map<String, dynamic>> rows)?
      seedProductsLoader;

  const PromoManagementScreen({
    super.key,
    this.apiService,
    this.expiringLoader,
    this.seedProductsLoader,
  });

  @override
  State<PromoManagementScreen> createState() => _PromoManagementScreenState();
}

/// View model de una promoción ya lista para pintar. Se construye a
/// partir del JSON del backend (que puede venir en dos shapes:
/// combo moderno con items[] o single-product legacy) — ambos casos
/// terminan en la misma representación plana.
class _PromoVM {
  final String id;
  final String title;
  final String subtitle; // items compactados o descripción
  final double totalPromo;
  final double totalRegular;
  final String emoji;

  const _PromoVM({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.totalPromo,
    required this.totalRegular,
    required this.emoji,
  });

  factory _PromoVM.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List?;
    final items = itemsRaw
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    // Combo → sumar items; legacy → usar orig_price/promo_price.
    double totalRegular = 0;
    double totalPromo = 0;
    final parts = <String>[];

    if (items.isNotEmpty) {
      for (final it in items) {
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        final promoPrice = (it['promo_price'] as num?)?.toDouble() ?? 0;
        totalPromo += promoPrice * qty;
        final name = (it['name'] ?? it['product_name'] ?? 'Producto') as String;
        parts.add(qty > 1 ? '$qty× $name' : name);
      }
      totalRegular = (json['total_regular'] as num?)?.toDouble() ?? totalPromo;
    } else {
      totalRegular = (json['orig_price'] as num?)?.toDouble() ?? 0;
      totalPromo = (json['promo_price'] as num?)?.toDouble() ?? 0;
      final legacyName = (json['product_name'] as String?) ?? '';
      if (legacyName.isNotEmpty) parts.add(legacyName);
    }

    final title = (json['name'] as String?)?.trim().isNotEmpty == true
        ? json['name'] as String
        : (parts.isNotEmpty ? parts.first : 'Combo');

    final subtitle = parts.isEmpty
        ? ((json['description'] as String?) ?? '')
        : parts.join(' + ');

    return _PromoVM(
      id: (json['id'] ?? json['uuid'] ?? '') as String,
      title: title,
      subtitle: subtitle,
      totalPromo: totalPromo,
      totalRegular: totalRegular,
      // Sin emoji real, mostramos un megáfono genérico consistente
      // con el icono del Marketing Hub.
      emoji: '📢',
    );
  }
}

class _PromoManagementScreenState extends State<PromoManagementScreen> {
  late final ApiService _api;
  bool _offersVisible = true;

  // Remote state — null significa "aún cargando", empty significa
  // "carga completa, sin resultados". Lo modelamos explícitamente
  // para evitar el flicker "no hay promos" antes del primer frame.
  List<_PromoVM>? _promos;
  Object? _promosError;

  String? _slug;
  String? _publicUrl;
  String? _slugError;

  /// Filas crudas de productos próximos a vencer (como las entrega el
  /// backend). Mantenemos el JSON completo para poder construir
  /// `seedProducts` para el PromoBuilder sin tener que re-consultar.
  /// - `null`  → aún cargando
  /// - `[]`    → carga OK, inventario sano
  /// - `[...]` → hay productos por vencer
  List<Map<String, dynamic>>? _expiring;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService(AuthService());
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadSlug(),
      _loadPromos(),
      _loadExpiring(),
      _loadOffersVisibility(),
    ]);
  }

  Future<void> _loadExpiring() async {
    try {
      final loader = widget.expiringLoader ?? _api.fetchExpiringProducts;
      final list = await loader();
      if (!mounted) return;
      setState(() => _expiring = list);
    } catch (_) {
      // Una tarjeta de sugerencia no debe romper la pantalla: si falla
      // la consulta, simplemente tratamos el inventario como "sano"
      // (no mostramos la alerta naranja).
      if (!mounted) return;
      setState(() => _expiring = const []);
    }
  }

  Future<void> _loadSlug() async {
    try {
      final data = await _api.fetchStoreSlug();
      if (!mounted) return;
      setState(() {
        _slug = data['slug'] as String?;
        _publicUrl = data['public_url'] as String?;
        _slugError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _slugError = _errorMessage(e));
    }
  }

  // Carga el estado real de "Sección de Ofertas visible" del perfil (antes el
  // switch era state local que no persistía).
  Future<void> _loadOffersVisibility() async {
    try {
      final profile = await _api.fetchBusinessProfile();
      if (!mounted) return;
      setState(() => _offersVisible = profile['hide_offers_section'] != true);
    } catch (_) {
      // Si falla, deja el default (visible) — no bloquea la pantalla.
    }
  }

  // Persiste el toggle. Optimista con reversión si el PATCH falla.
  Future<void> _setOffersVisible(bool val) async {
    final prev = _offersVisible;
    setState(() => _offersVisible = val);
    try {
      await _api.updateBusinessProfile({
        'config': {'hide_offers_section': !val},
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _offersVisible = prev); // revierte
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_errorMessage(e)),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  Future<void> _loadPromos() async {
    try {
      final list = await _api.fetchPromotions();
      if (!mounted) return;
      setState(() {
        _promos = list.map(_PromoVM.fromJson).toList();
        _promosError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _promosError = e);
    }
  }

  String _errorMessage(Object e) =>
      e is AppError ? e.message : 'No se pudo conectar al servidor.';

  String _formatNumber(double value) {
    final intVal = value.toInt();
    return intVal.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  // ── Share helpers ───────────────────────────────────────────────────────────

  /// Comparte el link del catálogo (tarjeta superior). Texto
  /// estandarizado para que el mensaje se lea bien en WhatsApp aunque
  /// la URL quede lineada aparte.
  void _shareCatalog() {
    if (_publicUrl == null) return;
    HapticFeedback.lightImpact();
    final text =
        '¡Hola! Haz tus pedidos en mi nueva tienda online aquí: $_publicUrl';
    Share.share(text, subject: 'Catálogo Online');
  }

  /// Copia el link al portapapeles. Disponible aunque no haya
  /// aplicaciones de share instaladas (caso simulador/CI).
  void _copyCatalogLink() {
    if (_publicUrl == null) return;
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _publicUrl!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enlace copiado', style: TextStyle(fontSize: 16)),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Comparte una promoción concreta. Si todavía no cargamos el link
  /// del catálogo, comparte solo el título + precio (degradación
  /// silenciosa en vez de bloquear la acción).
  void _sharePromo(_PromoVM p) {
    HapticFeedback.lightImpact();
    final price = '\$${_formatNumber(p.totalPromo)}';
    final tail =
        _publicUrl != null ? ' Pídela rápido aquí: $_publicUrl' : '';
    final text = '¡Tenemos una súper promo! ${p.title} a solo $price.$tail';
    Share.share(text, subject: p.title);
  }

  // ── Edit slug modal ─────────────────────────────────────────────────────────

  Future<void> _openEditSlugSheet() async {
    if (_slug == null) return;
    HapticFeedback.lightImpact();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _EditSlugSheet(api: _api, initialSlug: _slug!),
    );

    if (result != null && mounted) {
      setState(() {
        _slug = result;
        _publicUrl = _publicUrl?.replaceFirst(
          RegExp(r'/[^/]+$'),
          '/$result',
        );
      });
      // Refresh to get the canonical base_url from the backend.
      _loadSlug();
    }
  }

  // ── PromoBuilder navigation ─────────────────────────────────────────────────

  /// Abre el PromoBuilder sin productos precargados (CTA principal).
  Future<void> _openPromoBuilder() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PromoBuilderScreen(),
      ),
    );
    // Al volver del builder, recargamos para reflejar la promoción
    // recién creada sin que el usuario tenga que hacer pull-to-refresh.
    if (mounted) _loadPromos();
  }

  /// Abre el PromoBuilder precargado con los productos por vencer
  /// (botón "Ver sugerencias" de la tarjeta FEFO).
  Future<void> _openPromoBuilderFromExpiring() async {
    HapticFeedback.lightImpact();
    final rows = _expiring ?? const [];
    final loader = widget.seedProductsLoader ?? _defaultSeedLoader;
    final seeds = await loader(rows);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PromoBuilderScreen(seedProducts: seeds),
      ),
    );
    if (mounted) _loadPromos();
  }

  /// Implementación real del seed loader: cruza los UUIDs recibidos del
  /// backend contra los productos locales de Isar. Mismo patrón que
  /// usa `ExpiringProductsScreen._buildPromoFromList`.
  static Future<List<LocalProduct>> _defaultSeedLoader(
    List<Map<String, dynamic>> rows,
  ) async {
    final db = DatabaseService.instance;
    final all = await db.getAllProducts();
    final byUuid = {for (final p in all) p.uuid: p};
    final seeds = <LocalProduct>[];
    for (final row in rows) {
      final id = row['id'] as String? ?? row['uuid'] as String? ?? '';
      final match = byUuid[id];
      if (match != null) seeds.add(match);
    }
    return seeds;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        title: 'Mis Combos',
        onBack: () => Navigator.of(context).maybePop(),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppUI.s16),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Padding inferior generoso: el FAB extendido (alto
          // 64) más el offset de `centerFloat` (~16) más el
          // safe area inferior nos pisaban la última card.
          // Subimos a 160 con safe-area añadida para que el
          // tile inferior quede holgadamente por encima del
          // botón en cualquier resolución (PO image_125).
          padding: EdgeInsets.fromLTRB(
              AppUI.s16,
              MediaQuery.of(context).padding.top + kToolbarHeight + AppUI.s16,
              AppUI.s16,
              160 + MediaQuery.of(context).padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: AppUI.s4, bottom: AppUI.s16),
                child: Text(
                  'Ofertas visibles en su catálogo web',
                  style: AppUI.bodySoft,
                ),
              ),
              _buildCatalogCard(),
              const SizedBox(height: AppUI.s24),
              _buildVisibilityCard(),
              const SizedBox(height: AppUI.s16),
              _buildSuggestionCard(),
              const SizedBox(height: AppUI.s24),
              _buildPromosSection(),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildCreatePromoFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// CTA principal — botón gigante, brillante, pinneado abajo.
  /// Se mantiene siempre visible (no desaparece con el scroll) para
  /// que el usuario no-técnico sepa cuál es "el botón" de esta vista.
  Widget _buildCreatePromoFab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: FloatingActionButton.extended(
          key: const Key('btn_create_promo'),
          heroTag: 'btn_create_promo',
          onPressed: _openPromoBuilder,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUI.radius),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 22),
          label: const Text(
            'Crear Nuevo Combo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogCard() {
    return SoftCard(
      key: const Key('catalog_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: AppUI.s12),
              const Expanded(
                child: Text('Tu Catálogo Online', style: AppUI.bodyStrong),
              ),
            ],
          ),
          const SizedBox(height: AppUI.s16),
          // URL box — tap para copiar, long-press para editar. Se
          // muestra incluso en error para que el botón "Editar" siga
          // teniendo sentido visual.
          GestureDetector(
            key: const Key('catalog_url_box'),
            onTap: _publicUrl == null ? null : _copyCatalogLink,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppUI.s12, vertical: AppUI.s12),
              decoration: BoxDecoration(
                color: AppUI.pageBg,
                borderRadius: BorderRadius.circular(AppUI.radius),
                border: Border.all(color: AppUI.hairline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: AppUI.s8),
                  Expanded(
                    child: Text(
                      _publicUrl ??
                          (_slugError != null
                              ? 'Sin conexión'
                              : 'Cargando enlace...'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: _publicUrl != null
                            ? AppUI.ink
                            : AppUI.inkSoft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_publicUrl != null)
                    const Icon(Icons.copy_rounded,
                        size: 16, color: AppUI.inkSoft),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUI.s16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const Key('btn_edit_slug'),
                  label: 'Editar Link',
                  icon: Icons.edit_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: _slug == null ? null : _openEditSlugSheet,
                ),
              ),
              const SizedBox(width: AppUI.s12),
              Expanded(
                flex: 2,
                child: AppButton(
                  key: const Key('btn_share_catalog'),
                  label: 'Compartir',
                  icon: Icons.ios_share_rounded,
                  onPressed: _publicUrl == null ? null : _shareCatalog,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityCard() {
    return SoftCard(
      child: Row(
        children: [
          const Expanded(
            child: Text('Sección de Ofertas visible', style: AppUI.bodyStrong),
          ),
          Switch(
            value: _offersVisible,
            onChanged: (val) {
              HapticFeedback.mediumImpact();
              _setOffersVisible(val);
            },
            activeThumbColor: Colors.white,
            activeTrackColor: AppTheme.success,
          ),
        ],
      ),
    );
  }

  /// Tarjeta de sugerencia contextual. Tres estados:
  ///
  ///   * Cargando / expiring desconocido  → no se muestra (evita flicker).
  ///   * Hay N productos por vencer       → alerta naranja (condición A).
  ///   * Inventario sano y cero promos    → tip de IA (condición B).
  ///   * Inventario sano con promos       → no se muestra (no cansar al usuario).
  Widget _buildSuggestionCard() {
    final expiring = _expiring;
    if (expiring == null) return const SizedBox.shrink();

    if (expiring.isNotEmpty) {
      return _SmartSuggestionCard(
        key: const Key('suggestion_expiring'),
        tone: _SuggestionTone.warning,
        icon: Icons.warning_amber_rounded,
        title: 'Productos a punto de vencer',
        body:
            'Tienes ${expiring.length} ${expiring.length == 1 ? "producto" : "productos"} a punto de vencer. '
            '¡Crea un combo rápido con ${expiring.length == 1 ? "él" : "ellos"} para no perder dinero!',
        actionLabel: 'Ver sugerencias',
        onAction: _openPromoBuilderFromExpiring,
      );
    }

    // Inventario sano. Solo recomendamos crear una promo si aún no hay
    // ninguna — si ya las hay, el CTA inferior es suficiente.
    final hasPromos = _promos != null && _promos!.isNotEmpty;
    if (hasPromos) return const SizedBox.shrink();

    return _SmartSuggestionCard(
      key: const Key('suggestion_idea'),
      tone: _SuggestionTone.idea,
      icon: Icons.lightbulb_outline_rounded,
      title: 'Sugerencia de IA',
      body:
          'Revisa qué productos se venden menos y arma un combo para moverlos rápido.',
      actionLabel: 'Crear combo',
      onAction: _openPromoBuilder,
    );
  }

  Widget _buildPromosSection() {
    if (_promos == null && _promosError == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_promosError != null) {
      return _ErrorStateCard(
        message: _errorMessage(_promosError!),
        onRetry: _loadPromos,
      );
    }
    final list = _promos!;
    if (list.isEmpty) {
      return const _EmptyPromosCard();
    }
    return Column(
      key: const Key('promos_list'),
      children: [
        for (final p in list) _buildOfferCard(p),
      ],
    );
  }

  Widget _buildOfferCard(_PromoVM p) {
    return Container(
      key: Key('promo_${p.id}'),
      margin: const EdgeInsets.only(bottom: AppUI.s12),
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: AppUI.card(),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppUI.hairline,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(p.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: AppUI.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  // Permitimos 2 líneas: PO reportó "Coca Cola Y
                  // empanad..." truncado donde había espacio sobrado.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppUI.bodyStrong,
                ),
                if (p.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.subtitle,
                    // 2 líneas también para la composición de
                    // productos de la promo — "Producto + Producto +
                    // 2× Produ…" leía como error visual.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.bodySoft,
                  ),
                ],
                const SizedBox(height: AppUI.s8),
                Row(
                  children: [
                    if (p.totalRegular > p.totalPromo) ...[
                      Text(
                        '\$${_formatNumber(p.totalRegular)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppUI.inkSoft,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: AppUI.inkSoft,
                        ),
                      ),
                      const SizedBox(width: AppUI.s8),
                    ],
                    Text(
                      '\$${_formatNumber(p.totalPromo)}',
                      // Precio destacado en el azul de marca — un rojo se
                      // leería como alerta, y el precio de un combo activo
                      // debe verse positivo, no estresante.
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Compartir ${p.title}',
            child: GestureDetector(
              key: Key('share_${p.id}'),
              onTap: () => _sharePromo(p),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  // WhatsApp: excepción justificada a la paleta — el
                  // verde real de la marca es lo que el tendero reconoce
                  // como "esto comparte por WhatsApp" de un vistazo.
                  color: const Color(0xFF25D366).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.ios_share_rounded,
                    color: Color(0xFF25D366), size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT SLUG BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

/// Modal para editar el slug del catálogo. Hace debounce ligero en
/// el submit (no se valida mientras el usuario tipea — se valida al
/// presionar "Guardar" y se interpreta el 409 del backend como
/// mensaje inline).
class _EditSlugSheet extends StatefulWidget {
  final ApiService api;
  final String initialSlug;

  const _EditSlugSheet({required this.api, required this.initialSlug});

  @override
  State<_EditSlugSheet> createState() => _EditSlugSheetState();
}

class _EditSlugSheetState extends State<_EditSlugSheet> {
  late final TextEditingController _ctrl;
  String? _inlineError;
  bool _saving = false;

  // Mismo contrato que el backend (services.SlugPattern). Si lo
  // cambias allá, actualízalo acá también.
  static final RegExp _slugRe = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialSlug);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _localValidate(String value) {
    final v = value.trim();
    if (v.length < 3) return 'Debe tener al menos 3 caracteres.';
    if (v.length > 48) return 'No puede tener más de 48 caracteres.';
    if (!_slugRe.hasMatch(v)) {
      return 'Solo minúsculas, números y guiones (ej: mi-tienda-123).';
    }
    return null;
  }

  Future<void> _save() async {
    final value = _ctrl.text.trim().toLowerCase();
    final localErr = _localValidate(value);
    if (localErr != null) {
      setState(() => _inlineError = localErr);
      return;
    }
    if (value == widget.initialSlug) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _saving = true;
      _inlineError = null;
    });

    try {
      final data = await widget.api.updateStoreSlug(value);
      if (!mounted) return;
      Navigator.of(context).pop(data['slug'] as String? ?? value);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _inlineError = e.statusCode == 409
            ? 'Este nombre ya está en uso. Pruebe otro.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _inlineError = 'No se pudo guardar. Intente de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Editar enlace de tu tienda', style: AppUI.title),
          const SizedBox(height: 6),
          const Text(
            'Solo minúsculas, números y guiones.',
            style: AppUI.bodySoft,
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('slug_input'),
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
              LengthLimitingTextInputFormatter(48),
            ],
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.link_rounded),
              hintText: 'mi-tienda-123',
              errorText: _inlineError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('btn_save_slug'),
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppUI.radius),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY / ERROR STATES
// ═══════════════════════════════════════════════════════════════════════════════

/// Empty state educativo. Reemplaza el ícono vacío por una mini-guía
/// que explica QUÉ es una promoción en términos del tendero (combo
/// Pan+Leche) y deja a la vista el CTA inferior como siguiente paso.
class _EmptyPromosCard extends StatelessWidget {
  const _EmptyPromosCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      key: const Key('promos_empty'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: AppUI.s12),
              const Expanded(
                child: Text('¿Qué es un combo?', style: AppUI.bodyStrong),
              ),
            ],
          ),
          const SizedBox(height: AppUI.s12),
          const Text(
            'Atrae más clientes a tu catálogo agrupando productos.',
            style: AppUI.bodySoft,
          ),
          const SizedBox(height: AppUI.s12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppUI.s12, vertical: AppUI.s8),
            decoration: BoxDecoration(
              color: AppUI.pageBg,
              borderRadius: BorderRadius.circular(AppUI.radiusSm),
            ),
            child: const Row(
              children: [
                Text('🍞', style: TextStyle(fontSize: 20)),
                SizedBox(width: AppUI.s8),
                Text('+', style: TextStyle(fontSize: 16, color: AppUI.inkSoft)),
                SizedBox(width: AppUI.s8),
                Text('🥛', style: TextStyle(fontSize: 20)),
                SizedBox(width: AppUI.s8),
                Text('=', style: TextStyle(fontSize: 16, color: AppUI.inkSoft)),
                SizedBox(width: AppUI.s8),
                Flexible(
                  child: Text(
                    'Combo Desayuno',
                    style: AppUI.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUI.s12),
          const Text(
            'Usa el botón "Crear Nuevo Combo" de abajo para armar tu primer combo.',
            style: AppUI.bodySoft,
          ),
        ],
      ),
    );
  }
}

class _ErrorStateCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorStateCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('promos_error'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 36),
          const SizedBox(height: AppUI.s8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppUI.ink),
          ),
          const SizedBox(height: AppUI.s8),
          GhostButton(
            icon: Icons.refresh_rounded,
            label: 'Reintentar',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

enum _SuggestionTone { warning, idea }

/// Tarjeta reutilizable para las sugerencias contextuales (FEFO o
/// idea de IA). No hace networking — solo presentación + callback.
class _SmartSuggestionCard extends StatelessWidget {
  final _SuggestionTone tone;
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _SmartSuggestionCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    // Paleta derivada del tono — warning usa el naranja del theme
    // (alerta real: productos por vencer); idea usa el azul de marca
    // (sugerencia neutra/positiva) en vez de un dorado fuera de paleta.
    final accent =
        tone == _SuggestionTone.warning ? AppTheme.warning : AppTheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: AppUI.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppUI.bodyStrong),
                    const SizedBox(height: 4),
                    Text(body, style: AppUI.bodySoft),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppUI.s12),
          Align(
            alignment: Alignment.centerRight,
            child: GhostButton(
              key: Key(
                tone == _SuggestionTone.warning
                    ? 'btn_suggestion_expiring'
                    : 'btn_suggestion_idea',
              ),
              icon: Icons.arrow_forward_rounded,
              label: actionLabel,
              color: accent,
              onPressed: onAction,
            ),
          ),
        ],
      ),
    );
  }
}
