// Spec: specs/095-variantes-producto/spec.md
//
// Crear un grupo de variantes (talla/color) y generar todas sus
// combinaciones de una vez. Solo visible cuando el tenant activó
// "Variantes de producto" en Capacidades del negocio (AC-01: con la
// capacidad OFF esta pantalla ni siquiera es alcanzable).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/currency_input.dart';
import '../../widgets/product_variant_builder.dart';

class CreateVariantGroupScreen extends StatefulWidget {
  const CreateVariantGroupScreen({super.key, this.apiOverride});

  final ApiService? apiOverride;

  @override
  State<CreateVariantGroupScreen> createState() =>
      _CreateVariantGroupScreenState();
}

class _CreateVariantGroupScreenState extends State<CreateVariantGroupScreen> {
  late final ApiService _api = widget.apiOverride ?? ApiService(AuthService());
  final _groupNameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _groupNameCtrl.dispose();
    _categoryCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate(Map<String, List<String>> attributes) async {
    final name = _groupNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Ponle un nombre al grupo (ej. "Camiseta Básica")',
          isError: true);
      return;
    }
    final price = CurrencyUtils.parseToDouble(_priceCtrl.text);
    if (price <= 0) {
      _showSnack('El precio debe ser mayor a 0', isError: true);
      return;
    }
    try {
      final group = await _api.createVariantGroup({
        'name': name,
        'category': _categoryCtrl.text.trim(),
        'attribute_labels': attributes.keys.toList(),
      });
      final groupId = group['id'] as String? ?? group['data']?['id'] as String?;
      final created = await _api.generateVariantCombinations(groupId ?? '', {
        'attributes': attributes,
        'base_price': price,
        'base_stock': int.tryParse(_stockCtrl.text.trim()) ?? 0,
      });
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      _showSnack('${created.length} variantes creadas');
      Navigator.of(context).pop(true);
    } on AppError catch (e) {
      _showSnack('No se pudo crear: ${e.message}', isError: true);
    } catch (_) {
      _showSnack('No se pudo crear: revise su conexión e intente de nuevo.',
          isError: true);
    }
  }

  void _showSnack(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 15)),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        title: const Text('Producto con variantes', style: AppUI.title),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppUI.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('variant_group_name'),
              controller: _groupNameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nombre del producto',
                  hintText: 'Camiseta Básica'),
            ),
            const SizedBox(height: AppUI.s16),
            TextField(
              key: const Key('variant_group_category'),
              controller: _categoryCtrl,
              decoration: const InputDecoration(
                  labelText: 'Categoría (opcional)', hintText: 'Ropa'),
            ),
            const SizedBox(height: AppUI.s16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('variant_group_price'),
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Precio'),
                  ),
                ),
                const SizedBox(width: AppUI.s16),
                Expanded(
                  child: TextField(
                    key: const Key('variant_group_stock'),
                    controller: _stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Stock inicial (c/u)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppUI.s24),
            ProductVariantBuilder(
              groupNameController: _groupNameCtrl,
              basePriceController: _priceCtrl,
              baseStockController: _stockCtrl,
              onGenerate: _generate,
            ),
          ],
        ),
      ),
    );
  }
}
