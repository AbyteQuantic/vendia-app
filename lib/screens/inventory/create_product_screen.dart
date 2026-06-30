// Spec: specs/018-nuevo-producto-fixes/spec.md
// Spec: specs/029-precios-multi-tier/spec.md
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_catalog_product.dart';
import '../recipes/recipe_studio_screen.dart';
import 'manage_inventory_screen.dart';
import '../../database/collections/local_product.dart';
import '../../database/sync/pending_product_push.dart';
import '../../database/local_product_factory.dart';
import 'product_save_flow.dart';
import '../../services/api_service.dart';
import '../../utils/text_normalize.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/image_normalizer.dart' show ImageNormalizationException;
import '../../theme/app_theme.dart';
import '../../utils/barcode_validator.dart';
import '../../utils/currency_input.dart';
import '../../widgets/ai_instruction_dialog.dart';
import '../../widgets/dashboard_ui_kit.dart';
import '../../theme/app_ui.dart';
import '../../widgets/advanced_product_options.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/picked_image_preview.dart';
import '../pos/scan_screen.dart';

/// Manual product creation form — single-screen, no scroll.
class CreateProductScreen extends StatefulWidget {
  final String? initialSku;
  const CreateProductScreen({super.key, this.initialSku});

  @override
  State<CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends State<CreateProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _nameLayerLink = LayerLink();
  final _buyPriceCtrl = TextEditingController();
  final _sellPriceCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '1');
  // Spec 050 — punto de reorden opcional. Vacío → 0 (sin alerta).
  final _minStockCtrl = TextEditingController();
  final _contentCtrl = TextEditingController(); // e.g. "350ml", "500g"
  OverlayEntry? _overlayEntry;

  // Spec 013: keep the picked XFile (not just a path string) so the
  // preview and upload work on web, where `XFile.path` is a blob URL.
  XFile? _photoFile;
  String? _photoUrl; // from barcode lookup
  String? _pendingUuid; // set after create, before enhance
  String? _pendingCatalogImageId; // set after enhance/generate, sent on save
  List<String> _catalogImages = []; // accepted images from catalog
  // Spec 018 / FR-04: the product name the catalog strip was captured for.
  // Once the typed name diverges from this, the strip is dropped so it can
  // never show photos of an unrelated product (the "Llavero Kitty" -> alien
  // keychains report). Empty when there is no catalog strip.
  String _catalogSourceName = '';
  // Spec 018 / FR-03: true once a suggested/AI/looked-up image is showing
  // (as opposed to a photo the merchant took or picked). Such an image is
  // cleared when the name diverges so it can't stay pinned to an old name.
  bool _imageIsSuggested = false;
  // The product name the suggested image was captured for. When the typed
  // name no longer overlaps this, the suggested image is stale and dropped.
  String _suggestedImageSourceName = '';
  bool _saving = false;
  bool _enhancing = false;
  bool _lookingUp = false;
  bool _dataFromCatalog = false; // shows "datos cargados" indicator
  String _presentation = ''; // botella, lata, bolsa, etc.
  DateTime? _expiryDate; // optional — only perishables carry one
  // Spec 063 — venta solo para mayores de 18 (licor, cigarrillos…).
  bool _isAgeRestricted = false;
  final _skuCtrl = TextEditingController();
  String? _skuError;
  /// Código completo y válido sugerido cuando el dígito de control falta o
  /// no cuadra (ver [BarcodeValidator.suggestCorrection]). Opt-in.
  String? _skuSuggestion;

  // Autocomplete (local Isar + backend catalog)
  List<_ProductSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _searching = false;

  // F029 — precios multi-tier. Cargamos los flags + nombres custom una
  // sola vez en initState. Cuando enable_price_tiers está OFF los 3
  // inputs no se renderizan (AC-01: cero UI nueva para el 95% de los
  // tenders).
  bool _enablePriceTiers = false;
  String _tier1Name = 'Depósito contado';
  String _tier2Name = 'Depósito crédito';
  String _tier3Name = 'Cliente final';
  final _priceTier1Ctrl = TextEditingController();
  final _priceTier2Ctrl = TextEditingController();
  final _priceTier3Ctrl = TextEditingController();

  // Spec 068 — categoría (con autocomplete antitypo) y características.
  final _categoryCtrl = TextEditingController();
  final _characteristicsCtrl = TextEditingController();
  List<String> _categorySuggestions = [];

  static const _presentationOptions = [
    {'value': 'botella', 'label': 'Botella', 'icon': '🍾'},
    {'value': 'lata', 'label': 'Lata', 'icon': '🥫'},
    {'value': 'bolsa', 'label': 'Bolsa', 'icon': '🛍️'},
    {'value': 'caja', 'label': 'Caja', 'icon': '📦'},
    {'value': 'paquete', 'label': 'Paquete', 'icon': '📦'},
    {'value': 'frasco', 'label': 'Frasco', 'icon': '🫙'},
    {'value': 'sobre', 'label': 'Sobre', 'icon': '✉️'},
    {'value': 'unidad', 'label': 'Unidad', 'icon': '🔘'},
  ];

  // Spec 018 / FR-02: stable key on the name field so its context can be
  // scrolled into view above the keyboard via Scrollable.ensureVisible.
  final _nameFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus) {
        // FR-02: al enfocar, el teclado sube y tapa la lista; desplazamos
        // el formulario para que el campo + sugerencias queden visibles.
        _ensureNameFieldVisible();
      }
      // IMPORTANTE: ya NO cerramos las sugerencias al perder el foco. En
      // web (iOS Safari) cualquier toque o arrastre sobre la lista inline
      // hace que el input HTML pierda el foco — si cerráramos aquí, "se
      // cerraría al mover o tocar" la lista (el bug reportado). La lista se
      // cierra solo al SELECCIONAR, al ENVIAR (onFieldSubmitted) o cuando
      // el texto baja de 3 letras. Es inline, así que quedarse abierta no
      // estorba: la siguiente interacción la resuelve.
    });
    // F029: cargar la capacidad enable_price_tiers + los nombres custom
    // de los tiers. Fail-closed: si la red falla o el storage está
    // corrupto, los inputs extra no aparecen (cero UI nueva por accidente).
    _loadPriceTierConfig();
    // Spec 068 — categorías ya usadas por el tenant (sugerencias antitypo).
    _loadCategorySuggestions();
    // Pre-fill SKU if coming from scanner
    if (widget.initialSku != null && widget.initialSku!.isNotEmpty) {
      _skuCtrl.text = widget.initialSku!;
      // Auto-lookup barcode data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _lookupBarcode(widget.initialSku!);
      });
    }
  }

  // F029 — leemos los flags persistidos por AuthService + los nombres
  // custom desde el endpoint del perfil del negocio. Hacemos el round-trip
  // a la red solo cuando el flag está activado para no penalizar a los
  // 95% de tenders que no usan la capacidad.
  Future<void> _loadPriceTierConfig() async {
    try {
      final flags = await AuthService().getFeatureFlags();
      if (!mounted) return;
      if (!flags.enablePriceTiers) {
        // OFF → nada más que hacer; los inputs quedan ocultos.
        setState(() => _enablePriceTiers = false);
        return;
      }
      // ON → vamos por los nombres custom. Tolerante a fallos: si el
      // GET revienta, mantenemos los defaults (que son los mismos del
      // backend, así que el label es consistente).
      String t1 = _tier1Name;
      String t2 = _tier2Name;
      String t3 = _tier3Name;
      try {
        final profile =
            await ApiService(AuthService()).fetchBusinessProfile();
        final raw1 = (profile['price_tier_1_name'] as String?)?.trim();
        final raw2 = (profile['price_tier_2_name'] as String?)?.trim();
        final raw3 = (profile['price_tier_3_name'] as String?)?.trim();
        if (raw1 != null && raw1.isNotEmpty) t1 = raw1;
        if (raw2 != null && raw2.isNotEmpty) t2 = raw2;
        if (raw3 != null && raw3.isNotEmpty) t3 = raw3;
      } catch (_) {
        // Fallback a defaults: el usuario sigue pudiendo guardar
        // valores; los labels se ven en el idioma default.
      }
      if (!mounted) return;
      setState(() {
        _enablePriceTiers = true;
        _tier1Name = t1;
        _tier2Name = t2;
        _tier3Name = t3;
      });
    } catch (_) {
      // Cualquier error inesperado → fail-closed: la UI extra no aparece.
      if (mounted) setState(() => _enablePriceTiers = false);
    }
  }

  // Spec 068 — sugerencias de categoría: endpoint del tenant (primario) con
  // degradación silenciosa a vacío (el campo sigue siendo libre).
  Future<void> _loadCategorySuggestions() async {
    try {
      final cats = await ApiService(AuthService()).fetchProductCategories();
      if (mounted && cats.isNotEmpty) {
        setState(() => _categorySuggestions = cats);
      }
    } catch (_) {/* sin sugerencias; no rompe el flujo */}
  }

  @override
  void dispose() {
    // No pasamos por _removeOverlay() aquí: ahora hace setState (la lista es
    // inline) y setState durante dispose lanza. Limpiamos el entry directo.
    _overlayEntry?.remove();
    _overlayEntry = null;
    _debounce?.cancel();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    _quantityCtrl.dispose();
    _minStockCtrl.dispose();
    _contentCtrl.dispose();
    _skuCtrl.dispose();
    _priceTier1Ctrl.dispose();
    _priceTier2Ctrl.dispose();
    _priceTier3Ctrl.dispose();
    _categoryCtrl.dispose();
    _characteristicsCtrl.dispose();
    super.dispose();
  }

  /// Oculta las sugerencias. (Antes removía un OverlayEntry; ahora la lista
  /// es INLINE en el formulario, así que basta con limpiar el estado.)
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() {});
  }

  /// Muestra/actualiza las sugerencias. Ya NO usa un Overlay: en Flutter web
  /// (iOS Safari) tocar un Overlay dibujado sobre el canvas hacía que el
  /// input HTML perdiera el foco → el teclado bajaba, el Overlay se reubicaba
  /// (CompositedTransformFollower) y el toque caía al vacío: "no me deja
  /// seleccionar / se cierra al mover la lista". La lista inline vive dentro
  /// del propio ListView del formulario, así que tocarla y desplazarla son
  /// gestos normales que nunca la cierran.
  void _showSuggestionsOverlay() {
    if (mounted) setState(() {});
  }

  /// Sugerencias renderizadas INLINE bajo el campo de nombre. Es un Column
  /// (NO un ListView anidado): así cada fila forma parte del scroll del
  /// formulario y se toca/desplaza sin los problemas de hit-test de un
  /// scrollable dentro de otro. Las sugerencias son pocas (≤8), así que no
  /// hace falta virtualizar.
  Widget _inlineSuggestions() {
    final tiles = <Widget>[];
    for (var i = 0; i < _suggestions.length; i++) {
      if (i > 0) {
        tiles.add(const Divider(height: 1, thickness: 1, color: DashUI.divider));
      }
      tiles.add(_suggestionTile(_suggestions[i]));
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x0D000000), width: 1),
        boxShadow: DashUI.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: tiles),
    );
  }

  Widget _suggestionTile(_ProductSuggestion s) {
    final pres = s.presentation ?? '';
    final cont = s.content ?? '';
    final detail =
        [if (pres.isNotEmpty) pres, if (cont.isNotEmpty) cont].join(' - ');
    final subtitleText = detail.isNotEmpty
        ? detail
        : (s.brand.isNotEmpty ? s.brand : 'Sin especificar');

    return InkWell(
      onTap: () => _selectSuggestion(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: Colors.grey.shade100,
                child: s.imageUrl != null && s.imageUrl!.isNotEmpty
                    ? Image.network(s.imageUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _suggestionPlaceholder())
                    : _suggestionPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.brand.isNotEmpty ? '${s.name} (${s.brand})' : s.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: DashUI.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(subtitleText,
                      style: const TextStyle(
                          fontSize: 14, color: DashUI.inkSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (s.source == 'user')
              _sourcePill('VendIA', const Color(0xFF7C3AED))
            else if (s.isLocal)
              _sourcePill('Mi tienda', const Color(0xFF0D8B5E)),
          ],
        ),
      ),
    );
  }

  Widget _sourcePill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _suggestionPlaceholder() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.fastfood_rounded,
          size: 20, color: AppTheme.textSecondary),
    );
  }

  /// Scrolls the form so the name field sits above the keyboard, leaving
  /// room for the suggestion overlay rendered just below it (FR-02).
  ///
  /// Se invoca SOLO al enfocar el campo (una vez), no en cada resultado
  /// de búsqueda. Acoplar este scroll a `_showSuggestionsOverlay` —como
  /// hacía F018— hacía que mostrar las sugerencias dependiera de un
  /// scroll animado que se disparaba en cada tecla; eso es la regresión
  /// que dejó el autocompletado sin funcionar. Cualquier fallo aquí se
  /// registra pero nunca puede impedir que el overlay se pinte.
  void _ensureNameFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final ctx = _nameFieldKey.currentContext;
        if (ctx == null || !mounted) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          // Pull the field toward the top of the viewport so the
          // suggestion list below it does not fall behind the keyboard.
          alignment: 0.05,
        );
      } catch (e) {
        // El ajuste de scroll es cosmético (FR-02). Si falla, se ignora
        // explícitamente —con log, sin `catch` mudo— para no arrastrar
        // el autocompletado.
        debugPrint('CreateProductScreen._ensureNameFieldVisible error: $e');
      }
    });
  }

  /// Drops a suggested/AI/looked-up image and the catalog strip when the
  /// typed name no longer matches what they were captured for (FR-03/04).
  ///
  /// Never touches `_photoFile`: a photo the merchant took or picked is
  /// theirs and always wins (D2). Only suggested imagery is volatile.
  void _dropStaleSuggestedImage(String typedName) {
    if (_photoFile != null) return; // merchant photo — leave it alone

    var changed = false;

    // A suggested URL (catalog/AI/barcode lookup) is pinned to the name it
    // was captured for. Once the typed name diverges from that name, the
    // image is stale and unrelated — clear it so the thumbnail reflects the
    // current product. A small edit ("Kitty" -> "Kitty Rosado") keeps it.
    if (_imageIsSuggested &&
        _photoUrl != null &&
        !CreateProductImagePolicy.catalogStillMatchesName(
          catalogSourceName: _suggestedImageSourceName,
          currentName: typedName,
        )) {
      _photoUrl = null;
      _pendingCatalogImageId = null;
      _imageIsSuggested = false;
      _suggestedImageSourceName = '';
      changed = true;
    }

    // The catalog strip belongs to a specific product name. Once the typed
    // name diverges from it, the strip would show unrelated photos — drop it.
    if (_catalogImages.isNotEmpty &&
        !CreateProductImagePolicy.catalogStillMatchesName(
          catalogSourceName: _catalogSourceName,
          currentName: typedName,
        )) {
      _catalogImages = [];
      _catalogSourceName = '';
      changed = true;
    }

    if (changed) setState(() {});
  }

  // #10 — true cuando el nombre parece un PLATO PREPARABLE (empanada, sopa,
  // almuerzo…). Sugiere registrarlo como receta para controlar insumos.
  bool _suggestRecipe = false;

  static const _preparableHints = [
    'empanada', 'arepa', 'sopa', 'sancocho', 'caldo', 'almuerzo', 'bandeja',
    'plato', 'guiso', 'sudado', 'asado', 'frito', 'seco', 'ensalada', 'jugo',
    'frijol', 'lenteja', 'arroz', 'pasta', 'lasaña', 'pizza', 'hamburguesa',
    'perro', 'salchipapa', 'tamal', 'mondongo', 'ajiaco', 'menú', 'menu',
    'desayuno', 'comida', 'porción', 'porcion', 'combo',
  ];

  bool _looksPreparable(String name) {
    final n = name.toLowerCase();
    return _preparableHints.any((k) => n.contains(k));
  }

  /// #9 — el producto ya existe en la tienda: ofrece editarlo (no duplicar) y
  /// lleva a su edición en el inventario.
  Future<void> _confirmEditExisting(String name, String uuid) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ya tiene este producto'),
        content: Text('«$name» ya está en su inventario. ¿Quiere editarlo en vez de crear otro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Crear otro')),
          ElevatedButton(
            key: const Key('edit_existing_cta'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Editar'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ManageInventoryScreen(focusProductId: uuid)));
    }
  }

  Widget _recipeSuggestionCard() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.restaurant_menu_rounded, color: AppTheme.primary, size: 24),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            '¿Esto lo prepara usted? Regístrelo como RECETA y le controlamos los '
            'insumos y la lista de compras.',
            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.3),
          ),
        ),
        TextButton(
          key: const Key('suggest_recipe_cta'),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecipeStudioScreen())),
          child: const Text('Crear receta'),
        ),
      ]),
    );
  }

  void _onNameChanged(String query) {
    _debounce?.cancel();
    // #10 — pista de "esto lo prepara usted" para sugerir receta.
    final prep = _looksPreparable(query.trim());
    if (prep != _suggestRecipe && mounted) {
      setState(() => _suggestRecipe = prep);
    }
    // FR-03/FR-04: the name now describes a (possibly) different product.
    // Drop any image/catalog data that belonged to an earlier name so the
    // screen never keeps a stale, unrelated photo pinned. A photo the
    // merchant took or picked is never touched — D2, it always wins.
    //
    // Regresión F018 → fix: este descarte de imagen es SECUNDARIO; jamás
    // debe impedir la búsqueda. Se aísla en su propio try/catch para que,
    // si algo falla aquí, el autocompletado siga corriendo igual.
    try {
      _dropStaleSuggestedImage(query);
    } catch (e, st) {
      debugPrint('CreateProductScreen._dropStaleSuggestedImage falló '
          '(se ignora para no romper el autocompletado): $e\n$st');
    }
    if (query.trim().length < 3) {
      _suggestions = [];
      _searching = false;
      _removeOverlay();
      setState(() {});
      return;
    }
    // Instant local search (no debounce, no spinner)
    _searchLocal(query.trim());
    // Backend search with debounce
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchRemote(query.trim());
    });
  }

  void _searchLocal(String query) {
    final db = DatabaseService.instance;

    // Search both: user's products + OFF catalog (both in Isar)
    Future.wait([
      db.getAllProducts(),
      db.searchCatalog(query),
    ]).then((results) {
      if (!mounted) return;
      final lowerQ = query.toLowerCase();
      final userProducts = results[0] as List<LocalProduct>;
      final catalogProducts = results[1] as List<LocalCatalogProduct>;

      final seen = <String>{};
      final matches = <_ProductSuggestion>[];

      // User's own products first
      for (final p in userProducts) {
        if (!p.name.toLowerCase().contains(lowerQ)) continue;
        final key = p.name.toLowerCase();
        if (seen.add(key)) {
          matches.add(_ProductSuggestion(
            name: p.name,
            brand: '',
            imageUrl: p.imageUrl,
            isLocal: true,
            productUuid: p.uuid, // para enrutar a EDITAR este producto propio
          ));
        }
        if (matches.length >= 6) break;
      }

      // Then OFF catalog products
      for (final p in catalogProducts) {
        if (matches.length >= 6) break;
        final key = p.name.toLowerCase();
        if (seen.add(key)) {
          matches.add(_ProductSuggestion(
            name: p.name,
            brand: p.brand,
            imageUrl: p.imageUrl,
          ));
        }
      }

      if (matches.isNotEmpty) {
        _suggestions = matches;
        _showSuggestionsOverlay();
      }
    }).catchError((Object e, StackTrace st) {
      // No silenciar: la búsqueda local es offline-first; si Isar falla
      // queremos verlo en los logs (no un `catchError` mudo). El
      // autocompletado remoto sigue intentándolo aparte.
      debugPrint('CreateProductScreen._searchLocal error: $e\n$st');
    });
  }

  Future<void> _searchRemote(String query) async {
    if (!mounted) return;
    setState(() => _searching = true);
    List<_ProductSuggestion>? merged;
    try {
      final api = ApiService(AuthService());
      final res = await api.searchCatalog(query);
      final products = res['data'] as List? ?? [];
      if (!mounted) return;

      final remoteResults = products
          .map((p) {
            final map = p as Map<String, dynamic>;
            final imagesList = (map['images'] as List?)
                    ?.map((img) =>
                        (img as Map<String, dynamic>)['image_url'] as String? ??
                        '')
                    .where((url) => url.isNotEmpty)
                    .toList() ??
                [];
            return _ProductSuggestion(
              name: map['name'] as String? ?? '',
              brand: map['brand'] as String? ?? '',
              imageUrl: map['image_url'] as String?,
              presentation: map['presentation'] as String?,
              content: map['content'] as String?,
              barcode: map['barcode'] as String?,
              sku: map['sku'] as String?, // SKU normalizado de otra tienda
              source: map['source'] as String? ?? 'off',
              images: imagesList,
            );
          })
          .where((s) => s.name.isNotEmpty)
          .toList();

      // Merge: local first, then remote (deduplicated)
      final seen = <String>{};
      final out = <_ProductSuggestion>[];
      for (final s in [
        ..._suggestions.where((s) => s.isLocal),
        ...remoteResults
      ]) {
        final key = s.name.toLowerCase();
        if (seen.add(key)) out.add(s);
        if (out.length >= 6) break;
      }
      merged = out;
    } on Object catch (e) {
      // El backend falló: se conservan los resultados locales (si los
      // hay). NO se silencia mudo — se registra para diagnóstico.
      // `merged` queda en null, así que el overlay no se vuelve a pintar
      // abajo y el autocompletado local visible se mantiene intacto.
      debugPrint('CreateProductScreen._searchRemote error: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
    // Pintar las sugerencias va FUERA del try del backend a propósito:
    // si construir/insertar el overlay fallara, ese error ya no quedaría
    // atrapado por el catch del backend (la causa de que, tras F018, una
    // falla del overlay se viera como "el autocompletado no funciona").
    if (merged != null && mounted) {
      _suggestions = merged;
      _showSuggestionsOverlay();
    }
  }

  /// Called when the user presses Enter/Done on the name field without
  /// selecting a suggestion. Capitalises the text, closes suggestions and
  /// optionally moves focus away.
  void _confirmNameField({bool unfocus = true}) {
    _debounce?.cancel();
    _removeOverlay();
    _suggestions = [];
    final raw = _nameCtrl.text.trim();
    if (raw.isNotEmpty) {
      // Title Case: capitalise first letter of every word
      _nameCtrl.text = raw
          .split(RegExp(r'\s+'))
          .map((w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join(' ');
      _nameCtrl.selection =
          TextSelection.collapsed(offset: _nameCtrl.text.length);
    }
    setState(() => _searching = false);
    if (unfocus && _nameFocus.hasFocus) {
      _nameFocus.unfocus();
    }
  }

  void _selectSuggestion(_ProductSuggestion s) {
    // #9 — si ya EXISTE en esta tienda (sugerencia local), no duplicar: ofrecer
    // editarlo y llevar a su edición.
    if (s.isLocal && s.productUuid != null && s.productUuid!.isNotEmpty) {
      _removeOverlay();
      setState(() => _suggestions = []);
      _confirmEditExisting(s.name, s.productUuid!);
      return;
    }
    final fullName = s.brand.isNotEmpty ? '${s.name} (${s.brand})' : s.name;
    _nameCtrl.text = fullName;
    _removeOverlay();
    _suggestions = [];

    setState(() {
      // Auto-fill image — D2: only when the merchant has not taken/picked
      // their own photo; their photo always wins over a suggested one.
      if (CreateProductImagePolicy.canApplySuggestedImage(
        hasMerchantPhoto: _photoFile != null,
        suggestedUrl: s.imageUrl,
      )) {
        _photoUrl = s.imageUrl;
        _imageIsSuggested = true;
        _suggestedImageSourceName = fullName;
      }

      // Auto-fill presentation & content
      if (s.presentation != null && s.presentation!.isNotEmpty) {
        _presentation = s.presentation!;
      }
      if (s.content != null && s.content!.isNotEmpty) {
        _contentCtrl.text = s.content!;
      }

      // Auto-fill SKU: si la referencia ya está normalizada en el catálogo
      // (otra tienda) con un SKU válido, ese SKU manda; si no, el código de
      // barras. Así el tenant hereda la referencia normalizada (Spec 077/068).
      final normalizedSku = (s.sku != null && s.sku!.trim().isNotEmpty) ? s.sku!.trim() : null;
      if (normalizedSku != null) {
        _skuCtrl.text = normalizedSku;
      } else if (s.barcode != null && s.barcode!.isNotEmpty) {
        _skuCtrl.text = s.barcode!;
      }

      // Store catalog images for selection, tagged with the name they
      // belong to so a later name change can drop them (FR-04).
      _catalogImages = s.images;
      _catalogSourceName = s.images.isEmpty ? '' : fullName;

      // Show "data loaded" indicator
      _dataFromCatalog = true;
    });

    // Hide indicator after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _dataFromCatalog = false);
    });
  }

  // ── Photo ──────────────────────────────────────────────────────────────────

  Future<void> _takePhoto() => _pickPhoto(ImageSource.camera);

  /// Spec 018 / FR-01: lets the merchant choose a photo from the phone
  /// album. "Editar Producto" already offers this; "Nuevo Producto" must
  /// too, so the merchant can hand the AI a real reference photo.
  Future<void> _pickFromGallery() => _pickPhoto(ImageSource.gallery);

  /// Shared photo picker for camera and gallery. The picked [XFile] is
  /// kept as-is (not a path string) so the preview and the byte-based
  /// upload work on web too — the cross-platform pattern of Spec 013.
  Future<void> _pickPhoto(ImageSource source) async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (photo != null && mounted) {
      setState(() {
        // D2 — a photo the merchant picked always wins: drop any
        // suggested/generated URL and its catalog metadata so the
        // chosen photo is the one that gets saved.
        _photoFile = photo;
        _photoUrl = null;
        _pendingCatalogImageId = null;
        _imageIsSuggested = false;
        _suggestedImageSourceName = '';
      });
    }
  }

  // forceGenerate=true ignora la foto del tendero y crea una desde cero (opción
  // "Crear con IA"); por defecto, si hay foto, la MEJORA ("Mejorar con IA").
  Future<void> _enhanceOrGeneratePhoto(
      {String? instruction, bool forceGenerate = false, bool studio = false}) async {
    // Validate required fields for a good AI result. El precio es obligatorio
    // porque la IA crea primero el producto en el backend (que exige precio) para
    // tener un ID; sin precio fallaba con un error técnico ('Price required').
    final missingFields = <String>[];
    if (_nameCtrl.text.trim().isEmpty) missingFields.add('nombre');
    if (_presentation.isEmpty) missingFields.add('presentación');
    if (_contentCtrl.text.trim().isEmpty) {
      missingFields.add('contenido (ej: 350ml)');
    }
    if (CurrencyUtils.parseToDouble(_sellPriceCtrl.text) <= 0) {
      missingFields.add('precio');
    }

    if (missingFields.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Complete los campos: ${missingFields.join(", ")}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF7C3AED),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final hasExistingPhoto =
        !forceGenerate && _photoUrl != null && _photoUrl!.isNotEmpty;

    HapticFeedback.lightImpact();
    setState(() => _enhancing = true);
    // Spec 016 / FR-03: the AI photo job runs asynchronously on the
    // backend; ApiService polls its status under the hood. Tell the
    // tendero it is processing so the wait never reads as a failure.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        hasExistingPhoto
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

      // Reserve a UUID for the product (in-memory only, NOT saved to DB yet)
      _pendingUuid ??= const Uuid().v4();

      // Create a temporary product in backend ONLY for AI processing
      // This is needed because enhance/generate endpoints require a product ID.
      // The real save happens only when user presses "Guardar".
      //
      // Spec 014: this call no longer swallows its error with a mute
      // `.catchError`. CreateProduct is idempotent on the backend, so a
      // repeated id returns the existing product instead of failing —
      // there is nothing to "ignore". Any genuine error (network,
      // validation, server) now propagates to the catch block below and
      // is shown to the user in Spanish.
      await api.createProduct({
        'id': _pendingUuid,
        'name': _nameCtrl.text.trim().isEmpty
            ? 'Producto temporal'
            : _nameCtrl.text.trim(),
        'price': CurrencyUtils.parseToDouble(_sellPriceCtrl.text),
        'stock': int.tryParse(_quantityCtrl.text.trim()) ?? 1,
        'image_url': _photoUrl,
        'presentation': _presentation,
        'content': _contentCtrl.text.trim(),
        'category': canonicalValue(_categoryCtrl.text, _categorySuggestions),
        'characteristics': _characteristicsCtrl.text.trim(),
        'is_age_restricted': _isAgeRestricted,
      });

      // If product has a photo URL, enhance it. Otherwise, generate from scratch.
      final Map<String, dynamic> result;
      if (hasExistingPhoto) {
        result = await api.enhanceProductPhoto(_pendingUuid!,
            instruction: instruction, mode: studio ? 'studio' : null);
      } else {
        result = await api.generateProductImage(_pendingUuid!);
      }

      final url = (result['photo_url'] ?? result['image_url']) as String?;
      final catalogImgId = result['catalog_image_id'] as String?;
      if (url != null && mounted) {
        setState(() {
          _photoUrl = url;
          _photoFile = null;
          // FR-03: an AI image is generated for the *current* name — mark
          // it suggested and tag it with that name so that, if the merchant
          // later edits the name, the stale render is dropped, not pinned.
          _imageIsSuggested = true;
          _suggestedImageSourceName = _nameCtrl.text.trim();
          if (catalogImgId != null && catalogImgId.isNotEmpty) {
            _pendingCatalogImageId = catalogImgId;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        // Spec 014: this catch now also receives errors from
        // createProduct (the mute `.catchError` was removed). Surface a
        // clean Spanish message — AppError already carries one — instead
        // of leaking the exception type to a tendero 50+.
        final message = e is AppError
            ? e.message
            : 'No pudimos procesar la imagen. Intente de nuevo.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enhancing = false);
    }
  }

  // ── Barcode ────────────────────────────────────────────────────────────────

  Future<void> _scanBarcode() async {
    HapticFeedback.lightImpact();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      await _lookupBarcode(result);
    }
  }

  /// Aplica la sugerencia de [BarcodeValidator.suggestCorrection]:
  /// reemplaza el SKU por el código completo y válido. Opt-in.
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

  /// Banda accionable bajo el campo SKU con el código sugerido.
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

  Future<void> _lookupBarcode(String barcode) async {
    setState(() {
      _lookingUp = true;
      _skuSuggestion = BarcodeValidator.suggestCorrection(barcode);
    });
    // Always fill the SKU field with the scanned barcode
    _skuCtrl.text = barcode;
    try {
      final api = ApiService(AuthService());
      final data = await api.lookupBarcode(barcode);
      if (!mounted) return;
      final name = data['name'] as String?;
      final imageUrl = data['image_url'] as String?;
      if (name != null && name.isNotEmpty) {
        _nameCtrl.text = name;
      }
      setState(() {
        // D2 — only adopt the looked-up image if the merchant has no photo
        // of their own. Tag it as suggested so a later name edit clears it.
        if (CreateProductImagePolicy.canApplySuggestedImage(
          hasMerchantPhoto: _photoFile != null,
          suggestedUrl: imageUrl,
        )) {
          _photoUrl = imageUrl;
          _imageIsSuggested = true;
          // Tie the image to the product name from the lookup so a later
          // name edit can detect when it has gone stale.
          _suggestedImageSourceName =
              (name != null && name.isNotEmpty) ? name : _nameCtrl.text.trim();
        }
      });
    } catch (_) {
      // best effort — user can fill manually
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  // ── Expiry date ────────────────────────────────────────────────────────────

  /// Formats a DateTime as ISO `YYYY-MM-DD` for wire transport (backend
  /// Postgres DATE column + local Isar). Kept as a local helper to avoid
  /// the `intl` dependency for a single-purpose format.
  String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Human-facing display: "31 dic 2026". Adults 50+ audience — the full
  /// abbreviation beats a numeric DD/MM/YY that people mis-read.
  String _displayExpiry(DateTime d) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickExpiryDate() async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final initial = _expiryDate ?? DateTime(now.year, now.month + 3, now.day);
    // Intentionally no `locale:` — the app has no localizationsDelegates
    // configured, so forcing 'es' throws. System default is fine on CO
    // devices; the cancel/confirm strings below keep the CTA in Spanish.
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year + 10, now.month, now.day),
      helpText: 'Fecha de vencimiento',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
      fieldLabelText: 'Fecha (día/mes/año)',
    );
    if (picked != null && mounted) {
      setState(() => _expiryDate = picked);
    }
  }

  void _clearExpiryDate() {
    HapticFeedback.lightImpact();
    setState(() => _expiryDate = null);
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    final productName = _nameCtrl.text.trim();
    bool savedOk = false;

    try {
      final id = _pendingUuid ?? const Uuid().v4();
      final price = CurrencyUtils.parseToDouble(_sellPriceCtrl.text);
      final stock = int.tryParse(_quantityCtrl.text.trim()) ?? 1;
      // Spec 050 — punto de reorden. Vacío o inválido → 0 (sin alerta).
      final minStock = int.tryParse(_minStockCtrl.text.trim()) ?? 0;

      final api = ApiService(AuthService());
      final expiryIso = _expiryDate == null ? null : _isoDate(_expiryDate!);

      // F029: armar el bloque opcional de tier prices. Solo se incluye
      // si la capacidad está ON; cuando está OFF (95% de tenders) NO
      // serializamos las claves para no tocar columnas del backend.
      // Cada tier que esté vacío también se omite — el backend ya
      // valida > 0 si llega un número.
      final tierExtras = <String, dynamic>{};
      if (_enablePriceTiers) {
        final t1 = CurrencyUtils.parseToDouble(_priceTier1Ctrl.text);
        final t2 = CurrencyUtils.parseToDouble(_priceTier2Ctrl.text);
        final t3 = CurrencyUtils.parseToDouble(_priceTier3Ctrl.text);
        if (t1 > 0) tierExtras['price_tier_1'] = t1;
        if (t2 > 0) tierExtras['price_tier_2'] = t2;
        if (t3 > 0) tierExtras['price_tier_3'] = t3;
      }

      // Offline-first (Art. II): el guardado LOCAL ocurre siempre, aunque la
      // red falle. El bug previo dejaba el upsert local DESPUÉS de la llamada
      // de red dentro del mismo try; sin conexión `createProduct` lanzaba, se
      // saltaba al catch y el producto (con su foto) se perdía — pero igual se
      // mostraba "guardado". Ahora la red es best-effort y el row local nunca
      // se pierde.
      // Invariante offline-first (probada en product_save_flow.dart): la red
      // es best-effort; el guardado local ocurre SIEMPRE; si el server no
      // confirma se marca pendiente para subir luego (Spec 047).
      final outcome = await persistProductOfflineFirst(
        serverWrite: () async {
          if (_pendingUuid != null) {
            // Product was already created by enhance — update it
            await api.updateProduct(id, {
              'name': productName,
              'price': price,
              'stock': stock,
              'min_stock': minStock,
              'image_url': _photoUrl,
              'barcode': _skuCtrl.text.trim(),
              'presentation': _presentation,
              'content': _contentCtrl.text.trim(),
              'category': canonicalValue(_categoryCtrl.text, _categorySuggestions),
              'characteristics': _characteristicsCtrl.text.trim(),
              'expiry_date': expiryIso ?? '',
              'is_age_restricted': _isAgeRestricted,
              if (_pendingCatalogImageId != null)
                'catalog_image_id': _pendingCatalogImageId,
              ...tierExtras,
            });
          } else {
            // Create new product
            _pendingUuid = id;
            await api.createProduct({
              'id': id,
              'name': productName,
              'price': price,
              'stock': stock,
              'min_stock': minStock,
              'image_url': _photoUrl,
              'barcode': _skuCtrl.text.trim(),
              'presentation': _presentation,
              'content': _contentCtrl.text.trim(),
              'category': canonicalValue(_categoryCtrl.text, _categorySuggestions),
              'characteristics': _characteristicsCtrl.text.trim(),
              'is_age_restricted': _isAgeRestricted,
              if (expiryIso != null) 'expiry_date': expiryIso,
              if (_pendingCatalogImageId != null)
                'catalog_image_id': _pendingCatalogImageId,
              ...tierExtras,
            });
          }

          // Upload local photo if taken from camera/gallery.
          // Spec 013: pass the picked XFile — `uploadProductPhoto` reads its
          // bytes and normalizes to PNG, so this works on web and the photo
          // renders on Android. Una falla de FOTO no debe marcar la venta como
          // offline: se maneja aquí y no se propaga.
          final pickedPhoto = _photoFile;
          if (pickedPhoto != null && _photoUrl == null) {
            try {
              final uploadRes = await api.uploadProductPhoto(id, pickedPhoto);
              final url = (uploadRes['photo_url'] as String?) ??
                  (uploadRes['image_url'] as String?);
              if (url != null && url.isNotEmpty) {
                _photoUrl = url;
                await api.updateProduct(id, {'image_url': url});
              }
            } on ImageNormalizationException catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'El producto se guardó, pero no pudimos subir la foto.'),
                  ),
                );
              }
            }
          }
        },
        saveLocal: () async {
          // Only a durable photo URL is stored — never a transient local/blob
          // path that would be a dead reference after a refresh. La factory
          // setea reservedStock (late) para no romper la serialización Isar.
          final product = buildSavedLocalProduct(
            uuid: id,
            name: productName,
            price: price,
            stock: stock,
            minStock: minStock,
            imageUrl: _photoUrl,
            barcode: _skuCtrl.text.trim(),
            presentation: _presentation,
            content: _contentCtrl.text.trim(),
            category: canonicalValue(_categoryCtrl.text, _categorySuggestions),
            characteristics: _characteristicsCtrl.text.trim(),
            expiryDate: _expiryDate,
          );
          await DatabaseService.instance.upsertProduct(product);
        },
        markPending: () => PendingProductPush.add(id),
        // Si no hay red, NO intentamos el servidor: el guardado offline cae al
        // instante en Isar en vez de bloquear ~30s esperando el timeout.
        isOnline: () async {
          final r = await Connectivity().checkConnectivity();
          return r.any((c) => c != ConnectivityResult.none);
        },
      );
      savedOk = outcome.savedLocally;
    } catch (_) {
      // El guardado LOCAL falló de verdad → savedOk queda false; NO mostramos
      // falso éxito (ese era el bug original, una capa más arriba).
      savedOk = false;
    }

    if (!mounted) return;

    if (!savedOk) {
      // No se guardó: avisamos y dejamos el formulario para reintentar.
      HapticFeedback.heavyImpact();
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar el producto. Intente de nuevo.',
              style: TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Producto "$productName" guardado',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Dirty check ────────────────────────────────────────────────────────────

  bool get _isDirty =>
      _nameCtrl.text.trim().isNotEmpty ||
      _skuCtrl.text.trim().isNotEmpty ||
      _photoFile != null ||
      _photoUrl != null;

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Descartar producto?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        content: const Text(
          'Tiene datos sin guardar. Si regresa ahora, se perderá la información.',
          style: TextStyle(fontSize: 17, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, descartar',
                style: TextStyle(fontSize: 18, color: AppTheme.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photoFile != null || _photoUrl != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        // Página gris súper claro (estilo iOS): las tarjetas blancas flotan
        // nítidas encima.
        backgroundColor: DashUI.groupBg,
        appBar: AppBar(
          backgroundColor: DashUI.groupBg,
          surfaceTintColor: DashUI.groupBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: DashUI.ink, size: 28),
            tooltip: 'Volver',
            onPressed: () async {
              final shouldPop = await _confirmDiscard();
              if (shouldPop && context.mounted) Navigator.of(context).pop();
            },
          ),
          title: const Text(
            'Nuevo Producto',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: DashUI.ink,
            ),
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: BranchSelectorChip()),
            ),
          ],
        ),
        // Fixed Cancel + Save buttons at the bottom
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                // Cancel button
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () async {
                        final shouldPop = await _confirmDiscard();
                        if (shouldPop && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DashUI.inkSoft,
                        side: const BorderSide(color: Color(0x14000000)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancelar',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Save button
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 56,
                    // Acción primaria: azul sólido de alto contraste, sin
                    // bordes ni el degradado morado anterior.
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Icon(Icons.save_rounded,
                              size: 20, color: Colors.white),
                      label: Text(
                        _saving ? 'Guardando...' : 'Guardar',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 56),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // ═══════════════════════════════════════════════════════════
                // HERO: Scan Barcode Button
                // ═══════════════════════════════════════════════════════════
                GestureDetector(
                  onTap: _lookingUp ? null : _scanBarcode,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      // Spec 071 — densidad SaaS: acción primaria sólida y
                      // sobria (sin degradado ni sombra azul pesada).
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(AppUI.radiusSm),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_lookingUp)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        else
                          const Icon(Icons.qr_code_scanner_rounded,
                              color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          _lookingUp
                              ? 'Buscando producto...'
                              : 'Escanear código de barras',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text('Escanee para auto-completar los datos',
                      style: TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary)),
                ),

                const SizedBox(height: 20),

                // ═══════════════════════════════════════════════════════════
                // CARD 1: Identidad Visual y Nombre
                // ═══════════════════════════════════════════════════════════
                _card(children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo thumbnail (110x110). Con imagen → ampliar (zoom);
                      // sin imagen → tomar foto.
                      GestureDetector(
                        onTap: (_photoFile != null ||
                                (_photoUrl != null && _photoUrl!.isNotEmpty))
                            ? _openImageViewer
                            : _takePhoto,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGrey,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _buildPhotoContent(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Action buttons column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Spec 018 / FR-01: camera + gallery side by side,
                            // matching "Editar Producto". Two compact buttons
                            // keep the card short on a 360dp screen.
                            Row(
                              children: [
                                Expanded(
                                  child: _actionButton(
                                    key: const Key('btn_take_photo'),
                                    label: 'Tomar foto',
                                    icon: Icons.camera_alt_rounded,
                                    color: AppTheme.primary,
                                    onTap: _takePhoto,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _actionButton(
                                    key: const Key('btn_pick_gallery'),
                                    label: 'Galería',
                                    icon: Icons.photo_library_rounded,
                                    color: AppTheme.success,
                                    onTap: _pickFromGallery,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Spec 018 — opciones de IA claras y separadas:
                            // con foto → MEJORAR (su foto) o CREAR (desde cero);
                            // sin foto → solo CREAR. (Tomar/Galería arriba.)
                            if (hasPhoto) ...[
                              _actionButton(
                                label: _enhancing
                                    ? 'Procesando…'
                                    : 'Mejorar foto con IA',
                                icon: Icons.auto_fix_high_rounded,
                                color: const Color(0xFF7C3AED),
                                loading: _enhancing,
                                onTap: _enhancing
                                    ? null
                                    : () => _enhanceOrGeneratePhoto(),
                              ),
                              const SizedBox(height: 8),
                              _actionButton(
                                label: _enhancing
                                    ? 'Procesando…'
                                    : 'Crear foto con IA',
                                icon: Icons.auto_awesome_rounded,
                                color: const Color(0xFF0E6BA8),
                                loading: _enhancing,
                                onTap: _enhancing
                                    ? null
                                    : () => _enhanceOrGeneratePhoto(
                                        forceGenerate: true),
                              ),
                              const SizedBox(height: 8),
                              // Spec 094: foto de estudio generativa (mejor ángulo,
                              // usa su foto como referencia; puede estilizar).
                              _actionButton(
                                label: _enhancing
                                    ? 'Procesando…'
                                    : 'Foto de estudio (IA)',
                                icon: Icons.camera_enhance_rounded,
                                color: const Color(0xFF0E7490),
                                loading: _enhancing,
                                onTap: _enhancing
                                    ? null
                                    : () => _enhanceOrGeneratePhoto(studio: true),
                              ),
                            ] else
                              _actionButton(
                                label:
                                    _enhancing ? 'Generando…' : 'Crear foto con IA',
                                icon: Icons.auto_awesome_rounded,
                                color: const Color(0xFF7C3AED),
                                loading: _enhancing,
                                onTap: _enhancing
                                    ? null
                                    : () => _enhanceOrGeneratePhoto(
                                        forceGenerate: true),
                              ),
                            // Spec 017 FR-05: si la IA alteró el resultado, el
                            // tendero escribe indicaciones y reintenta.
                            if (hasPhoto && _imageIsSuggested && !_enhancing)
                              TextButton.icon(
                                onPressed: () async {
                                  final hint =
                                      await showAiInstructionDialog(context);
                                  if (hint != null) {
                                    await _enhanceOrGeneratePhoto(
                                        instruction: hint);
                                  }
                                },
                                icon: const Icon(Icons.edit_note_rounded,
                                    size: 18),
                                label: const Text('¿No quedó bien? Dar indicaciones'),
                              ),
                            // Spec 017 — aclarar qué hace cada opción: el caso de
                            // confusión fue usar "Crear" (genera desde el nombre,
                            // NO usa la foto) esperando que respetara el producto.
                            const SizedBox(height: 6),
                            Text(
                              hasPhoto
                                  ? '«Mejorar» = foto de estudio fiel (fondo blanco + luz profesional) SIN cambiar su producto. '
                                      '«Foto de estudio» prueba otro ángulo (puede estilizar). '
                                      '«Crear» hace una imagen nueva (no usa su foto).'
                                  : 'Crea una imagen con IA a partir del nombre (no es una foto real del producto).',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.3,
                                  color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── Catalog image options ─────────────────────────────────
                  if (_catalogImages.length > 1) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Fotos del catálogo',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _catalogImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final url = _catalogImages[index];
                          final isSelected = _photoUrl == url;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                // A catalog photo is tied to the catalog
                                // entry, not a merchant photo — mark it
                                // suggested and tag it with the catalog name
                                // so it drops if the typed name diverges.
                                _photoUrl = url;
                                _photoFile = null;
                                _imageIsSuggested = true;
                                _suggestedImageSourceName = _catalogSourceName;
                              });
                            },
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : AppTheme.borderColor,
                                  width: isSelected ? 2.5 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(url,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_rounded,
                                        size: 24,
                                        color: AppTheme.textSecondary)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── Product name with autocomplete ────────────────────────
                  _fieldLabel('Nombre del producto'),
                  const SizedBox(height: 6),
                  CompositedTransformTarget(
                    link: _nameLayerLink,
                    child: TextFormField(
                      key: _nameFieldKey,
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      style: const TextStyle(fontSize: 18),
                      textInputAction: TextInputAction.next,
                      onChanged: _onNameChanged,
                      onFieldSubmitted: (_) => _confirmNameField(),
                      decoration: InputDecoration(
                        hintText: 'Buscar o escribir nombre...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.w400,
                          fontStyle: FontStyle.italic,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppTheme.primary, size: 22),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppTheme.primary),
                                ),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingrese el nombre';
                        }
                        return null;
                      },
                    ),
                  ),
                  // Sugerencias INLINE (no overlay) — se desplazan y se tocan
                  // como parte del formulario; nunca se cierran al moverlas.
                  if (_suggestions.isNotEmpty) _inlineSuggestions(),
                  // #10 — si el nombre parece un plato preparable, sugiere receta.
                  if (_suggestRecipe) _recipeSuggestionCard(),
                ]),

                const SizedBox(height: 14),

                // ═══════════════════════════════════════════════════════════
                // CARD 2: SKU, Presentación, Contenido
                // ═══════════════════════════════════════════════════════════
                _card(children: [
                  // ── "Data loaded from catalog" indicator ──────────────────
                  if (_dataFromCatalog) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                const Color(0xFF7C3AED).withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 18, color: Color(0xFF7C3AED)),
                          SizedBox(width: 8),
                          Text(
                            'Datos cargados del catálogo',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── SKU / Barcode ─────────────────────────────────────────
                  _fieldLabel('Codigo SKU / Barras'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _skuCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 18),
                    textInputAction: TextInputAction.next,
                    onChanged: (v) {
                      final code = v.trim();
                      setState(() {
                        _skuError = code.isEmpty
                            ? null
                            : BarcodeValidator.validate(code);
                        _skuSuggestion = code.isEmpty
                            ? null
                            : BarcodeValidator.suggestCorrection(code);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Ej: 7702535011119',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                      ),
                      prefixIcon: const Icon(Icons.qr_code_rounded,
                          color: AppTheme.textSecondary, size: 22),
                      errorText: _skuError,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _scanBarcode,
                            icon: const Icon(Icons.qr_code_scanner_rounded,
                                color: AppTheme.success, size: 22),
                            tooltip: 'Escanear código',
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
                          vertical: 12, horizontal: 12),
                    ),
                  ),
                  if (_skuSuggestion != null) _skuSuggestionHint(),
                  const SizedBox(height: 14),

                  // ── Presentation chips ────────────────────────────────────
                  _fieldLabel('Presentación'),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _presentationOptions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final opt = _presentationOptions[i];
                        final selected = _presentation == opt['value'];
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _presentation = opt['value']!),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.primary.withValues(alpha: 0.12)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : AppTheme.borderColor,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(opt['icon']!,
                                    style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 4),
                                Text(
                                  opt['label']!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected
                                        ? AppTheme.primary
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Content / gramaje ─────────────────────────────────────
                  _fieldLabel('Contenido'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _contentCtrl,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(fontSize: 18),
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      hint: 'Ej: 350ml, 500g, 1L, 6 unidades',
                      icon: Icons.scale_rounded,
                      iconColor: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),

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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Licor, cigarrillos. El catálogo pedirá confirmar edad.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ]),

                const SizedBox(height: 14),

                // ═══════════════════════════════════════════════════════════
                // CARD 3: Precios y Cantidad
                // ═══════════════════════════════════════════════════════════
                _card(children: [
                  // ── Prices row ─────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Precio compra'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _buyPriceCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 18),
                              textInputAction: TextInputAction.next,
                              inputFormatters: const [CurrencyInputFormatter()],
                              decoration: _inputDecoration(
                                hint: '\$0',
                                icon: Icons.attach_money_rounded,
                                iconColor: AppTheme.textSecondary,
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Requerido';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Precio venta'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _sellPriceCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                              ),
                              textInputAction: TextInputAction.next,
                              inputFormatters: const [CurrencyInputFormatter()],
                              decoration: _inputDecoration(
                                hint: '\$0',
                                icon: Icons.attach_money_rounded,
                                iconColor: const Color(0xFF10B981),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Requerido';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Quantity stepper (unified component) ──────────────────
                  _fieldLabel('Cantidad'),
                  const SizedBox(height: 8),
                  Container(
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Row(
                      children: [
                        // Minus button
                        GestureDetector(
                          onTap: () {
                            final c = int.tryParse(_quantityCtrl.text) ?? 1;
                            if (c > 1) {
                              HapticFeedback.lightImpact();
                              _quantityCtrl.text = '${c - 1}';
                              setState(() {});
                            }
                          },
                          child: Container(
                            width: 64,
                            height: double.infinity,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF5F7FA),
                              borderRadius: BorderRadius.horizontal(
                                  left: Radius.circular(15)),
                            ),
                            child: const Icon(Icons.remove_rounded,
                                color: AppTheme.textPrimary, size: 26),
                          ),
                        ),
                        // Center value
                        Expanded(
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border.symmetric(
                                vertical: BorderSide(
                                    color: AppTheme.borderColor, width: 1),
                              ),
                            ),
                            child: TextField(
                              controller: _quantityCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                              ),
                              onChanged: (v) {
                                if (v.isEmpty || int.tryParse(v) == null) {
                                  return;
                                }
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                        // Plus button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            final c = int.tryParse(_quantityCtrl.text) ?? 1;
                            _quantityCtrl.text = '${c + 1}';
                            setState(() {});
                          },
                          child: Container(
                            width: 64,
                            height: double.infinity,
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.horizontal(
                                  right: Radius.circular(15)),
                            ),
                            child: const Icon(Icons.add_rounded,
                                color: Colors.white, size: 26),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Stock mínimo (Spec 050) — punto de reorden opcional ────
                  const SizedBox(height: 18),
                  _fieldLabel('Stock mínimo para avisar (opcional)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _minStockCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: const TextStyle(
                      fontSize: 18, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Ej: 5 — le avisamos para pedir al proveedor',
                      hintStyle: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                      prefixIcon: const Icon(Icons.notifications_active_outlined,
                          color: AppTheme.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                  ),
                ]),

                // ═══════════════════════════════════════════════════════════
                // F029 — CARD: Precios por tipo de cliente (tiers)
                // ═══════════════════════════════════════════════════════════
                // Solo renderiza cuando enable_price_tiers está ON. AC-01:
                // tenants sin la capacidad ven la pantalla EXACTAMENTE
                // como antes de F029.
                if (_enablePriceTiers) ...[
                  const SizedBox(height: 14),
                  _card(children: _buildPriceTierFields()),
                ],

                // ═══════════════════════════════════════════════════════════
                // Advanced options (collapsed by default)
                // ═══════════════════════════════════════════════════════════
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune_rounded,
                            size: 20, color: AppTheme.textSecondary),
                        SizedBox(width: 8),
                        Text('Opciones avanzadas',
                            style: TextStyle(
                                fontSize: 16, color: AppTheme.textSecondary)),
                      ],
                    ),
                    children: [
                      _card(children: [
                        _fieldLabel('Fecha de vencimiento'),
                        const SizedBox(height: 6),
                        _expiryDateField(),
                        const SizedBox(height: 14),
                        // Spec 068 — categoría (autocomplete antitypo) +
                        // características, en un bloque compartido con editar.
                        AdvancedProductOptions(
                          categoryController: _categoryCtrl,
                          characteristicsController: _characteristicsCtrl,
                          categorySuggestions: _categorySuggestions,
                        ),
                        const SizedBox(height: 16),
                        // Spec 070 — la galería (más fotos, video o YouTube) se
                        // agrega al EDITAR (el producto debe existir primero).
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.video_library_rounded,
                                  color: AppTheme.primary, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Guarde el producto y luego ábralo en Editar '
                                  'para agregar más fotos, un video corto o un '
                                  'link de YouTube que sus clientes verán en el '
                                  'catálogo.',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.black87, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ), // PopScope
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card({required List<Widget> children}) {
    // Tarjeta limpia: blanca sobre la página gris claro, borde hairline
    // (rgba 0,0,0,.05) y sombra amplia casi invisible — mismo lenguaje que
    // el dashboard/eventos, sin sombras pesadas.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x0D000000), width: 1),
        boxShadow: DashUI.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _actionButton({
    Key? key,
    required String label,
    IconData? icon,
    required Color color,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        key: key,
        onPressed: onTap,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 20),
        // FittedBox keeps the label readable on 360dp: "Tomar foto" and
        // "Galería" sit in narrow side-by-side slots — shrink, never wrap
        // or overflow (UI_RULES § texto de longitud variable).
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

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

  Widget _buildPhotoContent() {
    // BoxFit.contain (not cover) so AI-generated product images that fill
    // edge-to-edge don't get cropped past the rounded container. The
    // Gemini prompt now reserves a 12% safe zone, but older generated
    // assets or user-uploaded tight crops still need this fallback.
    if (_photoFile != null) {
      return PickedImagePreview(
        file: _photoFile!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _photoPlaceholder(),
      );
    }
    if (_photoUrl != null) {
      return Image.network(_photoUrl!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _photoPlaceholder());
    }
    return _photoPlaceholder();
  }

  Widget _photoPlaceholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.camera_alt_rounded, size: 32, color: AppTheme.textSecondary),
        SizedBox(height: 4),
        Text(
          'Foto',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  // F029 — campos opcionales de precio por tier. Cada input usa el
  // mismo `CurrencyInputFormatter` que el precio venta para que el
  // formato sea consistente y los aproximes a $50 se aplique igual.
  // Los labels vienen de los nombres custom del tenant (cargados en
  // _loadPriceTierConfig).
  List<Widget> _buildPriceTierFields() {
    return [
      const Row(
        children: [
          Icon(Icons.local_offer_rounded,
              size: 22, color: AppTheme.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Precios por tipo de cliente',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Opcional — déjelo en blanco para usar el precio venta por defecto.',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade600,
        ),
      ),
      const SizedBox(height: 14),
      _buildTierPriceInput(
        keyName: 'product_price_tier_1',
        label: _tier1Name,
        controller: _priceTier1Ctrl,
      ),
      const SizedBox(height: 12),
      _buildTierPriceInput(
        keyName: 'product_price_tier_2',
        label: _tier2Name,
        controller: _priceTier2Ctrl,
      ),
      const SizedBox(height: 12),
      _buildTierPriceInput(
        keyName: 'product_price_tier_3',
        label: _tier3Name,
        controller: _priceTier3Ctrl,
      ),
    ];
  }

  Widget _buildTierPriceInput({
    required String keyName,
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 6),
        TextFormField(
          key: Key(keyName),
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 18),
          textInputAction: TextInputAction.next,
          inputFormatters: const [CurrencyInputFormatter()],
          decoration: _inputDecoration(
            hint: '\$0',
            icon: Icons.attach_money_rounded,
            iconColor: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _expiryDateField() {
    final hasDate = _expiryDate != null;
    // Large tap target (56px) per gerontodesign guideline — older adults
    // need forgiving hit areas. The calendar icon + Spanish label keeps
    // the purpose obvious without requiring the user to tap to discover it.
    return InkWell(
      onTap: _pickExpiryDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasDate ? AppTheme.primary : AppTheme.borderColor,
            width: hasDate ? 1.5 : 1,
          ),
          color:
              hasDate ? AppTheme.primary.withValues(alpha: 0.04) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_rounded,
              size: 22,
              color: hasDate ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasDate
                    ? _displayExpiry(_expiryDate!)
                    : 'Opcional — toque para elegir',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.w400,
                  fontStyle: hasDate ? FontStyle.normal : FontStyle.italic,
                  color: hasDate ? AppTheme.textPrimary : Colors.grey.shade500,
                ),
              ),
            ),
            if (hasDate)
              IconButton(
                onPressed: _clearExpiryDate,
                icon: const Icon(Icons.close_rounded,
                    size: 22, color: AppTheme.textSecondary),
                tooltip: 'Quitar fecha',
              ),
          ],
        ),
      ),
    );
  }

  /// Generates an internal SKU based on the product name and presentation.
  /// Format: VND-{PRES}-{3-letter-name}-{random4digits}
  void _generateSku() {
    HapticFeedback.lightImpact();
    final name = _nameCtrl.text.trim().toUpperCase();
    final presMap = {
      'botella': 'BOT',
      'lata': 'LAT',
      'bolsa': 'BLS',
      'caja': 'CAJ',
      'frasco': 'FRA',
      'paquete': 'PAQ',
      'unidad': 'UNI',
      'sobre': 'SOB',
    };
    final pres = presMap[_presentation.toLowerCase()] ?? 'GEN';
    final letters = name.replaceAll(RegExp(r'[^A-Z]'), '');
    final nameCode = letters.length >= 3
        ? letters.substring(0, 3)
        : letters.padRight(3, 'X');
    final digits = (DateTime.now().millisecondsSinceEpoch % 10000)
        .toString()
        .padLeft(4, '0');
    setState(() {
      _skuCtrl.text = 'VND-$pres-$nameCode-$digits';
    });
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required Color iconColor,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.grey.shade400,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
      ),
      prefixIcon: Icon(icon, color: iconColor, size: 22),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
    );
  }
}

class _ProductSuggestion {
  final String name;
  final String brand;
  final String? imageUrl;
  final bool isLocal;
  final String? presentation;
  final String? content;
  final String? barcode;
  final String? sku; // SKU normalizado del catálogo (otra tienda) — Spec 077/068
  final String? productUuid; // uuid del producto PROPIO (sugerencia local) → editar
  final String source; // "off", "user", or "local"
  final List<String> images; // accepted catalog images (max 3)

  const _ProductSuggestion({
    required this.name,
    required this.brand,
    this.imageUrl,
    this.isLocal = false,
    this.presentation,
    this.content,
    this.barcode,
    this.sku,
    this.productUuid,
    this.source = 'off',
    this.images = const [],
  });
}

/// Pure decision helpers for "Nuevo Producto" image handling (Feature 018,
/// FR-03 / FR-04). Kept free of any state or I/O so the rules can be unit
/// tested directly — see `test/create_product_screen_fixes_test.dart`.
///
/// Why this exists: the screen used to pin an AI/catalog image (`_photoUrl`)
/// and a catalog image strip (`_catalogImages`) that were never cleared when
/// the typed name changed. A merchant who looked up "Llavero Alien" and then
/// retyped "Llavero Kitty" kept seeing the alien keychains — the catalog
/// strip had no link to the *current* name. These two rules fix that.
class CreateProductImagePolicy {
  const CreateProductImagePolicy._();

  /// Whether a suggested/looked-up/generated image URL may be adopted as
  /// the product photo.
  ///
  /// D2 — the merchant's own photo (camera or gallery) always wins: once
  /// [hasMerchantPhoto] is true no suggested image may overwrite it. An
  /// empty or null [suggestedUrl] is never adopted.
  static bool canApplySuggestedImage({
    required bool hasMerchantPhoto,
    required String? suggestedUrl,
  }) {
    if (hasMerchantPhoto) return false;
    return suggestedUrl != null && suggestedUrl.trim().isNotEmpty;
  }

  /// Whether a catalog image strip — captured for [catalogSourceName] when
  /// the merchant picked that suggestion — still belongs to the product the
  /// merchant is now describing in [currentName].
  ///
  /// FR-04: rather than show unrelated catalog photos, the strip is kept
  /// only while the typed name is still the *same product* — i.e. every
  /// meaningful word of the source name is still present in the current
  /// name. That survives a refinement ("Llavero Kitty" -> "Llavero Kitty
  /// Rosado") but drops on a real divergence ("Llavero Kitty" -> "Llavero
  /// Alien"), which is the reported "alien keychains" disparity.
  static bool catalogStillMatchesName({
    required String catalogSourceName,
    required String currentName,
  }) {
    final source = _words(catalogSourceName);
    final current = _words(currentName);
    if (source.isEmpty || current.isEmpty) return false;
    // Keep only while the current name still contains every word of the
    // name the strip came from — a pure extension of the same product.
    return source.difference(current).isEmpty;
  }

  static Set<String> _words(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-záéíóúñ0-9]+'))
      .where((w) => w.length > 1)
      .toSet();
}
