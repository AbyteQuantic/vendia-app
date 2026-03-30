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

/// Manual product creation form with photo, barcode, and price fields.
class CreateProductScreen extends StatefulWidget {
  const CreateProductScreen({super.key});

  @override
  State<CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends State<CreateProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _buyPriceCtrl = TextEditingController();
  final _sellPriceCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '1');

  String? _photoPath;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _buyPriceCtrl.dispose();
    _sellPriceCtrl.dispose();
    _quantityCtrl.dispose();
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
      setState(() => _photoPath = photo.path);
    }
  }

  Future<void> _scanBarcode() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    try {
      final id = const Uuid().v4();
      final name = _nameCtrl.text.trim();
      final price = double.tryParse(_sellPriceCtrl.text.trim()) ?? 0;
      final stock = int.tryParse(_quantityCtrl.text.trim()) ?? 1;

      // Guardar en backend (PostgreSQL/Supabase)
      final api = ApiService(AuthService());
      await api.createProduct({
        'id': id,
        'name': name,
        'price': price,
        'stock': stock,
      });

      // Guardar en DB local (Isar) para offline
      final product = LocalProduct()
        ..uuid = id
        ..name = name
        ..price = price
        ..stock = stock
        ..imageUrl = _photoPath
        ..isAvailable = true
        ..requiresContainer = false
        ..containerPrice = 0
        ..clientUpdatedAt = DateTime.now();
      await DatabaseService.instance.upsertProduct(product);
    } catch (_) {
      // Best effort save
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
                'Producto "${_nameCtrl.text.trim()}" guardado',
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

  @override
  Widget build(BuildContext context) {
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
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Formulario de nuevo producto',
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Photo placeholder
                  GestureDetector(
                    onTap: _takePhoto,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: _photoPath == null
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFF6B6B),
                                  Color(0xFFE05252),
                                ],
                              )
                            : null,
                        image: _photoPath != null
                            ? DecorationImage(
                                image: FileImage(File(_photoPath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _photoPath == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  '\uD83E\uDD5F', // dumpling emoji
                                  style: TextStyle(fontSize: 48),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _nameCtrl.text.isEmpty
                                      ? 'Producto'
                                      : _nameCtrl.text,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Take photo button
                  TextButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt_rounded, size: 20),
                    label: const Text('Tomar foto'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF667EEA),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Scan barcode button
                  SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner_rounded,
                          size: 24, color: Color(0xFF667EEA)),
                      label: const Text(
                        'Escanear Codigo de Barras',
                        style: TextStyle(color: Color(0xFF667EEA)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFF667EEA), width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Product name
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nombre del producto',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _nameCtrl,
                        style: const TextStyle(fontSize: 20),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Ej: Coca-Cola 350ml',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.italic,
                          ),
                          prefixIcon: const Icon(Icons.inventory_2_rounded,
                              color: AppTheme.primary, size: 26),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Ingrese el nombre';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Prices side by side
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Precio compra',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _buyPriceCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 20),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                hintText: '\$0',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w400,
                                ),
                                prefixIcon: const Icon(Icons.attach_money_rounded,
                                    color: AppTheme.textSecondary, size: 24),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Requerido';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Precio venta',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _sellPriceCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                fontSize: 20,
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                hintText: '\$0',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w400,
                                ),
                                prefixIcon: const Icon(Icons.attach_money_rounded,
                                    color: Color(0xFF10B981), size: 24),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Requerido';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Quantity
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cantidad',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _quantityCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 20),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: '1',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w400,
                          ),
                          prefixIcon: const Icon(Icons.numbers_rounded,
                              color: AppTheme.primary, size: 26),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          if (int.tryParse(v) == null || int.parse(v) < 1) {
                            return 'Minimo 1';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667EEA)
                                .withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Icon(Icons.save_rounded,
                                size: 24, color: Colors.white),
                        label: Text(
                          _saving ? 'Guardando...' : 'Guardar producto',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size(double.infinity, 64),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
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
}
