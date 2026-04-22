import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../database/collections/local_product.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
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
        : (parts.isNotEmpty ? parts.first : 'Promoción');

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
    await Future.wait([_loadSlug(), _loadPromos(), _loadExpiring()]);
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
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: _loadAll,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // Padding inferior generoso: el FAB extendido se
                  // superpone al scroll; queremos que la última card
                  // siga siendo visible por encima del botón.
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCatalogCard(),
                      const SizedBox(height: 20),
                      _buildVisibilityCard(),
                      const SizedBox(height: 16),
                      _buildSuggestionCard(),
                      const SizedBox(height: 24),
                      _buildPromosSection(),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 24),
          label: const Text(
            '✨ Crear Nueva Promoción',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        bottom: 28,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFFF6B6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 28),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Mis Promociones',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ofertas visibles en su catálogo web',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogCard() {
    return Container(
      key: const Key('catalog_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C3AED).withValues(alpha: 0.08),
            const Color(0xFF7C3AED).withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Color(0xFF7C3AED), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tu Catálogo Online',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // URL box — tap para copiar, long-press para editar. Se
          // muestra incluso en error para que el botón "Editar" siga
          // teniendo sentido visual.
          GestureDetector(
            key: const Key('catalog_url_box'),
            onTap: _publicUrl == null ? null : _copyCatalogLink,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      size: 20, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _publicUrl ??
                          (_slugError != null
                              ? 'Sin conexión'
                              : 'Cargando enlace...'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: _publicUrl != null
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_publicUrl != null)
                    const Icon(Icons.copy_rounded,
                        size: 18, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('btn_edit_slug'),
                  onPressed: _slug == null ? null : _openEditSlugSheet,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Editar Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Share — CTA secundario más pesado visualmente
              // (gerontodiseño): usa el color primario de la app,
              // icono grande y elevación para que quede obvio que es
              // el botón que manda el catálogo al cliente por
              // WhatsApp/etc.
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  key: const Key('btn_share_catalog'),
                  onPressed: _publicUrl == null ? null : _shareCatalog,
                  icon: const Icon(Icons.ios_share_rounded, size: 22),
                  label: const Text('Compartir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Sección de Ofertas visible',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Transform.scale(
            scale: 1.3,
            child: Switch(
              value: _offersVisible,
              onChanged: (val) {
                HapticFeedback.mediumImpact();
                setState(() => _offersVisible = val);
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppTheme.success,
            ),
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
          'Revisa qué productos se venden menos y arma una promoción para moverlos rápido.',
      actionLabel: 'Crear promoción',
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(p.emoji, style: const TextStyle(fontSize: 30)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (p.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (p.totalRegular > p.totalPromo) ...[
                      Text(
                        '\$${_formatNumber(p.totalRegular)}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '\$${_formatNumber(p.totalPromo)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.error,
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
          const Text(
            'Editar enlace de tu tienda',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Solo minúsculas, números y guiones.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
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
            child: ElevatedButton(
              key: const Key('btn_save_slug'),
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
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
    return Container(
      key: const Key('promos_empty'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.06),
            AppTheme.primary.withValues(alpha: 0.015),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '¿Qué es una promoción?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Atrae más clientes a tu catálogo agrupando productos.',
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Row(
              children: [
                Text('🍞', style: TextStyle(fontSize: 22)),
                SizedBox(width: 6),
                Text('+', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
                SizedBox(width: 6),
                Text('🥛', style: TextStyle(fontSize: 22)),
                SizedBox(width: 10),
                Text('=', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Combo Desayuno',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Usa el botón "Crear Nueva Promoción" de abajo para armar tu primer combo.',
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: Colors.grey.shade700,
            ),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 40),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
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
    // Paleta derivada del tono — warning usa el naranja del theme,
    // idea usa un dorado suave para diferenciarlo sin chocar con el
    // rojo de "error" ni el verde de "success".
    final accent = tone == _SuggestionTone.warning
        ? AppTheme.warning
        : const Color(0xFFB8860B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: Key(
                tone == _SuggestionTone.warning
                    ? 'btn_suggestion_expiring'
                    : 'btn_suggestion_idea',
              ),
              onPressed: onAction,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(actionLabel),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
