// Spec: specs/100-completar-skus-inventario/spec.md
//
// Piezas de bottom-sheet del flujo "Completar SKUs", extraídas de la
// pantalla (Art. IX: archivos < 800 líneas). Solo presentación + validación
// de entrada del campo; la asignación del código sigue viviendo en la
// pantalla dueña del estado.

import 'package:flutter/material.dart';

import '../theme/app_ui.dart';

/// Manija centrada del bottom-sheet (patrón de modal del design system).
Widget sheetHandle() {
  return Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: AppUI.s12),
      decoration: BoxDecoration(
        color: AppUI.border,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// Hoja para digitar el código a mano. Es un StatefulWidget propio para que
/// el TextEditingController viva y muera con la hoja (disponerlo desde la
/// pantalla rompía el frame de cierre de la animación del bottom sheet).
class SkuManualCodeSheet extends StatefulWidget {
  const SkuManualCodeSheet({super.key, required this.productName, this.prefill});
  final String productName;
  final String? prefill;

  @override
  State<SkuManualCodeSheet> createState() => _SkuManualCodeSheetState();
}

class _SkuManualCodeSheetState extends State<SkuManualCodeSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.prefill ?? '');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Valida el código digitado (longitud/caracteres — NFR de seguridad) y
  /// cierra la hoja devolviéndolo, o pinta el error en el campo.
  void _submit() {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return setState(() => _error = 'Digite el código.');
    if (code.length < 4) {
      return setState(
          () => _error = 'Código muy corto (mínimo 4 caracteres).');
    }
    if (!RegExp(r'^[A-Za-z0-9\-]+$').hasMatch(code)) {
      return setState(() => _error = 'Use solo letras, números y guiones.');
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetHandle(),
            Text('Código para "${widget.productName}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppUI.title),
            const SizedBox(height: AppUI.s16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 20, letterSpacing: 1),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Digite el código de barras…',
                hintStyle: const TextStyle(fontSize: 17, color: AppUI.inkSoft),
                errorText: _error,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppUI.radius),
                    borderSide: const BorderSide(color: AppUI.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppUI.radius),
                    borderSide: const BorderSide(color: AppUI.border)),
              ),
            ),
            const SizedBox(height: AppUI.s12),
            AppButton(label: 'Guardar', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
