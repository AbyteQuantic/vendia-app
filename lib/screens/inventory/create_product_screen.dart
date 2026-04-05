import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_catalog_product.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
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
  final _contentCtrl = TextEditingController(); // e.g. "350ml", "500g"
  OverlayEntry? _overlayEntry;

  String? _photoPath;
  String? _photoUrl; // from barcode lookup
  String? _pendingUuid; // set after create, before enhance
  String? _pendingCatalogImageId; // set after enhance/generate, sent on save
  List<String> _catalogImages = []; // accepted images from catalog
  bool _saving = false;
  bool _enhancing = false;
  bool _lookingUp = false;
  bool _dataFromCatalog = false; // shows "datos cargados" indicator
  String _presentation = ''; // botella, lata, bolsa, etc.
  final _skuCtrl = TextEditingController();

  // Autocomplete (local Isar + backend catalog)
  List<_ProductSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _searching = false;

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

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) {
        _confirmNameField(unfocus: false);
      }
    });
    // Pre-fill SKU if coming from scanner
    if (widget.initialSku != null && widget.initialSku!.isNotEmpty) {
      _skuCtrl.text = widget.initialSku!;
      // Auto-lookup barcode data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _lookupBarcode(widget.initialSku!);
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _debounce?.cancel();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    _quantityCtrl.dispose();
    _contentCtrl.dispose();
    _skuCtrl.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showSuggestionsOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _nameLayerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 60),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: MediaQuery.of(context).size.width - 32,
              child: Material(
                elevation: 8,
                shadowColor: Colors.black26,
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _suggestions.length,
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      // Subtitle: Presentación - Contenido (priority), fallback to brand
                      final pres = s.presentation ?? '';
                      final cont = s.content ?? '';
                      final detail = [
                        if (pres.isNotEmpty) pres,
                        if (cont.isNotEmpty) cont,
                      ].join(' - ');
                      final subtitleText = detail.isNotEmpty
                          ? detail
                          : (s.brand.isNotEmpty ? s.brand : 'Sin especificar');

                      return InkWell(
                        onTap: () => _selectSuggestion(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              // Image (strict 48x48)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.grey.shade100,
                                  child: s.imageUrl != null && s.imageUrl!.isNotEmpty
                                      ? Image.network(
                                          s.imageUrl!,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              _suggestionPlaceholder(),
                                        )
                                      : _suggestionPlaceholder(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Title + Subtitle
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.brand.isNotEmpty
                                          ? '${s.name} (${s.brand})'
                                          : s.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitleText,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Source badge (pill style)
                              if (s.source == 'user')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: const Text(
                                    'VendIA',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF7C3AED),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else if (s.isLocal)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: const Text(
                                    'Mi tienda',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF0D8B5E),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

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

  void _onNameChanged(String query) {
    _debounce?.cancel();
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
    }).catchError((_) {});
  }

  Future<void> _searchRemote(String query) async {
    if (!mounted) return;
    setState(() => _searching = true);
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
              source: map['source'] as String? ?? 'off',
              images: imagesList,
            );
          })
          .where((s) => s.name.isNotEmpty)
          .toList();

      // Merge: local first, then remote (deduplicated)
      final seen = <String>{};
      final merged = <_ProductSuggestion>[];
      for (final s in [..._suggestions.where((s) => s.isLocal), ...remoteResults]) {
        final key = s.name.toLowerCase();
        if (seen.add(key)) merged.add(s);
        if (merged.length >= 6) break;
      }
      _suggestions = merged;
      _showSuggestionsOverlay();
    } catch (_) {
      // keep local results if backend fails
    } finally {
      if (mounted) setState(() => _searching = false);
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
    final fullName =
        s.brand.isNotEmpty ? '${s.name} (${s.brand})' : s.name;
    _nameCtrl.text = fullName;
    _removeOverlay();
    _suggestions = [];

    final hadUserPhoto = _photoPath != null;

    setState(() {
      // Auto-fill image (only if user hasn't taken their own photo)
      if (!hadUserPhoto && s.imageUrl != null && s.imageUrl!.isNotEmpty) {
        _photoUrl = s.imageUrl;
      }

      // Auto-fill presentation & content
      if (s.presentation != null && s.presentation!.isNotEmpty) {
        _presentation = s.presentation!;
      }
      if (s.content != null && s.content!.isNotEmpty) {
        _contentCtrl.text = s.content!;
      }

      // Auto-fill barcode/SKU
      if (s.barcode != null && s.barcode!.isNotEmpty) {
        _skuCtrl.text = s.barcode!;
      }

      // Store catalog images for selection
      _catalogImages = s.images;

      // Show "data loaded" indicator
      _dataFromCatalog = true;
    });

    // Hide indicator after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _dataFromCatalog = false);
    });
  }

  // ── Photo ──────────────────────────────────────────────────────────────────

  Future<void> _takePhoto() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo != null && mounted) {
      setState(() {
        _photoPath = photo.path;
        _photoUrl = null; // local photo takes precedence
      });
    }
  }

  Future<void> _enhanceOrGeneratePhoto() async {
    // Validate required fields for a good AI result
    final missingFields = <String>[];
    if (_nameCtrl.text.trim().isEmpty) missingFields.add('nombre');
    if (_presentation.isEmpty) missingFields.add('presentación');
    if (_contentCtrl.text.trim().isEmpty) missingFields.add('contenido (ej: 350ml)');

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

    final hasExistingPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;

    HapticFeedback.lightImpact();
    setState(() => _enhancing = true);
    try {
      final api = ApiService(AuthService());

      // Reserve a UUID for the product (in-memory only, NOT saved to DB yet)
      _pendingUuid ??= const Uuid().v4();

      // Create a temporary product in backend ONLY for AI processing
      // This is needed because enhance/generate endpoints require a product ID.
      // The real save happens only when user presses "Guardar".
      await api.createProduct({
        'id': _pendingUuid,
        'name': _nameCtrl.text.trim().isEmpty ? 'Producto temporal' : _nameCtrl.text.trim(),
        'price': double.tryParse(_sellPriceCtrl.text.trim()) ?? 1,
        'stock': int.tryParse(_quantityCtrl.text.trim()) ?? 1,
        'image_url': _photoUrl,
        'presentation': _presentation,
        'content': _contentCtrl.text.trim(),
      }).catchError((_) => <String, dynamic>{}); // Ignore if already exists

      // If product has a photo URL, enhance it. Otherwise, generate from scratch.
      final Map<String, dynamic> result;
      if (hasExistingPhoto) {
        result = await api.enhanceProductPhoto(_pendingUuid!);
      } else {
        result = await api.generateProductImage(_pendingUuid!);
      }

      final url = (result['photo_url'] ?? result['image_url']) as String?;
      final catalogImgId = result['catalog_image_id'] as String?;
      if (url != null && mounted) {
        setState(() {
          _photoUrl = url;
          _photoPath = null;
          if (catalogImgId != null && catalogImgId.isNotEmpty) {
            _pendingCatalogImageId = catalogImgId;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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

  Future<void> _lookupBarcode(String barcode) async {
    setState(() => _lookingUp = true);
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
        if (imageUrl != null && imageUrl.isNotEmpty && _photoPath == null) {
          _photoUrl = imageUrl;
        }
      });
    } catch (_) {
      // best effort — user can fill manually
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
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

    try {
      final id = _pendingUuid ?? const Uuid().v4();
      final price = double.tryParse(_sellPriceCtrl.text.trim()) ?? 0;
      final stock = int.tryParse(_quantityCtrl.text.trim()) ?? 1;

      final api = ApiService(AuthService());
      if (_pendingUuid != null) {
        // Product was already created by enhance — update it
        await api.updateProduct(id, {
          'name': productName,
          'price': price,
          'stock': stock,
          'image_url': _photoUrl,
          'barcode': _skuCtrl.text.trim(),
          'presentation': _presentation,
          'content': _contentCtrl.text.trim(),
          if (_pendingCatalogImageId != null)
            'catalog_image_id': _pendingCatalogImageId,
        });
      } else {
        // Create new product
        _pendingUuid = id;
        await api.createProduct({
          'id': id,
          'name': productName,
          'price': price,
          'stock': stock,
          'image_url': _photoUrl,
          'barcode': _skuCtrl.text.trim(),
          'presentation': _presentation,
          'content': _contentCtrl.text.trim(),
          if (_pendingCatalogImageId != null)
            'catalog_image_id': _pendingCatalogImageId,
        });
      }

      // Save to local Isar for offline
      final product = LocalProduct()
        ..uuid = id
        ..name = productName
        ..price = price
        ..stock = stock
        ..imageUrl = _photoUrl ?? _photoPath
        ..isAvailable = true
        ..requiresContainer = false
        ..containerPrice = 0
        ..barcode = _skuCtrl.text.trim()
        ..presentation = _presentation
        ..content = _contentCtrl.text.trim()
        ..clientUpdatedAt = DateTime.now();
      await DatabaseService.instance.upsertProduct(product);
    } catch (_) {
      // best effort save
    }

    if (!mounted) return;
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
      _photoPath != null ||
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
    final hasPhoto = _photoPath != null || _photoUrl != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscard();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          tooltip: 'Volver',
          onPressed: () async {
            final shouldPop = await _confirmDiscard();
            if (shouldPop && mounted) Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Nuevo Producto',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
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
                      if (shouldPop && mounted) Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.borderColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Cancelar',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Save button
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Icon(Icons.save_rounded,
                              size: 20, color: Colors.white),
                      label: Text(
                        _saving ? 'Guardando...' : 'Guardar',
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(0, 56),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
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
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF5A67D8)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_lookingUp)
                        const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      else
                        const Icon(Icons.qr_code_scanner_rounded,
                            color: Colors.white, size: 26),
                      const SizedBox(width: 12),
                      Text(
                        _lookingUp ? 'Buscando producto...' : 'Escanear Código de Barras',
                        style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text('Escanee para auto-completar los datos',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              ),

              const SizedBox(height: 20),

              // ═══════════════════════════════════════════════════════════
              // CARD 1: Identidad Visual y Nombre
              // ═══════════════════════════════════════════════════════════
              _card(children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo thumbnail (110x110)
                    GestureDetector(
                      onTap: _takePhoto,
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
                          _actionButton(
                            label: 'Tomar foto',
                            icon: Icons.camera_alt_rounded,
                            color: AppTheme.primary,
                            onTap: _takePhoto,
                          ),
                          const SizedBox(height: 8),
                          _actionButton(
                            label: _enhancing
                                ? (hasPhoto ? 'Mejorando...' : 'Generando...')
                                : (hasPhoto ? 'Mejorar con IA' : 'Generar con IA'),
                            icon: _enhancing
                                ? null
                                : (hasPhoto ? Icons.auto_fix_high_rounded : Icons.auto_awesome_rounded),
                            color: const Color(0xFF7C3AED),
                            loading: _enhancing,
                            onTap: _enhancing ? null : _enhanceOrGeneratePhoto,
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
                              _photoUrl = url;
                              _photoPath = null;
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
                                  fit: BoxFit.cover,
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
                                    strokeWidth: 2,
                                    color: AppTheme.primary),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                _fieldLabel('Código SKU / Barras'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _skuCtrl,
                  style: const TextStyle(fontSize: 18),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'Ej: 7702535011119',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                    ),
                    prefixIcon: const Icon(Icons.qr_code_rounded,
                        color: AppTheme.textSecondary, size: 22),
                    suffixIcon: IconButton(
                      onPressed: _generateSku,
                      icon: const Icon(Icons.auto_fix_high_rounded,
                          color: AppTheme.primary, size: 22),
                      tooltip: 'Generar SKU',
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Presentation chips ────────────────────────────────────
                _fieldLabel('Presentación'),
                const SizedBox(height: 6),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _presentationOptions.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final opt = _presentationOptions[i];
                      final selected =
                          _presentation == opt['value'];
                      return GestureDetector(
                        onTap: () => setState(
                            () => _presentation = opt['value']!),
                        child: AnimatedContainer(
                          duration: const Duration(
                              milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.primary
                                    .withValues(alpha: 0.12)
                                : Colors.white,
                            borderRadius:
                                BorderRadius.circular(12),
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
                                  style: const TextStyle(
                                      fontSize: 18)),
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
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
                              if (v.isEmpty || int.tryParse(v) == null) return;
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
              ]),

              // ═══════════════════════════════════════════════════════════
              // Advanced options (collapsed by default)
              // ═══════════════════════════════════════════════════════════
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 20, color: AppTheme.textSecondary),
                      SizedBox(width: 8),
                      Text('Opciones avanzadas',
                          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                    ],
                  ),
                  children: [
                    _card(children: [
                      _fieldLabel('Categoría'),
                      const SizedBox(height: 6),
                      TextFormField(
                        style: const TextStyle(fontSize: 18),
                        decoration: _inputDecoration(
                          hint: 'Ej: Bebidas, Aseo, Snacks',
                          icon: Icons.category_rounded,
                          iconColor: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel('Proveedor'),
                      const SizedBox(height: 6),
                      TextFormField(
                        style: const TextStyle(fontSize: 18),
                        decoration: _inputDecoration(
                          hint: 'Ej: Coca-Cola, Postobón',
                          icon: Icons.local_shipping_rounded,
                          iconColor: AppTheme.textSecondary,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _actionButton({
    required String label,
    IconData? icon,
    required Color color,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }

  Widget _buildPhotoContent() {
    if (_photoPath != null) {
      return Image.file(File(_photoPath!), fit: BoxFit.cover);
    }
    if (_photoUrl != null) {
      return Image.network(_photoUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _photoPlaceholder());
    }
    return _photoPlaceholder();
  }

  Widget _photoPlaceholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.camera_alt_rounded,
            size: 32, color: AppTheme.textSecondary),
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

  /// Generates an internal SKU based on the product name and presentation.
  /// Format: VND-{PRES}-{3-letter-name}-{random4digits}
  void _generateSku() {
    HapticFeedback.lightImpact();
    final name = _nameCtrl.text.trim().toUpperCase();
    final presMap = {
      'botella': 'BOT', 'lata': 'LAT', 'bolsa': 'BLS', 'caja': 'CAJ',
      'frasco': 'FRA', 'paquete': 'PAQ', 'unidad': 'UNI', 'sobre': 'SOB',
    };
    final pres = presMap[_presentation.toLowerCase()] ?? 'GEN';
    final letters = name.replaceAll(RegExp(r'[^A-Z]'), '');
    final nameCode =
        letters.length >= 3 ? letters.substring(0, 3) : letters.padRight(3, 'X');
    final digits =
        (DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
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
      contentPadding:
          const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
    this.source = 'off',
    this.images = const [],
  });
}
