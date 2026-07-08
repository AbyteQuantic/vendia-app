import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../database/collections/pending_operation.dart';
import '../../database/database_service.dart';
import '../../database/sync/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_normalize.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/image_normalizer.dart' show ImageNormalizationException;
import '../../utils/barcode_validator.dart';
import '../../utils/currency_input.dart';
import '../../widgets/ai_instruction_dialog.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/catalog_photo_suggestion.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/product_image.dart';
import '../../widgets/branch_aware_reload.dart';
import '../../widgets/negative_stock_banner.dart';
import '../../widgets/picked_image_preview.dart';
import '../../widgets/stock_badge.dart';
import '../../widgets/advanced_product_options.dart';
import '../../widgets/product_media_editor.dart';
import '../../widgets/variant_group_link_tile.dart';
import '../pos/scan_screen.dart';
import 'kardex_screen.dart';
import 'negative_stock_screen.dart';
import 'product_import_screen.dart';
import 'organize_categories_screen.dart';
import 'product_save_flow.dart';
import 'photo_completion_screen.dart';
import '../legal/photo_rights_notice.dart';

const kSinCategoria = 'Sin categoría';

/// Auditoría 2026-07-02: Mi Inventario era una lista plana sin ninguna ayuda
/// de navegación — con decenas/cientos de referencias, encontrar un
/// producto a simple vista (sin usar el buscador) exigía scroll a ciegas.
/// Agrupar por categoría (el campo ya existe en cada producto) acota el
/// barrido visual a una sección en vez de todo el catálogo.
///
/// Devuelve una lista mixta: `String` = encabezado de sección,
/// `Map<String,dynamic>` = producto. 'Sin categoría' siempre al final;
/// las demás categorías en orden alfabético. Dentro de cada categoría se
/// preserva el orden de entrada (ya viene alfabético por nombre desde el
/// backend, `Order("name ASC")`).
///
/// Función pura de nivel de archivo (no un método privado del State) para
/// poder testearla sin montar el widget — esta pantalla no tenía ningún
/// test hasta ahora.
List<Object> groupProductsByCategory(List<Map<String, dynamic>> products) {
  final byCategory = <String, List<Map<String, dynamic>>>{};
  for (final p in products) {
    final raw = (p['category'] as String? ?? '').trim();
    final key = raw.isEmpty ? kSinCategoria : raw;
    byCategory.putIfAbsent(key, () => []).add(p);
  }
  final categories = byCategory.keys.toList()
    ..sort((a, b) {
      if (a == kSinCategoria) return 1;
      if (b == kSinCategoria) return -1;
      return a.compareTo(b);
    });
  final result = <Object>[];
  for (final cat in categories) {
    result.add(cat);
    result.addAll(byCategory[cat]!);
  }
  return result;
}

class ManageInventoryScreen extends StatefulWidget {
  const ManageInventoryScreen({super.key, this.focusProductId});

  /// Producto a destacar al abrir (desde una alerta de stock bajo). Hoy
  /// abre el inventario en el módulo correcto; el resaltado por-ítem es
  /// el siguiente paso (Spec 056 slice 1).
  final String? focusProductId;

  @override
  State<ManageInventoryScreen> createState() => _ManageInventoryScreenState();
}

class _ManageInventoryScreenState extends State<ManageInventoryScreen>
    with BranchAwareReload<ManageInventoryScreen> {
  @override
  void onBranchChanged() => _loadProducts(); // recarga al cambiar de sede

  final _searchCtrl = TextEditingController();
  final _api = ApiService(AuthService());
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;
  bool _filterNoSku = false;
  bool _filterNoPrice = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // sellableOnly: el inventario muestra productos reales + platos COMPLETOS
      // (con receta y foto). Los platos incompletos (sin receta) no son productos
      // listos → se gestionan/completan en "Mis recetas" (badge Incompleto), no
      // aquí. Antes salían como "Plato de menú" sin foto y confundían. Spec 078.
      //
      // Auditoría 2026-07-02: esta pantalla pedía UNA sola página
      // (page:1, perPage:100) sin loopear el resto — cualquier sede con
      // más de 100 referencias (ya ocurre en prod, ej. 11.137 productos
      // VTEX importados) quedaba con productos invisibles incluso
      // buscándolos, porque el buscador filtra sobre lo ya cargado
      // (`_applyFilter`), no vuelve a pedir al backend. `fetchAllProducts`
      // recorre todas las páginas (mismo patrón que cart_controller.dart
      // ya aplica para el POS, Spec 088).
      final products = await _api.fetchAllProducts(sellableOnly: true);
      if (!mounted) return;
      setState(() {
        _products = products;
        // PERF: contar SKU/precio faltantes una vez al cargar (no por build).
        _noSkuCount = _products
            .where((p) => (p['barcode'] as String? ?? '').trim().isEmpty)
            .length;
        _noPriceCount = _products
            .where((p) => ((p['price'] as num?)?.toDouble() ?? 0) <= 0)
            .length;
        _noImageCount = _products.where(_isNoImage).length;
        _loading = false;
      });
      _applyFilter();
      // #9 — si venimos de "Agregar referencia" con un producto existente,
      // abrir su edición directamente.
      if (widget.focusProductId != null && widget.focusProductId!.isNotEmpty) {
        final id = widget.focusProductId!;
        final match = _products.where((p) => (p['id'] ?? '').toString() == id);
        if (match.isNotEmpty) {
          final p = match.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _editProduct(p);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar inventario';
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      var list = _products.where((p) {
        if (query.isNotEmpty) {
          final name = (p['name'] as String? ?? '').toLowerCase();
          final barcode = (p['barcode'] as String? ?? '').toLowerCase();
          if (!name.contains(query) && !barcode.contains(query)) return false;
        }
        if (_filterNoSku) {
          final barcode = (p['barcode'] as String? ?? '').trim();
          if (barcode.isNotEmpty) return false;
        }
        if (_filterNoPrice) {
          final price = (p['price'] as num?)?.toDouble() ?? 0;
          if (price > 0) return false;
        }
        return true;
      });
      _filtered = list.toList();
    });
  }

  List<Object> get _groupedFiltered => groupProductsByCategory(_filtered);

  int _noSkuCount = 0;
  int _noPriceCount = 0;
  int _noImageCount = 0;

  /// Un producto está "sin imagen" si no tiene ni photo_url ni image_url —
  /// misma lógica que `imgSrc` del tile de la lista (Spec 097).
  bool _isNoImage(Map<String, dynamic> p) {
    final photo = (p['photo_url'] as String? ?? '').trim();
    final image = (p['image_url'] as String? ?? '').trim();
    return photo.isEmpty && image.isEmpty;
  }

  /// Abre el flujo de "Completar fotos" con las referencias sin imagen de la
  /// sede activa; al volver, recarga para reflejar las fotos asignadas.
  Future<void> _openPhotoCompletion() async {
    final pending = _products.where(_isNoImage).toList();
    if (pending.isEmpty) return;
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhotoCompletionScreen(products: pending),
    ));
    if (mounted) _loadProducts();
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final name = product['name'] as String? ?? 'Producto';
    final id = product['id'] as String? ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar producto',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        content: Text(
          '¿Seguro que desea eliminar "$name"?\nEsta acción no se puede deshacer.',
          style: const TextStyle(fontSize: 18, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar',
                style: TextStyle(fontSize: 18, color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.deleteProduct(id);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('"$name" eliminado',
                  style: const TextStyle(fontSize: 16)),
            ),
          ]),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _loadProducts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al eliminar producto',
              style: TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EditProductSheet(product: product),
      ),
    );
    if (result == true) {
      _loadProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Mi inventario', style: AppUI.title),
        // T-16 (F027): botón de importación. El AppBar no tenía acciones
        // previas → se agrega directamente (regla UI_RULES.md: máx 2 acciones).
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
          IconButton(
            icon: const Icon(Icons.category_rounded,
                color: AppTheme.textPrimary, size: 24),
            tooltip: 'Organizar categorías (IA)',
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const OrganizeCategoriesScreen()),
              );
              if (changed == true && mounted) _loadProducts();
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded,
                color: AppTheme.textPrimary, size: 26),
            tooltip: 'Importar inventario',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProductImportScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Negative-stock alert (P0): renders only when at least one
            // product has reservedStock > stock — the merchant taps the
            // banner to jump to the regularization screen.
            NegativeStockBanner(
              key: const Key('manage_inventory_negative_stock_banner'),
              count: 0,
              countStream: DatabaseService.instance.watchNegativeStockCount(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NegativeStockScreen(),
                  ),
                );
              },
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código...',
                  hintStyle:
                      const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 26, color: AppTheme.textSecondary),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 24),
                          onPressed: () {
                            _searchCtrl.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppUI.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppUI.border),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),

            // Count + Filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} producto${_filtered.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (_noPriceCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: _filterNoPrice,
                        label: Text(
                          'Sin precio ($_noPriceCount)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _filterNoPrice ? Colors.white : AppTheme.error,
                          ),
                        ),
                        avatar: Icon(
                          Icons.money_off_rounded,
                          size: 16,
                          color: _filterNoPrice ? Colors.white : AppTheme.error,
                        ),
                        selectedColor: AppTheme.error,
                        backgroundColor: AppTheme.error.withValues(alpha: 0.1),
                        side: BorderSide(
                          color: AppTheme.error.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onSelected: (v) {
                          HapticFeedback.lightImpact();
                          _filterNoPrice = v;
                          _applyFilter();
                        },
                      ),
                    ),
                  if (_noSkuCount > 0)
                    FilterChip(
                      selected: _filterNoSku,
                      label: Text(
                        'Sin SKU ($_noSkuCount)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _filterNoSku ? Colors.white : AppTheme.warning,
                        ),
                      ),
                      avatar: Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: _filterNoSku ? Colors.white : AppTheme.warning,
                      ),
                      selectedColor: AppTheme.warning,
                      backgroundColor: AppTheme.warning.withValues(alpha: 0.1),
                      side: BorderSide(
                        color: AppTheme.warning.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onSelected: (v) {
                        HapticFeedback.lightImpact();
                        _filterNoSku = v;
                        _applyFilter();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Spec 097 — un único acceso al flujo dedicado "Completar fotos"
            // (sugerencias del catálogo + IA/cargar/foto/recortar). Abre una
            // VISTA APARTE que lista las referencias sin imagen; no filtra el
            // inventario (eso confundía: "las filtra pero no abre la vista").
            if (_noImageCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openPhotoCompletion,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 20),
                    label: Text('Completar fotos ($_noImageCount sin imagen)',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),

            // Spec 071 — el acceso al catálogo en línea se movió al hub
            // "Agregar mercancía" (vista de entrada, más visible).

            // Product list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 48, color: AppTheme.textSecondary),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      color: AppTheme.textSecondary)),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _loadProducts,
                                child: const Text('Reintentar',
                                    style: TextStyle(fontSize: 18)),
                              ),
                            ],
                          ),
                        )
                      : _filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inventory_2_outlined,
                                      size: 56,
                                      color: AppTheme.textSecondary),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchCtrl.text.isNotEmpty
                                        ? 'No se encontraron productos'
                                        : 'Inventario vacío',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadProducts,
                              child: ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(
                                    20, 0, 20, 20),
                                itemCount: _groupedFiltered.length,
                                itemBuilder: (context, index) {
                                  final item = _groupedFiltered[index];
                                  if (item is String) {
                                    return _CategoryHeader(
                                      label: item,
                                      topPadding: index == 0 ? 0 : 20,
                                    );
                                  }
                                  final p = item as Map<String, dynamic>;
                                  return _ProductTile(
                                    product: p,
                                    onEdit: () => _editProduct(p),
                                    onDelete: () => _deleteProduct(p),
                                    onHistory: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => KardexScreen(
                                          productId: p['id'] as String? ?? '',
                                          productName: p['name'] as String? ?? '',
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Encabezado de sección por categoría — acota el barrido visual a un
/// grupo en vez de todo el catálogo (auditoría 2026-07-02).
class _CategoryHeader extends StatelessWidget {
  final String label;
  final double topPadding;

  const _CategoryHeader({required this.label, required this.topPadding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, topPadding, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: AppUI.sectionLabel,
      ),
    );
  }
}

// ── Product tile ─────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onHistory;

  const _ProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
    this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? 'Sin nombre';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final stock = product['stock'] as int? ?? 0;
    final isMenuItem = product['is_menu_item'] == true;
    final byPortions = product['availability_mode'] == 'por_porciones';
    final photoUrl = product['photo_url'] as String?;
    final imageUrl = product['image_url'] as String?;
    final imgSrc = (photoUrl != null && photoUrl.isNotEmpty)
        ? photoUrl
        : imageUrl;
    final barcode = product['barcode'] as String? ?? '';
    final presentation = product['presentation'] as String? ?? '';
    final content = product['content'] as String? ?? '';
    final subtitleParts = <String>[
      if (barcode.isNotEmpty) 'SKU: $barcode',
      if (presentation.isNotEmpty || content.isNotEmpty)
        [presentation, content].where((s) => s.isNotEmpty).join(' · '),
    ];
    final subtitle = subtitleParts.join(' | ');

    return Dismissible(
      key: ValueKey(product['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        onDelete();
        return false; // dialog handles deletion
      },
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onEdit();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: AppUI.card(r: 10),
          child: Row(
            children: [
              // Product image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 60,
                  height: 60,
                  color: Colors.white,
                  // Spec 090: caché en disco del thumbnail (listado de inventario).
                  child: ProductImage(
                    url: imgSrc,
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    placeholder: const Center(
                        child: Icon(Icons.inventory_2_outlined,
                            size: 28, color: AppTheme.textSecondary)),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppUI.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppUI.bodySoft),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _formatPrice(price),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 12),
                        StockBadge(stock: stock, size: StockBadgeSize.medium, isMenuItem: isMenuItem, byPortions: byPortions),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded,
                        size: 20, color: AppUI.inkSoft),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onEdit();
                    },
                    tooltip: 'Editar',
                  ),
                  if (onHistory != null)
                    IconButton(
                      icon: const Icon(Icons.history_rounded,
                          size: 20, color: AppUI.inkSoft),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onHistory!();
                      },
                      tooltip: 'Kardex',
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 22, color: AppTheme.error),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onDelete();
                    },
                    tooltip: 'Eliminar',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatPrice(double price) {
    final int cents = price.round();
    final String s = cents.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }
}

// ── Edit product screen ──────────────────────────────────────────────────────

class _EditProductSheet extends StatefulWidget {
  final Map<String, dynamic> product;

  const _EditProductSheet({required this.product});

  @override
  State<_EditProductSheet> createState() => _EditProductSheetState();
}

class _EditProductSheetState extends State<_EditProductSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _minStockCtrl; // Spec 050 — punto de reorden
  late final TextEditingController _contentCtrl;
  late final TextEditingController _skuCtrl;
  // Spec 068 — categoría (autocomplete) + características, igual que crear.
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _characteristicsCtrl;
  List<String> _categorySuggestions = [];
  late String _presentation;
  // Spec 063 — venta solo para mayores de 18.
  bool _isAgeRestricted = false;
  bool _saving = false;
  bool _enhancing = false;
  String? _photoUrl;
  // Spec 013: store the picked XFile (not just its path string) so the
  // preview and upload both work cross-platform — on web `XFile.path` is
  // a blob URL, useless to `dart:io File`.
  XFile? _photoFile;
  String? _skuError;
  /// Código completo y válido sugerido cuando el dígito de control falta o
  /// no cuadra (ver [BarcodeValidator.suggestCorrection]). Se ofrece bajo
  /// el campo; el tendero decide si aplicarlo. `null` = nada que sugerir.
  String? _skuSuggestion;
  // Spec 095 — variantes de producto. Gatea el tile de "vincular a un
  // grupo"; con la capacidad OFF, la pantalla queda idéntica a hoy (AC-01).
  bool _enableProductVariants = false;

  final _presentations = [
    'Botella',
    'Lata',
    'Bolsa',
    'Caja',
    'Frasco',
    'Paquete',
    'Unidad',
    'Otro',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p['name'] as String? ?? '');
    _priceCtrl = TextEditingController(
        text: CurrencyUtils.formatInt(((p['price'] as num?)?.toDouble() ?? 0).toInt()));
    _stockCtrl =
        TextEditingController(text: (p['stock'] as int? ?? 0).toString());
    // Spec 050 — pre-llena el stock mínimo; vacío si es 0 (sin alerta).
    final pMin = (p['min_stock'] as num?)?.toInt() ?? 0;
    _minStockCtrl = TextEditingController(text: pMin > 0 ? '$pMin' : '');
    _contentCtrl =
        TextEditingController(text: p['content'] as String? ?? '');
    _skuCtrl =
        TextEditingController(text: p['barcode'] as String? ?? '');
    // Spec 068 — precarga categoría y características existentes (NO se pierden).
    _categoryCtrl =
        TextEditingController(text: p['category'] as String? ?? '');
    _characteristicsCtrl =
        TextEditingController(text: p['characteristics'] as String? ?? '');
    _loadCategorySuggestions();
    _presentation = p['presentation'] as String? ?? '';
    _isAgeRestricted = p['is_age_restricted'] as bool? ?? false;
    final photo = p['photo_url'] as String?;
    final image = p['image_url'] as String?;
    _photoUrl = (photo != null && photo.isNotEmpty) ? photo : image;
    _loadProductVariantsFlag();
  }

  // Spec 095 — solo consulta la capacidad (round-trip extra) cuando hace
  // falta; el 95% de tenders que no la usan no pagan este costo antes.
  Future<void> _loadProductVariantsFlag() async {
    try {
      final flags = await AuthService().getFeatureFlags();
      if (mounted && flags.enableProductVariants) {
        setState(() => _enableProductVariants = true);
      }
    } catch (_) {/* queda oculto */}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    _contentCtrl.dispose();
    _skuCtrl.dispose();
    _categoryCtrl.dispose();
    _characteristicsCtrl.dispose();
    super.dispose();
  }

  // Spec 068 — categorías ya usadas por el tenant (sugerencias antitypo).
  Future<void> _loadCategorySuggestions() async {
    try {
      final cats = await ApiService(AuthService()).fetchProductCategories();
      if (mounted && cats.isNotEmpty) {
        setState(() => _categorySuggestions = cats);
      }
    } catch (_) {/* sin sugerencias; no rompe el flujo */}
  }

  Future<void> _pickPhoto(ImageSource source) async {
    HapticFeedback.lightImpact();
    // Adenda A (Spec 098): aviso único de derechos antes de subir foto MANUAL.
    await maybeShowPhotoRightsNotice(context);
    if (!mounted) return;
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;
    setState(() {
      _photoFile = photo;
      _photoUrl = null;
    });
    // Upload immediately so "Mejorar foto" becomes available
    await _uploadLocalPhoto();
  }

  Future<void> _uploadLocalPhoto() async {
    final photo = _photoFile;
    if (photo == null) return;
    final id = widget.product['id'] as String? ?? '';
    if (id.isEmpty) return;
    try {
      final api = ApiService(AuthService());
      final result = await api.uploadProductPhoto(id, photo);
      final url = result['photo_url'] as String?;
      if (url != null && mounted) {
        setState(() => _photoUrl = url);
      }
    } on ImageNormalizationException catch (e) {
      // The picked image could not be normalized — tell the merchant in
      // Spanish instead of swallowing the failure (Constitution Art. V).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      // Upload failed (network / backend) — the merchant can still
      // generate a photo from scratch. Surface it instead of staying
      // silent so they know the camera photo did not save.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos subir la foto. Intente de nuevo.'),
          ),
        );
      }
    }
  }

  Future<void> _onAiPhotoTap() async {
    final id = widget.product['id'] as String? ?? '';
    if (id.isEmpty) return;

    // Validate required fields first
    final missingFields = <String>[];
    if (_nameCtrl.text.trim().isEmpty) missingFields.add('Nombre');
    if (_presentation.isEmpty) missingFields.add('Presentación');
    if (_contentCtrl.text.trim().isEmpty) missingFields.add('Contenido (ej: 350ml, 1L)');

    if (missingFields.isNotEmpty) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Para un mejor resultado, complete: ${missingFields.join(", ")}',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF7C3AED),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    final hasExistingPhoto =
        (_photoUrl != null && _photoUrl!.isNotEmpty) || _photoFile != null;

    // If we have a local photo but no URL yet, upload first
    if (_photoFile != null && (_photoUrl == null || _photoUrl!.isEmpty)) {
      await _uploadLocalPhoto();
    }

    final hasUploadedPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;

    if (!hasExistingPhoto && !hasUploadedPhoto) {
      // No photo at all — go straight to generate
      _executeAiPhoto(useExisting: false);
      return;
    }

    if (!mounted) return;
    // Has photo — ask user what they want
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('¿Qué desea hacer?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                    color: Colors.black87)),
            const SizedBox(height: 6),
            Text(
              'Nombre: ${_nameCtrl.text.trim()}\nPresentación: $_presentation · ${_contentCtrl.text.trim()}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            // Spec 096 — sugerencia OPCIONAL de foto verificada de catálogo
            // (Open Food Facts) para el barcode del producto. Nunca
            // reemplaza ni se aplica sola; NO toca las opciones de abajo.
            if (_skuCtrl.text.trim().isNotEmpty)
              CatalogPhotoSuggestion(
                barcode: _skuCtrl.text.trim(),
                onAccept: (url) {
                  Navigator.of(ctx).pop();
                  setState(() => _photoUrl = url);
                },
              ),
            // Spec 094: el tendero elige — quitar fondo (deja el producto igual) o
            // mejorar con IA (limpia/mejora, puede cambiar detalles).
            _AiOptionTile(
              icon: Icons.auto_fix_high_rounded,
              color: const Color(0xFF3B82F6),
              title: 'Quitar fondo',
              subtitle: 'Deja su producto igual sobre fondo blanco de estudio',
              onTap: () {
                Navigator.of(ctx).pop();
                _executeAiPhoto(useExisting: true);
              },
            ),
            const SizedBox(height: 12),
            _AiOptionTile(
              icon: Icons.auto_awesome_rounded,
              color: const Color(0xFF0E7490),
              title: 'Mejorar con IA',
              subtitle: 'Limpia y mejora el producto (puede cambiar detalles)',
              onTap: () {
                Navigator.of(ctx).pop();
                _executeAiPhoto(useExisting: true, mode: 'improve');
              },
            ),
            const SizedBox(height: 12),
            _AiOptionTile(
              icon: Icons.add_photo_alternate_rounded,
              color: const Color(0xFF7C3AED),
              title: 'Generar imagen nueva',
              subtitle: 'Crea una imagen desde cero basada en el nombre y presentación',
              onTap: () {
                Navigator.of(ctx).pop();
                _executeAiPhoto(useExisting: false);
              },
            ),
            // Spec 017 FR-05: corregir un resultado alterado con indicaciones
            // escritas. Solo si ya hay una foto que mejorar.
            if (_photoUrl != null && _photoUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AiOptionTile(
                icon: Icons.edit_note_rounded,
                color: const Color(0xFF0E6BA8),
                title: 'Corregir con indicaciones',
                subtitle: 'Dígale a la IA qué ajustar (respeta su producto)',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final hint = await showAiInstructionDialog(context);
                  if (hint != null) {
                    _executeAiPhoto(useExisting: true, instruction: hint);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _executeAiPhoto(
      {required bool useExisting, String? instruction, String? mode}) async {
    final id = widget.product['id'] as String? ?? '';
    final currentName = _nameCtrl.text.trim();
    final currentPresentation = _presentation;
    final currentContent = _contentCtrl.text.trim();

    HapticFeedback.lightImpact();
    setState(() => _enhancing = true);
    // Spec 016 / FR-03: the AI photo job runs asynchronously on the
    // backend; ApiService polls its status under the hood. Tell the
    // tendero it is processing so the wait never reads as a failure.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        useExisting
            ? 'Procesando tu foto con IA…'
            : 'Generando la imagen con IA…',
        style: const TextStyle(fontSize: 16),
      ),
      backgroundColor: const Color(0xFF7C3AED),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
    ));
    try {
      final api = ApiService(AuthService());
      final Map<String, dynamic> result;
      if (useExisting) {
        result = await api.enhanceProductPhoto(id,
          name: currentName,
          presentation: currentPresentation,
          content: currentContent,
          instruction: instruction,
          mode: mode,
        );
      } else {
        result = await api.generateProductImage(id,
          name: currentName,
          presentation: currentPresentation,
          content: currentContent,
        );
      }
      final url = (result['photo_url'] ?? result['image_url']) as String?;
      if (url != null && mounted) {
        setState(() {
          _photoUrl = url;
          _photoFile = null;
        });
      }
    } catch (e) {
      if (mounted) {
        // Spec 015 / FR-04: never leak the raw type
        // (AppError(AppErrorType.x): ...) to a tendero 50+. AppError
        // already carries a clean Spanish message; use it.
        final message = e is AppError
            ? e.message
            : 'No pudimos procesar la foto con IA. Intente de nuevo.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _enhancing = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('El nombre es requerido',
              style: TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final id = widget.product['id'] as String? ?? '';
    final payload = <String, dynamic>{
      'name': name,
      'price': CurrencyUtils.parseToDouble(_priceCtrl.text),
      'stock': int.tryParse(_stockCtrl.text.trim()) ?? 0,
      // Spec 050 — punto de reorden. Vacío → 0 (apaga la alerta).
      'min_stock': int.tryParse(_minStockCtrl.text.trim()) ?? 0,
      'presentation': _presentation,
      'content': _contentCtrl.text.trim(),
      'barcode': _skuCtrl.text.trim(),
      // Spec 068 — categoría (con autocomplete) + características.
      'category': canonicalValue(_categoryCtrl.text, _categorySuggestions),
      'characteristics': _characteristicsCtrl.text.trim(),
      // Spec 063 — venta para mayores de 18 (licor, cigarrillos).
      'is_age_restricted': _isAgeRestricted,
    };
    // Capturado ANTES de cualquier await: tras uno, el widget puede haberse
    // desmontado y context.read ya no sería seguro.
    final syncService = context.read<SyncService>();

    setState(() => _saving = true);
    final api = ApiService(AuthService());
    // Auditoría 2026-07-03: antes, si el servidor fallaba Y el tendero ya
    // había navegado a otro producto (muy real editando cientos de
    // referencias con señal intermitente), el cambio se perdía SIN RASTRO
    // — ni error visible, ni guardado, ni cola. Ahora, cualquier fallo
    // encola la actualización en el motor de sync genérico (mismo camino ya
    // usado por fiado/cliente; el backend soporta entity=product
    // action=update con Last-Write-Wins), así que sobrevive a que la
    // pantalla ya no exista.
    final outcome = await persistProductUpdateOfflineFirst(
      serverWrite: () => api.updateProduct(id, payload),
      enqueueRetry: () => syncService.enqueue(PendingOperation()
        ..uuid = id
        ..entity = 'product'
        ..action = 'update'
        ..jsonData = jsonEncode(payload)
        ..clientUpdatedAt = DateTime.now()
        ..retryCount = 0
        ..createdAt = DateTime.now()),
    );

    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _saving = false);
    if (!outcome.serverOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Sin conexión: se guardó y se sincronizará cuando haya señal.',
              style: TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  // (helper widgets below)

  // Ampliar la imagen del producto (la del tendero o la generada por IA).
  void _openImageViewer() {
    final Widget child;
    if (_photoFile != null) {
      child = PickedImagePreview(file: _photoFile!, fit: BoxFit.contain);
    } else if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      child = Image.network(_photoUrl!, fit: BoxFit.contain);
    } else {
      return;
    }
    showFullImageViewer(context, child: child);
  }

  Widget _photoPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo_rounded, size: 32,
            color: AppTheme.primary.withValues(alpha: 0.4)),
        const SizedBox(height: 4),
        Text('Foto', style: TextStyle(fontSize: 12,
            color: AppTheme.textSecondary.withValues(alpha: 0.6))),
      ],
    );
  }

  Widget _photoAction({
    required String label,
    IconData? icon,
    required Color color,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: color, strokeWidth: 2))
            else if (icon != null)
              Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: color)),
            ),
          ],
        ),
      ),
    );
  }

  /// Generates an internal SKU based on the product name and presentation.
  /// Format: VND-{PRES}{3-letter-name}-{random4digits}
  /// e.g. VND-UNI-EMP-4821
  void _generateSku() {
    HapticFeedback.lightImpact();
    final name = _nameCtrl.text.trim().toUpperCase();
    // Presentation prefix (3 chars)
    final presMap = {
      'Botella': 'BOT',
      'Lata': 'LAT',
      'Bolsa': 'BLS',
      'Caja': 'CAJ',
      'Frasco': 'FRA',
      'Paquete': 'PAQ',
      'Unidad': 'UNI',
      'Otro': 'OTR',
    };
    final pres = presMap[_presentation] ?? 'GEN';
    // First 3 consonants/letters of name (skip spaces)
    final letters = name.replaceAll(RegExp(r'[^A-Z]'), '');
    final nameCode = letters.length >= 3 ? letters.substring(0, 3) : letters.padRight(3, 'X');
    // Random 4 digits
    final rng = DateTime.now().millisecondsSinceEpoch % 10000;
    final digits = rng.toString().padLeft(4, '0');

    setState(() {
      _skuCtrl.text = 'VND-$pres-$nameCode-$digits';
      _skuError = null;
    });
  }

  Future<void> _scanSku() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _skuCtrl.text = result;
        _skuError = BarcodeValidator.validate(result);
        _skuSuggestion = BarcodeValidator.suggestCorrection(result);
      });
    }
  }

  /// Aplica la sugerencia de [BarcodeValidator.suggestCorrection]: reemplaza
  /// el SKU por el código completo y válido. Opt-in (el tendero la toca).
  void _applySkuSuggestion() {
    final s = _skuSuggestion;
    if (s == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _skuCtrl.text = s;
      _skuError = BarcodeValidator.validate(s);
      _skuSuggestion = null;
    });
  }

  /// Banda accionable bajo el campo SKU: muestra el código sugerido y lo
  /// aplica al tocarla. Texto según el caso (completar vs. corregir).
  Widget _skuSuggestionHint() {
    final suggestion = _skuSuggestion!;
    final typed = _skuCtrl.text.trim();
    final label = typed.length == 12
        ? 'Le falta el dígito de control. ¿Completar a EAN-13?'
        : 'El dígito de control no coincide. ¿Corregir?';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _applySkuSuggestion,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded,
                    color: Color(0xFF7C3AED), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text(suggestion,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF7C3AED),
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Aplicar',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7C3AED))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _validateSku() {
    HapticFeedback.lightImpact();
    final code = _skuCtrl.text.trim();
    if (code.isEmpty) {
      setState(() {
        _skuError = null;
        _skuSuggestion = null;
      });
      return;
    }
    final error = BarcodeValidator.validate(code);
    setState(() {
      _skuError = error;
      _skuSuggestion = BarcodeValidator.suggestCorrection(code);
    });
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Codigo valido', style: TextStyle(fontSize: 16)),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

    @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Spec 071 — densidad SaaS.
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Editar producto', style: AppUI.title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Photo + Actions ─────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    // Con imagen → ampliar (zoom); sin imagen → tomar foto.
                    onTap: (_photoFile != null ||
                            (_photoUrl != null && _photoUrl!.isNotEmpty))
                        ? _openImageViewer
                        : () => _pickPhoto(ImageSource.camera),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGrey,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _photoFile != null
                            ? PickedImagePreview(
                                file: _photoFile!,
                                width: 110,
                                height: 110,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    _photoPlaceholder())
                            : (_photoUrl != null && _photoUrl!.isNotEmpty)
                                ? Image.network(_photoUrl!,
                                    width: 110, height: 110, fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        _photoPlaceholder())
                                : _photoPlaceholder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _photoAction(
                          label: 'Foto',
                          icon: Icons.camera_alt_rounded,
                          color: AppTheme.primary,
                          onTap: () => _pickPhoto(ImageSource.camera),
                        ),
                        _photoAction(
                          label: 'Galería',
                          icon: Icons.photo_library_rounded,
                          color: AppTheme.success,
                          onTap: () => _pickPhoto(ImageSource.gallery),
                        ),
                        _photoAction(
                          label: _enhancing
                              ? 'Generando...'
                              : 'IA',
                          icon: _enhancing ? null : Icons.auto_awesome_rounded,
                          color: const Color(0xFF7C3AED),
                          loading: _enhancing,
                          onTap: _enhancing ? null : _onAiPhotoTap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // SKU / Barcode
              Row(
                children: [
                  const Text('Codigo SKU / Barras',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const Spacer(),
                  if (_skuCtrl.text.trim().isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Sin SKU',
                          style: TextStyle(fontSize: 11, color: AppTheme.warning, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _skuCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 18),
                onChanged: (v) {
                  // Live validate as user types + ofrecer corrección.
                  final code = v.trim();
                  setState(() {
                    _skuError =
                        code.isEmpty ? null : BarcodeValidator.validate(code);
                    _skuSuggestion = code.isEmpty
                        ? null
                        : BarcodeValidator.suggestCorrection(code);
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Ej: 7702535011119',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                  prefixIcon: const Icon(Icons.qr_code_rounded,
                      color: AppTheme.textSecondary, size: 22),
                  errorText: _skuError,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _scanSku,
                        icon: const Icon(Icons.qr_code_scanner_rounded,
                            color: AppTheme.success, size: 22),
                        tooltip: 'Escanear código',
                      ),
                      IconButton(
                        onPressed: _validateSku,
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            color: AppTheme.primary, size: 22),
                        tooltip: 'Validar código',
                      ),
                      IconButton(
                        onPressed: _generateSku,
                        icon: const Icon(Icons.auto_fix_high_rounded,
                            color: Color(0xFF7C3AED), size: 22),
                        tooltip: 'Generar SKU interno',
                      ),
                    ],
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 14),
                ),
              ),
              if (_skuSuggestion != null) _skuSuggestionHint(),
              const SizedBox(height: 18),

              // Name
              const Text('Nombre',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(fontSize: 18),
                decoration: _inputDecoration('Nombre del producto'),
              ),
              const SizedBox(height: 18),

              // Price & Stock
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Precio venta',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _priceCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [CurrencyInputFormatter()],
                          style: const TextStyle(fontSize: 18),
                          decoration: _inputDecoration('\$ 0'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cantidad',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _stockCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 18),
                          decoration: _inputDecoration('0'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Stock mínimo (Spec 050) — punto de reorden para la alerta.
              const Text('Stock mínimo para avisar (opcional)',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _minStockCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 18),
                decoration:
                    _inputDecoration('Ej: 5 — le avisamos para pedir'),
              ),
              const SizedBox(height: 18),

              // Presentation chips
              const Text('Presentación',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presentations.map((p) {
                  final selected =
                      _presentation.toLowerCase() == p.toLowerCase();
                  return ChoiceChip(
                    label: Text(p, style: const TextStyle(fontSize: 16)),
                    selected: selected,
                    onSelected: (_) {
                      HapticFeedback.lightImpact();
                      setState(() => _presentation = p.toLowerCase());
                    },
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: selected ? AppTheme.primary : AppTheme.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUI.radiusSm),
                      side: BorderSide(
                        color: selected ? AppTheme.primary : AppUI.border,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Content
              const Text('Contenido',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _contentCtrl,
                style: const TextStyle(fontSize: 18),
                decoration: _inputDecoration('ej: 350ml, 500g, 1L'),
              ),
              const SizedBox(height: 18),

              // ── Spec 063 — venta solo para mayores de 18 ─────────────
              SwitchListTile.adaptive(
                key: const Key('product_age_restricted_switch'),
                contentPadding: EdgeInsets.zero,
                value: _isAgeRestricted,
                onChanged: (v) => setState(() => _isAgeRestricted = v),
                secondary: const Icon(Icons.no_adult_content_rounded,
                    color: AppTheme.textSecondary),
                title: const Text(
                  'Solo para mayores de 18',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Licor, cigarrillos. El catálogo pedirá confirmar edad.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 18),
              // Spec 068 — mismas opciones avanzadas que crear: categoría
              // (autocomplete) + características.
              AdvancedProductOptions(
                categoryController: _categoryCtrl,
                characteristicsController: _characteristicsCtrl,
                categorySuggestions: _categorySuggestions,
              ),
              // Spec 095 — vincular este producto a un grupo de variantes
              // (talla/color) ya existente, sin recrearlo.
              if (_enableProductVariants &&
                  (widget.product['id'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                VariantGroupLinkTile(
                  productId: widget.product['id'] as String,
                  currentGroupId: widget.product['variant_group_id'] as String?,
                  onAdopted: () {},
                ),
              ],
              const SizedBox(height: 24),
              // Spec 070 — galería multimedia (fotos extra + video ≤25s + YouTube).
              if ((widget.product['id'] as String? ?? '').isNotEmpty)
                ProductMediaEditor(
                  productId: widget.product['id'] as String,
                  api: ApiService(AuthService()),
                ),
              const SizedBox(height: 32),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _saving ? 'Guardando...' : 'Guardar cambios',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 17, color: AppUI.inkSoft),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppUI.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppUI.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppUI.radiusSm),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}

class _AiOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AiOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 26),
          ],
        ),
      ),
    );
  }
}
