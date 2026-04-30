import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/margin_service.dart';
import '../../theme/app_theme.dart';

/// Colombian rounding: ceil to nearest $50 COP
int roundCOP(double amount) {
  return ((amount / 50).ceil() * 50);
}

/// Suggest a sale price based on purchase price + margin, rounded to $50 COP
int suggestPrice(double purchasePrice, double marginPercent) {
  final base = purchasePrice * (1 + marginPercent / 100);
  return roundCOP(base);
}

// ═══════════════════════════════════════════════════════════════════════════════

class IaResultScreen extends StatefulWidget {
  /// Products extracted by AI. Each map has: name, quantity, unit_price, total_price
  final List<Map<String, dynamic>> extractedProducts;
  final String providerName;

  const IaResultScreen({
    super.key,
    required this.extractedProducts,
    required this.providerName,
  });

  @override
  State<IaResultScreen> createState() => _IaResultScreenState();
}

class _IaResultScreenState extends State<IaResultScreen> {
  late List<_EditableProduct> _products;
  double _marginPercent = 20.0;
  bool _saving = false;
  bool _marginLoaded = false;

  @override
  void initState() {
    super.initState();
    _products = widget.extractedProducts.map((p) {
      final purchasePrice = (p['unit_price'] as num?)?.toDouble() ?? 0;
      final rawExpiry = p['expiry_date'];
      DateTime? parsedExpiry;
      if (rawExpiry is String && rawExpiry.isNotEmpty) {
        parsedExpiry = DateTime.tryParse(rawExpiry);
      }
      return _EditableProduct(
        name: p['name'] as String? ?? '',
        presentation: p['presentation'] as String? ?? '',
        quantity: (p['quantity'] as num?)?.toInt() ?? 1,
        purchasePrice: purchasePrice,
        sellPrice: suggestPrice(purchasePrice, _marginPercent).toDouble(),
        confidence: (p['confidence'] as num?)?.toDouble() ?? 0.9,
        expiryDate: parsedExpiry,
      );
    }).toList();
    _loadMargin();
  }

  Future<void> _loadMargin() async {
    final margin = await MarginService.getMargin();
    if (mounted && margin != _marginPercent) {
      _marginPercent = margin;
      _recalculateAllPrices();
      setState(() => _marginLoaded = true);
    } else {
      if (mounted) setState(() => _marginLoaded = true);
    }
  }

  void _recalculateAllPrices() {
    for (final p in _products) {
      p.sellPrice = suggestPrice(p.purchasePrice, _marginPercent).toDouble();
    }
    setState(() {});
  }

  double get _totalInvoice =>
      _products.fold(0, (sum, p) => sum + p.purchasePrice * p.quantity);

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      final db = DatabaseService.instance;
      for (final p in _products) {
        final product = LocalProduct()
          ..uuid = const Uuid().v4()
          ..name = p.name
          ..price = p.sellPrice
          ..stock = p.quantity
          ..imageUrl = p.photoUrl
          ..isAvailable = true
          ..requiresContainer = false
          ..containerPrice = 0
          ..presentation = p.presentation
          ..barcode = ''
          ..content = ''
          ..expiryDate = p.expiryDate
          ..clientUpdatedAt = DateTime.now();
        await db.upsertProduct(product);
      }

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_products.length} productos guardados en inventario',
            style: const TextStyle(fontSize: 16),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _deleteProduct(int index) {
    HapticFeedback.lightImpact();
    setState(() => _products.removeAt(index));
  }

  Future<void> _takePhotoFor(int index) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _products[index].photoPath = picked.path;
      _products[index].photoUrl = null;
    });
  }

  Future<void> _pickFromGalleryFor(int index) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _products[index].photoPath = picked.path;
      _products[index].photoUrl = null;
    });
  }

  Future<void> _enhanceOrGenerateFor(int index) async {
    final p = _products[index];
    setState(() => p.enhancing = true);
    try {
      final api = ApiService(AuthService());
      // Create the product first so we have a UUID for the enhance endpoint
      final uuid = const Uuid().v4();
      final createPayload = <String, dynamic>{
        'id': uuid,
        'name': p.name,
        'price': p.sellPrice,
        'stock': p.quantity,
      };
      await api.createProduct(createPayload);

      Map<String, dynamic> result;
      if (p.photoPath != null) {
        // Upload + enhance existing photo
        await api.uploadProductPhoto(uuid, File(p.photoPath!));
        result = await api.enhanceProductPhoto(uuid);
      } else {
        // Generate from scratch using product name
        result = await api.generateProductImage(uuid);
      }
      if (!mounted) return;
      final url = result['photo_url'] as String? ?? result['image_url'] as String?;
      setState(() {
        p.photoUrl = url;
        p.photoPath = null;
        p.enhancing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => p.enhancing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error IA: $e', style: const TextStyle(fontSize: 14)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  static const _monthAbbr = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  static String _displayExpiry(DateTime d) =>
      '${d.day} ${_monthAbbr[d.month - 1]} ${d.year}';

  Future<DateTime?> _pickExpiry(
    BuildContext ctx, {
    DateTime? current,
  }) async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final initial = current ?? DateTime(now.year, now.month + 3, now.day);
    return showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year + 10, now.month, now.day),
      helpText: 'Fecha de vencimiento',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
      fieldLabelText: 'Fecha (día/mes/año)',
    );
  }

  void _editProduct(int index) {
    final p = _products[index];
    final nameCtrl = TextEditingController(text: p.name);
    final presCtrl = TextEditingController(text: p.presentation);
    final qtyCtrl = TextEditingController(text: p.quantity.toString());
    final buyCtrl = TextEditingController(text: p.purchasePrice.round().toString());
    final sellCtrl = TextEditingController(text: p.sellPrice.round().toString());
    DateTime? draftExpiry = p.expiryDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D0C8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Editar Producto',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 16),

                _EditField(label: 'Nombre', controller: nameCtrl),
                const SizedBox(height: 12),
                _EditField(label: 'Presentación', controller: presCtrl,
                    hint: 'Ej: PACA X12, 350ml'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _EditField(
                        label: 'Cantidad', controller: qtyCtrl,
                        numeric: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _EditField(
                        label: 'P. Compra', controller: buyCtrl,
                        numeric: true, prefix: '\$')),
                  ],
                ),
                const SizedBox(height: 12),
                _EditField(
                    label: 'Precio Venta', controller: sellCtrl,
                    numeric: true, prefix: '\$'),
                const SizedBox(height: 6),
                Text(
                  'Sugerido: \$${suggestPrice(double.tryParse(buyCtrl.text) ?? 0, _marginPercent)} (+${_marginPercent.round()}%)',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.success,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                // Expiry date (optional). Pre-filled when Gemini detected
                // a date on the invoice — shopkeeper just confirms.
                const Text('Fecha de vencimiento',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                StatefulBuilder(
                  builder: (sbCtx, sbSet) => InkWell(
                    onTap: () async {
                      final picked = await _pickExpiry(sbCtx,
                          current: draftExpiry);
                      if (picked != null) {
                        sbSet(() => draftExpiry = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: draftExpiry != null
                              ? AppTheme.primary
                              : AppTheme.borderColor,
                          width: draftExpiry != null ? 1.5 : 1,
                        ),
                        color: draftExpiry != null
                            ? AppTheme.primary.withValues(alpha: 0.04)
                            : Colors.white,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded,
                              size: 22,
                              color: draftExpiry != null
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              draftExpiry != null
                                  ? _displayExpiry(draftExpiry!)
                                  : 'Opcional — toque para elegir',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: draftExpiry != null
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                fontStyle: draftExpiry != null
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                                color: draftExpiry != null
                                    ? AppTheme.textPrimary
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ),
                          if (draftExpiry != null)
                            IconButton(
                              onPressed: () =>
                                  sbSet(() => draftExpiry = null),
                              icon: const Icon(Icons.close_rounded,
                                  size: 22,
                                  color: AppTheme.textSecondary),
                              tooltip: 'Quitar fecha',
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        p.name = nameCtrl.text.trim();
                        p.presentation = presCtrl.text.trim();
                        p.quantity = int.tryParse(qtyCtrl.text) ?? p.quantity;
                        p.purchasePrice = double.tryParse(buyCtrl.text) ?? p.purchasePrice;
                        p.sellPrice = double.tryParse(sellCtrl.text) ?? p.sellPrice;
                        p.expiryDate = draftExpiry;
                      });
                      Navigator.of(ctx).pop();
                    },
                    icon: const Icon(Icons.check_rounded, size: 22),
                    label: const Text('Guardar cambios',
                        style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCOP(double amount) {
    final n = amount.round();
    if (n == 0) return '\$0';
    final s = n.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // Green header
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 24, right: 24, bottom: 20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_products.length} productos detectados',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Factura de ${widget.providerName}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ${_formatCOP(_totalInvoice)} · Margen: ${_marginPercent.round()}%',
                    style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ),

          // Editable product list
          Expanded(
            child: _products.isEmpty
                ? const Center(
                    child: Text('No hay productos',
                        style: TextStyle(fontSize: 18,
                            color: AppTheme.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _products.length,
                    itemBuilder: (_, i) => _ProductCard(
                      product: _products[i],
                      marginPercent: _marginPercent,
                      formatCOP: _formatCOP,
                      onEdit: () => _editProduct(i),
                      onDelete: () => _deleteProduct(i),
                      onTakePhoto: () => _takePhotoFor(i),
                      onPickGallery: () => _pickFromGalleryFor(i),
                      onEnhance: () => _enhanceOrGenerateFor(i),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _saving || _products.isEmpty ? null : _saveAll,
                icon: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Icon(Icons.save_rounded,
                        size: 22, color: Colors.white),
                label: Text(
                  _saving
                      ? 'Guardando...'
                      : 'Guardar ${_products.length} productos',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRODUCT CARD (editable)
// ═══════════════════════════════════════════════════════════════════════════════

class _ProductCard extends StatelessWidget {
  final _EditableProduct product;
  final double marginPercent;
  final String Function(double) formatCOP;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickGallery;
  final VoidCallback onEnhance;

  const _ProductCard({
    required this.product,
    required this.marginPercent,
    required this.formatCOP,
    required this.onEdit,
    required this.onDelete,
    required this.onTakePhoto,
    required this.onPickGallery,
    required this.onEnhance,
  });

  @override
  Widget build(BuildContext context) {
    final total = product.purchasePrice * product.quantity;
    final isLowConfidence = product.confidence < 0.7;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isLowConfidence
              ? AppTheme.warning.withValues(alpha: 0.5)
              : AppTheme.borderColor,
          width: isLowConfidence ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo + Name row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo thumbnail
              GestureDetector(
                onTap: onTakePhoto,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 72, height: 72,
                    color: AppTheme.surfaceGrey,
                    child: _buildThumb(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(product.name,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        if (isLowConfidence)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Revisar',
                                style: TextStyle(fontSize: 11,
                                    color: AppTheme.warning,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Photo action buttons
                    Row(
                      children: [
                        _miniBtn(Icons.camera_alt_rounded, 'Foto',
                            AppTheme.primary, onTakePhoto),
                        const SizedBox(width: 6),
                        _miniBtn(Icons.photo_library_rounded, 'Galería',
                            const Color(0xFF6D28D9), onPickGallery),
                        const SizedBox(width: 6),
                        _miniBtn(
                            product.enhancing
                                ? Icons.hourglass_top_rounded
                                : (product.hasPhoto
                                    ? Icons.auto_fix_high_rounded
                                    : Icons.auto_awesome_rounded),
                            product.enhancing
                                ? '...'
                                : (product.hasPhoto ? 'Mejorar' : 'IA'),
                            const Color(0xFF7C3AED),
                            product.enhancing ? null : onEnhance),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (product.presentation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(product.presentation,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
            ),
          if (product.expiryDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_rounded,
                        size: 14, color: AppTheme.warning),
                    const SizedBox(width: 4),
                    Text(
                      'Vence: ${_IaResultScreenState._displayExpiry(product.expiryDate!)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),

          // Prices row
          Row(
            children: [
              // Purchase
              _PriceChip(
                label: 'Compra',
                value: formatCOP(product.purchasePrice),
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              // Sale (suggested)
              _PriceChip(
                label: 'Venta',
                value: formatCOP(product.sellPrice),
                color: AppTheme.success,
                badge: '+${marginPercent.round()}%',
              ),
              const Spacer(),
              // Qty
              Text('x${product.quantity}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 8),

          // Action buttons
          Row(
            children: [
              Text('Total: ${formatCOP(total)}',
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary)),
              const Spacer(),
              // Edit
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded,
                          size: 18, color: AppTheme.primary),
                      SizedBox(width: 4),
                      Text('Editar',
                          style: TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Delete
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_rounded,
                      size: 18, color: AppTheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThumb() {
    if (product.enhancing) {
      return const Center(
          child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    if (product.photoPath != null && product.photoPath!.isNotEmpty) {
      return Image.file(File(product.photoPath!), fit: BoxFit.cover);
    }
    if (product.photoUrl != null && product.photoUrl!.isNotEmpty) {
      return Image.network(product.photoUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined, size: 28, color: AppTheme.textSecondary));
    }
    return const Center(
        child: Icon(Icons.add_a_photo_rounded, size: 28,
            color: AppTheme.textSecondary));
  }

  Widget _miniBtn(IconData icon, String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? badge;

  const _PriceChip({
    required this.label,
    required this.value,
    required this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: color)),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(badge!,
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.bold, color: color)),
              ),
            ],
          ],
        ),
        Text(value,
            style: TextStyle(fontSize: 16,
                fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool numeric;
  final String? prefix;
  final String? hint;

  const _EditField({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.prefix,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 18, color: Color(0xFF1A1A1A)),
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _EditableProduct {
  String name;
  String presentation;
  int quantity;
  double purchasePrice;
  double sellPrice;
  double confidence;
  DateTime? expiryDate;
  String? photoPath;
  String? photoUrl;
  bool enhancing;

  _EditableProduct({
    required this.name,
    required this.presentation,
    required this.quantity,
    required this.purchasePrice,
    required this.sellPrice,
    required this.confidence,
    this.expiryDate,
    this.photoPath,
    this.photoUrl,
    this.enhancing = false,
  });

  bool get hasPhoto =>
      (photoPath != null && photoPath!.isNotEmpty) ||
      (photoUrl != null && photoUrl!.isNotEmpty);
}
