import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../pos/scan_screen.dart';

/// Manual product creation form — single-screen, no scroll.
class CreateProductScreen extends StatefulWidget {
  const CreateProductScreen({super.key});

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
  bool _saving = false;
  bool _enhancing = false;
  bool _lookingUp = false;
  String _presentation = ''; // botella, lata, bolsa, etc.

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
  void dispose() {
    _removeOverlay();
    _debounce?.cancel();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    _quantityCtrl.dispose();
    _contentCtrl.dispose();
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
        offset: const Offset(0, 56),
        child: SizedBox(
          width: MediaQuery.of(context).size.width - 32,
          child: Material(
            elevation: 12,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded,
                            size: 16, color: AppTheme.primary.withValues(alpha: 0.7)),
                        const SizedBox(width: 6),
                        Text(
                          '${_suggestions.length} producto${_suggestions.length == 1 ? '' : 's'} encontrado${_suggestions.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.primary.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.borderColor),
                  // List
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 62, color: AppTheme.borderColor),
                      itemBuilder: (_, i) {
                        final s = _suggestions[i];
                        return InkWell(
                          onTap: () => _selectSuggestion(s),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                // Image
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    color: AppTheme.surfaceGrey,
                                    child: s.imageUrl != null
                                        ? Image.network(
                                            s.imageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _suggestionPlaceholder(),
                                          )
                                        : _suggestionPlaceholder(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Text
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (s.brand.isNotEmpty)
                                        Text(
                                          s.brand,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSecondary
                                                .withValues(alpha: 0.8),
                                          ),
                                          maxLines: 1,
                                        ),
                                    ],
                                  ),
                                ),
                                // Source badge
                                if (s.isLocal)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Mi tienda',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded,
                                    size: 18,
                                    color: Colors.grey.shade300),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchProducts(query.trim()).then((_) {
        if (mounted) setState(() => _searching = false);
      });
    });
  }

  Future<void> _searchProducts(String query) async {
    final lowerQ = query.toLowerCase();

    // 1. Instant results from local Isar DB
    try {
      final localProducts = await DatabaseService.instance.getAllProducts();
      final localMatches = localProducts
          .where((p) => p.name.toLowerCase().contains(lowerQ))
          .take(5)
          .map((p) => _ProductSuggestion(
                name: p.name,
                brand: '',
                imageUrl: p.imageUrl,
                isLocal: true,
              ))
          .toList();

      if (localMatches.isNotEmpty && mounted) {
        _suggestions = localMatches;
        _showSuggestionsOverlay();
      }
    } catch (_) {}

    // 2. Backend catalog (cached OFF) — merges with local
    try {
      final api = ApiService(AuthService());
      final res = await api.searchProductsOFF(query);
      final products = res['data'] as List? ?? [];
      if (!mounted) return;

      final remoteResults = products
          .map((p) {
            final map = p as Map<String, dynamic>;
            return _ProductSuggestion(
              name: map['name'] as String? ?? '',
              brand: map['brand'] as String? ?? '',
              imageUrl: map['image_url'] as String?,
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
    }
  }

  void _selectSuggestion(_ProductSuggestion s) {
    final fullName =
        s.brand.isNotEmpty ? '${s.name} (${s.brand})' : s.name;
    _nameCtrl.text = fullName;
    _removeOverlay();
    _suggestions = [];
    if (s.imageUrl != null && s.imageUrl!.isNotEmpty) {
      setState(() {
        _photoUrl = s.imageUrl;
        _photoPath = null;
      });
    } else {
      setState(() {});
    }
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

  Future<void> _enhancePhoto() async {
    if (_photoUrl == null || _photoUrl!.isEmpty) return;

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
                  'Para mejorar la foto completa los campos: ${missingFields.join(", ")}',
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

    HapticFeedback.lightImpact();
    setState(() => _enhancing = true);
    try {
      final api = ApiService(AuthService());
      final price = double.tryParse(_sellPriceCtrl.text.trim()) ?? 1;

      // Auto-create the product in backend if it doesn't exist yet
      if (_pendingUuid == null) {
        final id = const Uuid().v4();
        await api.createProduct({
          'id': id,
          'name': _nameCtrl.text.trim(),
          'price': price > 0 ? price : 1,
          'stock': int.tryParse(_quantityCtrl.text.trim()) ?? 1,
          'image_url': _photoUrl,
          'presentation': _presentation,
          'content': _contentCtrl.text.trim(),
        });
        _pendingUuid = id;
      } else {
        // Update with latest presentation info before enhancing
        await api.updateProduct(_pendingUuid!, {
          'presentation': _presentation,
          'content': _contentCtrl.text.trim(),
          'image_url': _photoUrl,
        });
      }

      final result = await api.enhanceProductPhoto(_pendingUuid!);
      // Backend returns "photo_url" key
      final url = (result['photo_url'] ?? result['image_url']) as String?;
      if (url != null && mounted) {
        setState(() {
          _photoUrl = url;
          _photoPath = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al mejorar foto: $e'),
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
        if (imageUrl != null && imageUrl.isNotEmpty) {
          _photoUrl = imageUrl;
          _photoPath = null;
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
          'presentation': _presentation,
          'content': _contentCtrl.text.trim(),
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
          'presentation': _presentation,
          'content': _contentCtrl.text.trim(),
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photoPath != null || _photoUrl != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
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
      // Fixed save button at the very bottom — never inside a scroll.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Icon(Icons.save_rounded,
                        size: 22, color: Colors.white),
                label: Text(
                  _saving ? 'Guardando...' : 'Guardar',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // ── Top row: photo + action buttons ────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Photo thumbnail
                    GestureDetector(
                      onTap: _takePhoto,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 100,
                          height: 100,
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
                          // Tomar foto
                          SizedBox(
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt_rounded,
                                  size: 20),
                              label: const Text(
                                'Tomar foto',
                                style: TextStyle(fontSize: 16),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: const BorderSide(
                                    color: AppTheme.primary, width: 1.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Mejorar con IA — only when photo exists
                          if (hasPhoto)
                            SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: _enhancing ? null : _enhancePhoto,
                                icon: _enhancing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.auto_fix_high_rounded,
                                        size: 20),
                                label: Text(
                                  _enhancing ? 'Mejorando...' : 'Mejorar con IA',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF7C3AED),
                                  side: const BorderSide(
                                      color: Color(0xFF7C3AED), width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10),
                                ),
                              ),
                            ),
                          // Escanear código — compact, only when no "Mejorar"
                          if (!hasPhoto)
                            SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                onPressed: _lookingUp ? null : _scanBarcode,
                                icon: _lookingUp
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(
                                        Icons.qr_code_scanner_rounded,
                                        size: 20),
                                label: Text(
                                  _lookingUp ? 'Buscando...' : 'Escanear código',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF667EEA),
                                  side: const BorderSide(
                                      color: Color(0xFF667EEA), width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                // When photo exists, show scan barcode as a second row
                if (hasPhoto) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _lookingUp ? null : _scanBarcode,
                      icon: _lookingUp
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.qr_code_scanner_rounded, size: 20),
                      label: Text(
                        _lookingUp ? 'Buscando...' : 'Escanear código de barras',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF667EEA),
                        side: const BorderSide(
                            color: Color(0xFF667EEA), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
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

                const SizedBox(height: 14),

                // ── Presentation + Content row ──────────────────────────
                Row(
                  children: [
                    // Presentation chips
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Presentación'),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 42,
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
                                        horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppTheme.primary
                                              .withValues(alpha: 0.12)
                                          : AppTheme.surfaceGrey,
                                      borderRadius:
                                          BorderRadius.circular(10),
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
                                                fontSize: 16)),
                                        const SizedBox(width: 4),
                                        Text(
                                          opt['label']!,
                                          style: TextStyle(
                                            fontSize: 13,
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
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Content / gramaje
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

                // ── Quantity stepper ───────────────────────────────────────
                Row(
                  children: [
                    _fieldLabel('Cantidad'),
                    const Spacer(),
                    // Decrease
                    GestureDetector(
                      onTap: () {
                        final current = int.tryParse(_quantityCtrl.text) ?? 1;
                        if (current > 1) {
                          _quantityCtrl.text = '${current - 1}';
                          setState(() {});
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGrey,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: const Icon(Icons.remove_rounded,
                            color: AppTheme.textPrimary, size: 24),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Editable value
                    SizedBox(
                      width: 64,
                      height: 48,
                      child: TextField(
                        controller: _quantityCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          filled: true,
                          fillColor: AppTheme.surfaceGrey,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppTheme.borderColor, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppTheme.primary, width: 2),
                          ),
                        ),
                        onChanged: (v) {
                          if (v.isEmpty || int.tryParse(v) == null) return;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Increase
                    GestureDetector(
                      onTap: () {
                        final current = int.tryParse(_quantityCtrl.text) ?? 1;
                        _quantityCtrl.text = '${current + 1}';
                        setState(() {});
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

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

  const _ProductSuggestion({
    required this.name,
    required this.brand,
    this.imageUrl,
    this.isLocal = false,
  });
}
