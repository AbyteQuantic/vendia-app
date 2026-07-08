import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_service.dart';
import '../../database/collections/local_product.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../services/image_normalizer.dart' show ImageNormalizationException;
import '../../services/margin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_photo_options_sheet.dart';
import '../../utils/product_matcher.dart';
import '../../utils/currency_input.dart';
import '../../widgets/picked_image_preview.dart';
import '../admin/suppliers_screen.dart';

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
      final matchId = p['match_product_id'] as String? ?? '';
      final matchMethod = p['match_method'] as String? ?? '';
      final status = p['status'] as String? ?? '';
      return _EditableProduct(
        name: p['name'] as String? ?? '',
        presentation: p['presentation'] as String? ?? '',
        content: p['content'] as String? ?? '',
        barcode: p['barcode'] as String? ?? '',
        quantity: (p['quantity'] as num?)?.toInt() ?? 1,
        purchasePrice: purchasePrice,
        sellPrice: suggestPrice(purchasePrice, _marginPercent).toDouble(),
        confidence: (p['confidence'] as num?)?.toDouble() ?? 0.9,
        expiryDate: parsedExpiry,
        photoUrl: p['image_url'] as String?,
        matchProductId: matchId.isNotEmpty ? matchId : null,
        matchMethod: matchMethod,
        // Auto-merge on barcode match
        useExisting: status == 'match_encontrado' && matchMethod == 'barcode',
      );
    }).toList();
    _loadMargin();
    _runMatching();
  }

  Future<void> _runMatching() async {
    // The backend ScanInvoice already populated matchProductId for
    // products that matched (barcode/normalized/fuzzy). We just need
    // to enrich with local Isar data for the UI toggle.
    final db = DatabaseService.instance;
    final catalog = await db.getAllProducts();
    if (!mounted) return;

    var changed = false;
    for (final p in _products) {
      // If backend already found a match, try to find it locally too
      if (p.matchProductId != null && p.matchProductId!.isNotEmpty) {
        final local = catalog.where((lp) => lp.uuid == p.matchProductId);
        if (local.isNotEmpty) {
          p.matchedProduct = local.first;
          p.matchScore = p.matchMethod == 'barcode'
              ? 1.0
              : p.matchMethod == 'normalized'
                  ? 0.9
                  : 0.7;
        } else {
          // Backend matched but local Isar doesn't have it — still
          // enable merge since _saveAll uses the API directly
          p.matchScore = p.matchMethod == 'barcode' ? 1.0 : 0.9;
        }
        changed = true;
        continue;
      }
      // Fallback: local fuzzy matching for products without backend match
      if (catalog.isNotEmpty) {
        final match = findBestMatch(p.name, catalog);
        if (match != null) {
          p.matchedProduct = match.product;
          p.matchProductId = match.product.uuid;
          p.matchScore = match.score;
          changed = true;
        }
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _loadMargin() async {
    final margin = await MarginService.getMargin();
    if (mounted && margin != _marginPercent) {
      _marginPercent = margin;
      _recalculateAllPrices();
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

    final api = ApiService(AuthService());
    int created = 0;
    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    for (var i = 0; i < _products.length; i++) {
      final p = _products[i];
      try {
        // Ensure price is at least $50 COP (backend requires gt=0)
        final price = p.sellPrice > 0 ? p.sellPrice : 50.0;
        final qty = p.quantity > 0 ? p.quantity : 1;

        String? isoExpiry;
        if (p.expiryDate != null) {
          isoExpiry = '${p.expiryDate!.year}-'
              '${p.expiryDate!.month.toString().padLeft(2, '0')}-'
              '${p.expiryDate!.day.toString().padLeft(2, '0')}';
        }

        final matchId = p.matchedProduct?.uuid ?? p.matchProductId;
        if (p.useExisting && matchId != null && matchId.isNotEmpty) {
          // Restock existing product — atomic increment via dedicated endpoint
          final restockData = <String, dynamic>{
            'quantity': qty,
            'price': price,
            'purchase_price': p.purchasePrice,
          };
          if (p.photoUrl != null && p.photoUrl!.isNotEmpty) {
            restockData['image_url'] = p.photoUrl;
          }
          if (isoExpiry != null) restockData['expiry_date'] = isoExpiry;
          debugPrint('[SAVE] RESTOCK product $matchId: +$qty');
          try {
            await api.restockProduct(matchId, restockData);
            updated++;
          } catch (_) {
            // Product may have been deleted — fall through to create
            debugPrint('[SAVE] RESTOCK failed, creating new instead');
            final data = <String, dynamic>{
              'name': p.name,
              'price': price,
              'stock': qty,
              'presentation': p.presentation,
              'content': p.content,
              'barcode': p.barcode,
            };
            if (p.photoUrl != null && p.photoUrl!.isNotEmpty) {
              data['image_url'] = p.photoUrl;
            }
            if (isoExpiry != null) data['expiry_date'] = isoExpiry;
            await api.createProduct(data);
            created++;
          }
        } else {
          // Create new product via POST
          final data = <String, dynamic>{
            'name': p.name,
            'price': price,
            'stock': qty,
            'presentation': p.presentation,
            'content': p.content,
            'barcode': p.barcode,
          };
          if (p.photoUrl != null && p.photoUrl!.isNotEmpty) {
            data['image_url'] = p.photoUrl;
          }
          if (isoExpiry != null) data['expiry_date'] = isoExpiry;
          debugPrint('[SAVE] CREATE new product: ${p.name} price=$price qty=$qty');
          await api.createProduct(data);
          created++;
        }
        debugPrint('[SAVE] ${i + 1}/${_products.length} OK: ${p.name}');
      } catch (e) {
        failed++;
        errors.add('${p.name}: $e');
        debugPrint('[SAVE] ${i + 1}/${_products.length} FAILED: ${p.name} — $e');
      }
    }

    // Log the invoice save (fire-and-forget)
    if (created + updated > 0) {
      api.logInvoiceSave({
        'provider_name': widget.providerName,
        'invoice_total': _totalInvoice,
        'products': _products.map((p) => {
          'name': p.name,
          'quantity': p.quantity,
          'is_new': !(p.useExisting && (p.matchProductId ?? '').isNotEmpty),
        }).toList(),
      });
    }

    if (!mounted) return;
    HapticFeedback.heavyImpact();

    // Show result snackbar FIRST — user needs to see the outcome
    final parts = <String>[];
    if (created > 0) parts.add('$created creados');
    if (updated > 0) parts.add('$updated actualizados');
    if (failed > 0) parts.add('$failed fallaron');

    final saved = created + updated;
    debugPrint('[SAVE] DONE: created=$created updated=$updated failed=$failed');
    if (saved == 0) {
      // Nothing saved — stay on screen, show error dialog
      setState(() => _saving = false);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al guardar'),
          content: Text(
            'No se pudieron guardar los productos.\n\n'
            '${errors.take(3).join("\n")}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // At least some products saved — navigate away
    final provName = widget.providerName;
    final hasProvider = provName.isNotEmpty &&
        provName != 'Desconocido' &&
        provName != 'Proveedor' &&
        provName != 'Dictado por voz';

    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$saved productos guardados',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              parts.join(", "),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: failed > 0 ? AppTheme.warning : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    // Offer supplier registration AFTER navigating home
    if (hasProvider) {
      // Small delay so snackbar is visible before dialog
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final nav = Navigator.of(context);
      final goToSuppliers = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Proveedor detectado'),
          content: Text(
            'La factura es de "$provName".\n¿Registrarlo como proveedor?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      );
      if (goToSuppliers == true) {
        nav.push(MaterialPageRoute(
          builder: (_) => SuppliersScreen(invoiceProviderName: provName),
        ));
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
      _products[index].photoFile = picked;
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
      _products[index].photoFile = picked;
      _products[index].photoUrl = null;
    });
  }

  bool _canGenerateImage(_EditableProduct p) {
    return p.name.trim().length >= 3;
  }

  Future<void> _enhanceOrGenerateFor(int index) async {
    final p = _products[index];

    if (!_canGenerateImage(p)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Agrega el nombre del producto (min. 3 letras) y la '
            'presentacion para que la IA genere una imagen fiel.',
            style: TextStyle(fontSize: 14),
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Spec 094: si el producto del lote YA tiene foto (tomada o resultado
    // previo de IA), el tendero elige en la hoja unificada; sin foto, se
    // genera directo. Mismo orden/hoja que crear/editar.
    final hasPhoto = p.photoFile != null ||
        (p.photoUrl != null && p.photoUrl!.isNotEmpty);
    if (!hasPhoto) {
      await _runAiPhoto(index, forceGenerate: true);
      return;
    }
    await showAiPhotoOptions(
      context,
      name: p.name,
      presentation: p.presentation,
      content: p.content,
      hasPhoto: true,
      onRemoveBg: () => _runAiPhoto(index),
      onImprove: () => _runAiPhoto(index, mode: 'improve'),
      onGenerate: () => _runAiPhoto(index, forceGenerate: true),
    );
  }

  /// Ejecuta la acción de IA sobre el producto [index] del lote.
  /// - [forceGenerate] `true` → genera imagen nueva desde el nombre.
  /// - con foto y sin forceGenerate → mejora (`mode: 'improve'`) o quita fondo
  ///   (`mode` null) sobre la foto real / resultado previo.
  Future<void> _runAiPhoto(int index,
      {String? mode, bool forceGenerate = false}) async {
    final p = _products[index];
    final usePhoto = !forceGenerate &&
        (p.photoFile != null || (p.photoUrl != null && p.photoUrl!.isNotEmpty));

    setState(() => p.enhancing = true);
    // Spec 016 / FR-03: the AI photo job runs asynchronously on the
    // backend; ApiService polls its status under the hood. Tell the
    // tendero it is processing so the wait never reads as a failure.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        usePhoto
            ? 'Procesando tu foto con IA…'
            : 'Generando la imagen con IA…',
        style: const TextStyle(fontSize: 14),
      ),
      backgroundColor: const Color(0xFF7C3AED),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
    ));
    try {
      final api = ApiService(AuthService());
      // Create a throwaway product just so the AI photo endpoints have
      // a UUID to work with. We delete it immediately after — the real
      // product is only created in _saveAll() when the user confirms.
      final tempUuid = const Uuid().v4();
      final picked = p.photoFile;
      await api.createProduct({
        'id': tempUuid,
        'name': p.name,
        'price': p.sellPrice > 0 ? p.sellPrice : 50,
        'stock': 0, // zero stock so kardex/inventory stay clean
        'presentation': p.presentation,
        'content': p.content,
        // Si la foto es un resultado previo (URL, sin XFile), pásala al temp
        // para que enhance opere sobre ella (como en "Editar Producto").
        if (usePhoto && picked == null && p.photoUrl != null &&
            p.photoUrl!.isNotEmpty)
          'image_url': p.photoUrl,
      });

      Map<String, dynamic> result;
      try {
        // Spec 013: pass the picked XFile — `uploadProductPhoto` reads
        // its bytes and normalizes to PNG, so this works on web.
        if (usePhoto) {
          if (picked != null) {
            await api.uploadProductPhoto(tempUuid, picked);
          }
          result = await api.enhanceProductPhoto(
            tempUuid,
            name: p.name,
            presentation: p.presentation,
            content: p.content,
            mode: mode,
          );
        } else {
          result = await api.generateProductImage(
            tempUuid,
            name: p.name,
            presentation: p.presentation,
            content: p.content,
            barcode: p.barcode,
          );
        }
      } finally {
        // Always clean up the temp product — fire-and-forget
        api.deleteProduct(tempUuid).catchError((_) => null);
      }
      if (!mounted) return;
      final url = result['photo_url'] as String? ?? result['image_url'] as String?;
      setState(() {
        p.photoUrl = url;
        p.photoFile = null;
        p.enhancing = false;
      });
    } on ImageNormalizationException catch (e) {
      // The picked photo could not be normalized — show the Spanish
      // message directly, not a raw exception string.
      if (!mounted) return;
      setState(() => p.enhancing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message, style: const TextStyle(fontSize: 14)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => p.enhancing = false);
      // Spec 015 / FR-04: never leak the raw type
      // (AppError(AppErrorType.x): ...) to a tendero 50+. AppError already
      // carries a clean Spanish message; use it.
      final message = e is AppError
          ? e.message
          : 'No pudimos procesar la imagen con IA. Intente de nuevo.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
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
    final barcodeCtrl = TextEditingController(text: p.barcode);
    final contentCtrl = TextEditingController(text: p.content);
    final qtyCtrl = TextEditingController(text: p.quantity.toString());
    final buyCtrl = TextEditingController(text: p.purchasePrice.round().toString());
    final sellCtrl = TextEditingController(text: p.sellPrice.round().toString());
    DateTime? draftExpiry = p.expiryDate;
    XFile? draftPhotoFile = p.photoFile;
    String? draftPhotoUrl = p.photoUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: StatefulBuilder(
            builder: (sbCtx, sbSet) => SingleChildScrollView(
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

                  // ── Photo section ──
                  Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 80, height: 80,
                          color: AppTheme.surfaceGrey,
                          child: _editThumb(draftPhotoFile, draftPhotoUrl),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _editPhotoBtn(
                                  icon: Icons.camera_alt_rounded,
                                  label: 'Foto',
                                  color: AppTheme.primary,
                                  onTap: () async {
                                    final picked = await ImagePicker().pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 85, maxWidth: 1024,
                                    );
                                    if (picked == null) return;
                                    sbSet(() {
                                      draftPhotoFile = picked;
                                      draftPhotoUrl = null;
                                    });
                                  },
                                ),
                                const SizedBox(width: 6),
                                _editPhotoBtn(
                                  icon: Icons.photo_library_rounded,
                                  label: 'Galeria',
                                  color: const Color(0xFF6D28D9),
                                  onTap: () async {
                                    final picked = await ImagePicker().pickImage(
                                      source: ImageSource.gallery,
                                      imageQuality: 85, maxWidth: 1024,
                                    );
                                    if (picked == null) return;
                                    sbSet(() {
                                      draftPhotoFile = picked;
                                      draftPhotoUrl = null;
                                    });
                                  },
                                ),
                                const SizedBox(width: 6),
                                _editPhotoBtn(
                                  icon: Icons.auto_awesome_rounded,
                                  label: 'IA',
                                  color: const Color(0xFF7C3AED),
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _enhanceOrGenerateFor(index);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Name ──
                  _EditField(label: 'Nombre del producto', controller: nameCtrl),
                  const SizedBox(height: 12),

                  // ── Barcode ──
                  _EditField(label: 'Codigo SKU / Barras', controller: barcodeCtrl,
                      hint: 'Ej: 7702535011119'),
                  const SizedBox(height: 12),

                  // ── Presentation ──
                  _EditField(label: 'Presentacion', controller: presCtrl,
                      hint: 'Ej: Botella, Lata, Bolsa'),
                  const SizedBox(height: 12),

                  // ── Content ──
                  _EditField(label: 'Contenido', controller: contentCtrl,
                      hint: 'Ej: 350ml, 500g, 1L'),
                  const SizedBox(height: 12),

                  // ── Prices ──
                  Row(
                    children: [
                      Expanded(child: _EditField(
                          label: 'P. Compra', controller: buyCtrl,
                          numeric: true, isCurrency: true, prefix: '\$')),
                      const SizedBox(width: 12),
                      Expanded(child: _EditField(
                          label: 'P. Venta', controller: sellCtrl,
                          numeric: true, isCurrency: true, prefix: '\$')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sugerido: \$${suggestPrice(CurrencyUtils.parseToDouble(buyCtrl.text), _marginPercent)} (+${_marginPercent.round()}%)',
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.success,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  // ── Quantity ──
                  _EditField(label: 'Cantidad', controller: qtyCtrl,
                      numeric: true),
                  const SizedBox(height: 14),

                  // ── Expiry date ──
                  const Text('Fecha de vencimiento',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  InkWell(
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
                                    ? FontWeight.w600 : FontWeight.w400,
                                fontStyle: draftExpiry != null
                                    ? FontStyle.normal : FontStyle.italic,
                                color: draftExpiry != null
                                    ? AppTheme.textPrimary
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ),
                          if (draftExpiry != null)
                            IconButton(
                              onPressed: () => sbSet(() => draftExpiry = null),
                              icon: const Icon(Icons.close_rounded,
                                  size: 22, color: AppTheme.textSecondary),
                              tooltip: 'Quitar fecha',
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Save button ──
                  SizedBox(
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          p.name = nameCtrl.text.trim();
                          p.presentation = presCtrl.text.trim();
                          p.barcode = barcodeCtrl.text.trim();
                          p.content = contentCtrl.text.trim();
                          p.quantity = int.tryParse(qtyCtrl.text) ?? p.quantity;
                          p.purchasePrice = CurrencyUtils.parseToDouble(buyCtrl.text);
                          p.sellPrice = CurrencyUtils.parseToDouble(sellCtrl.text);
                          p.expiryDate = draftExpiry;
                          p.photoFile = draftPhotoFile;
                          p.photoUrl = draftPhotoUrl;
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
      ),
    );
  }

  Widget _editThumb(XFile? photoFile, String? photoUrl) {
    if (photoFile != null) {
      // Spec 013: cross-platform preview of the just-picked image.
      return PickedImagePreview(
        file: photoFile,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_outlined, size: 28,
            color: AppTheme.textSecondary),
      );
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Image.network(photoUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined, size: 28, color: AppTheme.textSecondary));
    }
    return const Center(
        child: Icon(Icons.add_a_photo_rounded, size: 28,
            color: AppTheme.textSecondary));
  }

  Widget _editPhotoBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                      onToggleMatch: (useExisting) {
                        setState(() => _products[i].useExisting = useExisting);
                      },
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
  final ValueChanged<bool> onToggleMatch;

  const _ProductCard({
    required this.product,
    required this.marginPercent,
    required this.formatCOP,
    required this.onEdit,
    required this.onDelete,
    required this.onTakePhoto,
    required this.onPickGallery,
    required this.onEnhance,
    required this.onToggleMatch,
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
          // Match banner
          if (product.matchedProduct != null) _buildMatchBanner(),
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

  Widget _buildMatchBanner() {
    final match = product.matchedProduct!;
    final decided = product.useExisting;
    // Amber when undecided (null), green when accepted
    final bannerColor = decided ? AppTheme.success : const Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bannerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_rounded, size: 16, color: bannerColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ya existe: "${match.name}" (stock: ${match.stock})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: bannerColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _bannerAction(
                  label: 'Sumar al existente',
                  icon: Icons.add_circle_outline_rounded,
                  active: decided,
                  color: AppTheme.success,
                  onTap: () => onToggleMatch(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _bannerAction(
                  label: 'Crear nuevo',
                  icon: Icons.fiber_new_rounded,
                  active: !decided,
                  color: AppTheme.textSecondary,
                  onTap: () => onToggleMatch(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerAction({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color : AppTheme.borderColor,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: active ? color : AppTheme.textSecondary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? color : AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb() {
    if (product.enhancing) {
      return const Center(
          child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    if (product.photoFile != null) {
      // Spec 013: cross-platform preview of the just-picked image.
      return PickedImagePreview(
        file: product.photoFile!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_outlined, size: 28,
            color: AppTheme.textSecondary),
      );
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
  final bool isCurrency;
  final String? prefix;
  final String? hint;

  const _EditField({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.isCurrency = false,
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
          inputFormatters: isCurrency
              ? const [CurrencyInputFormatter()]
              : (numeric ? [FilteringTextInputFormatter.digitsOnly] : null),
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
  String barcode;
  String content;
  int quantity;
  double purchasePrice;
  double sellPrice;
  double confidence;
  DateTime? expiryDate;
  // Spec 013: the picked image as an XFile (not a path string) so the
  // preview and upload work cross-platform — on web `XFile.path` is a
  // blob URL, unusable by `dart:io File`.
  XFile? photoFile;
  String? photoUrl;
  bool enhancing;

  /// Backend match info from ScanInvoice response
  String? matchProductId;
  /// Matched existing product from local catalog (null = no match found)
  LocalProduct? matchedProduct;
  double matchScore;
  String matchMethod; // "barcode", "normalized", "fuzzy", ""
  /// User decision: true = merge into existing, false = create new
  bool useExisting;

  _EditableProduct({
    required this.name,
    required this.presentation,
    required this.quantity,
    required this.purchasePrice,
    required this.sellPrice,
    required this.confidence,
    this.barcode = '',
    this.content = '',
    this.expiryDate,
    // Stable API: fields are mutated post-construction (e.g. p.photoFile
    // = picked) but exposing them as optional ctor params keeps the
    // class extensible without forcing a breaking change.
    // ignore: unused_element_parameter
    this.photoFile,
    this.photoUrl,
    // ignore: unused_element_parameter
    this.enhancing = false,
    this.matchProductId,
    // ignore: unused_element_parameter
    this.matchedProduct,
    // ignore: unused_element_parameter
    this.matchScore = 0.0,
    this.matchMethod = '',
    this.useExisting = false,
  });

  bool get hasPhoto =>
      photoFile != null || (photoUrl != null && photoUrl!.isNotEmpty);
}
