import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
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
  final _buyPriceCtrl = TextEditingController();
  final _sellPriceCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '1');

  String? _photoPath;
  String? _photoUrl; // from barcode lookup
  String? _pendingUuid; // set after create, before enhance
  bool _saving = false;
  bool _enhancing = false;
  bool _lookingUp = false;

  // Autocomplete
  List<_ProductSuggestion> _suggestions = [];
  Timer? _debounce;
  final _offDio = Dio(BaseOptions(
    baseUrl: 'https://world.openfoodfacts.org',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    _quantityCtrl.dispose();
    super.dispose();
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
    setState(() {});
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _searchProducts(query.trim());
    });
  }

  Future<void> _searchProducts(String query) async {
    try {
      final res = await _offDio.get('/cgi/search.pl', queryParameters: {
        'search_terms': query,
        'search_simple': 1,
        'action': 'process',
        'json': 1,
        'page_size': 5,
        'fields': 'product_name,image_small_url,brands',
        'lc': 'es',
      });
      final products = res.data['products'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        _suggestions = products
            .where((p) =>
                p['product_name'] != null &&
                (p['product_name'] as String).isNotEmpty)
            .map((p) => _ProductSuggestion(
                  name: p['product_name'] as String,
                  brand: p['brands'] as String? ?? '',
                  imageUrl: p['image_small_url'] as String?,
                ))
            .toList();
      });
    } catch (_) {
      // Silent fail — user types manually
    }
  }

  void _selectSuggestion(_ProductSuggestion s) {
    final fullName =
        s.brand.isNotEmpty ? '${s.name} (${s.brand})' : s.name;
    _nameCtrl.text = fullName;
    if (s.imageUrl != null && s.imageUrl!.isNotEmpty) {
      setState(() {
        _photoUrl = s.imageUrl;
        _photoPath = null;
      });
    }
    setState(() => _suggestions = []);
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
    if (_pendingUuid == null) return;
    HapticFeedback.lightImpact();
    setState(() => _enhancing = true);
    try {
      final api = ApiService(AuthService());
      final result = await api.enhanceProductPhoto(_pendingUuid!);
      final url = result['image_url'] as String?;
      if (url != null && mounted) {
        setState(() {
          _photoUrl = url;
          _photoPath = null;
        });
      }
    } catch (_) {
      // best effort
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
      final id = const Uuid().v4();
      _pendingUuid = id;
      final price = double.tryParse(_sellPriceCtrl.text.trim()) ?? 0;
      final stock = int.tryParse(_quantityCtrl.text.trim()) ?? 1;

      // Save to backend
      final api = ApiService(AuthService());
      await api.createProduct({
        'id': id,
        'name': productName,
        'price': price,
        'stock': stock,
      });

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                RawAutocomplete<_ProductSuggestion>(
                  textEditingController: _nameCtrl,
                  focusNode: _nameFocus,
                  optionsBuilder: (textEditingValue) {
                    _onNameChanged(textEditingValue.text);
                    return _suggestions;
                  },
                  displayStringForOption: (s) =>
                      s.brand.isNotEmpty ? '${s.name} (${s.brand})' : s.name,
                  optionsViewBuilder: (context, onSelected, options) {
                    if (options.isEmpty) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          width: MediaQuery.of(context).size.width - 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.borderColor),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: options.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: AppTheme.borderColor),
                            itemBuilder: (_, i) {
                              final s = options.elementAt(i);
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 2),
                                leading: s.imageUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          s.imageUrl!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _suggestionPlaceholder(),
                                        ),
                                      )
                                    : _suggestionPlaceholder(),
                                title: Text(
                                  s.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: s.brand.isNotEmpty
                                    ? Text(s.brand,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            color: AppTheme.textSecondary))
                                    : null,
                                onTap: () {
                                  onSelected(s);
                                  _selectSuggestion(s);
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(fontSize: 18),
                      textInputAction: TextInputAction.next,
                      onChanged: _onNameChanged,
                      decoration: _inputDecoration(
                        hint: 'Ej: Coca-Cola 350ml',
                        icon: Icons.inventory_2_rounded,
                        iconColor: AppTheme.primary,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingrese el nombre';
                        }
                        return null;
                      },
                    );
                  },
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

  const _ProductSuggestion({
    required this.name,
    required this.brand,
    this.imageUrl,
  });
}
