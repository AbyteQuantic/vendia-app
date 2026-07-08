// Spec: specs/100-completar-skus-inventario/spec.md
//
// Vista dedicada "Completar SKUs" (patrón de Spec 097 "Completar fotos"):
// recibe la lista YA prefiltrada de referencias físicas sin código y ofrece
// por tarjeta las acciones justas — Escanear / Generar / Digitar — hasta
// vaciar la lista. La detección de duplicados nunca asigna en silencio.

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_ui.dart';

class SkuCompletionScreen extends StatefulWidget {
  const SkuCompletionScreen({
    super.key,
    required this.products,
    @visibleForTesting this.apiOverride,
  });

  /// Referencias físicas SIN código (mapas crudos del backend).
  final List<Map<String, dynamic>> products;

  @visibleForTesting
  final ApiService? apiOverride;

  @override
  State<SkuCompletionScreen> createState() => _SkuCompletionScreenState();
}

class _SkuCompletionScreenState extends State<SkuCompletionScreen> {
  late final ApiService _api;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Completar SKUs'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.products.length,
        itemBuilder: (_, i) => Text(
          (widget.products[i]['name'] ?? '').toString(),
          style: AppUI.bodyStrong,
        ),
      ),
    );
  }
}
