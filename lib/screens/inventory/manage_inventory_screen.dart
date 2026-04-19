import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class ManageInventoryScreen extends StatefulWidget {
  const ManageInventoryScreen({super.key});

  @override
  State<ManageInventoryScreen> createState() => _ManageInventoryScreenState();
}

class _ManageInventoryScreenState extends State<ManageInventoryScreen> {
  final _searchCtrl = TextEditingController();
  final _api = ApiService(AuthService());
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

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
      final res = await _api.fetchProducts(page: 1, perPage: 100);
      final data = res['data'] as List? ?? [];
      final products = data.cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
      _applyFilter();
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
      if (query.isEmpty) {
        _filtered = List.of(_products);
      } else {
        _filtered = _products.where((p) {
          final name = (p['name'] as String? ?? '').toLowerCase();
          final barcode = (p['barcode'] as String? ?? '').toLowerCase();
          return name.contains(query) || barcode.contains(query);
        }).toList();
      }
    });
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Mi Inventario',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
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
                  fillColor: AppTheme.surfaceGrey,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),

            // Count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
                ],
              ),
            ),
            const SizedBox(height: 8),

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
                                itemCount: _filtered.length,
                                itemBuilder: (context, index) {
                                  final p = _filtered[index];
                                  return _ProductTile(
                                    product: p,
                                    onEdit: () => _editProduct(p),
                                    onDelete: () => _deleteProduct(p),
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

// ── Product tile ─────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? 'Sin nombre';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final stock = product['stock'] as int? ?? 0;
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
          decoration: BoxDecoration(
            color: AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor, width: 1),
          ),
          child: Row(
            children: [
              // Product image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 60,
                  height: 60,
                  color: Colors.white,
                  child: imgSrc != null && imgSrc.isNotEmpty
                      ? Image.network(imgSrc,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.image_not_supported_rounded,
                              size: 28,
                              color: AppTheme.textSecondary))
                      : const Icon(Icons.inventory_2_outlined,
                          size: 28, color: AppTheme.textSecondary),
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _formatPrice(price),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: stock > 0
                                ? AppTheme.success.withValues(alpha: 0.12)
                                : AppTheme.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Stock: $stock',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: stock > 0
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                          ),
                        ),
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
                        size: 22, color: AppTheme.primary),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onEdit();
                    },
                    tooltip: 'Editar',
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
  late final TextEditingController _contentCtrl;
  late final TextEditingController _skuCtrl;
  late String _presentation;
  bool _saving = false;
  bool _enhancing = false;
  String? _photoUrl;
  String? _photoPath;

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
        text: ((p['price'] as num?)?.toDouble() ?? 0).toInt().toString());
    _stockCtrl =
        TextEditingController(text: (p['stock'] as int? ?? 0).toString());
    _contentCtrl =
        TextEditingController(text: p['content'] as String? ?? '');
    _skuCtrl =
        TextEditingController(text: p['barcode'] as String? ?? '');
    _presentation = p['presentation'] as String? ?? '';
    final photo = p['photo_url'] as String?;
    final image = p['image_url'] as String?;
    _photoUrl = (photo != null && photo.isNotEmpty) ? photo : image;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _contentCtrl.dispose();
    _skuCtrl.dispose();
    super.dispose();
  }

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
        _photoUrl = null;
      });
    }
  }

  void _onAiPhotoTap() {
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

    final hasExistingPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;

    if (!hasExistingPhoto) {
      // No photo — go straight to generate
      _executeAiPhoto(useExisting: false);
      return;
    }

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
            _AiOptionTile(
              icon: Icons.auto_fix_high_rounded,
              color: const Color(0xFF3B82F6),
              title: 'Mejorar foto actual',
              subtitle: 'La IA mejora la imagen que ya tiene',
              onTap: () {
                Navigator.of(ctx).pop();
                _executeAiPhoto(useExisting: true);
              },
            ),
            const SizedBox(height: 12),
            _AiOptionTile(
              icon: Icons.auto_awesome_rounded,
              color: const Color(0xFF7C3AED),
              title: 'Generar imagen nueva',
              subtitle: 'Crea una imagen desde cero basada en el nombre y presentación',
              onTap: () {
                Navigator.of(ctx).pop();
                _executeAiPhoto(useExisting: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeAiPhoto({required bool useExisting}) async {
    final id = widget.product['id'] as String? ?? '';
    final currentName = _nameCtrl.text.trim();
    final currentPresentation = _presentation;
    final currentContent = _contentCtrl.text.trim();

    HapticFeedback.lightImpact();
    setState(() => _enhancing = true);
    try {
      final api = ApiService(AuthService());
      final Map<String, dynamic> result;
      if (useExisting) {
        result = await api.enhanceProductPhoto(id,
          name: currentName,
          presentation: currentPresentation,
          content: currentContent,
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
          _photoPath = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(fontSize: 16)),
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

    setState(() => _saving = true);
    try {
      final api = ApiService(AuthService());
      final id = widget.product['id'] as String? ?? '';
      await api.updateProduct(id, {
        'name': name,
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0,
        'stock': int.tryParse(_stockCtrl.text.trim()) ?? 0,
        'presentation': _presentation,
        'content': _contentCtrl.text.trim(),
        'barcode': _skuCtrl.text.trim(),
      });
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al guardar cambios',
              style: TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // (helper widgets below)

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photoPath != null || (_photoUrl != null && _photoUrl!.isNotEmpty);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text(
          'Editar Producto',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
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
                        child: _photoPath != null
                            ? Image.file(File(_photoPath!),
                                width: 110, height: 110, fit: BoxFit.contain)
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _photoAction(
                          label: 'Tomar foto',
                          icon: Icons.camera_alt_rounded,
                          color: AppTheme.primary,
                          onTap: _takePhoto,
                        ),
                        const SizedBox(height: 8),
                        _photoAction(
                          label: _enhancing
                              ? 'Generando...'
                              : 'Imagen con IA',
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

              // SKU / Barcode (editable + auto-generate)
              const Text('SKU / Código de barras',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _skuCtrl,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Ej: 7702535011119',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
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
                      vertical: 14, horizontal: 14),
                ),
              ),
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
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.borderColor,
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
              const SizedBox(height: 32),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 24),
                  label: Text(
                    _saving ? 'Guardando...' : 'Guardar cambios',
                    style: const TextStyle(fontSize: 20),
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
            const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
        filled: true,
        fillColor: AppTheme.surfaceGrey,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
