// Spec: specs/068-categorias-caracteristicas-producto/spec.md
//
// Bloque compartido "Opciones avanzadas" del producto, montado IGUAL por crear
// y editar (paridad por construcción). Dos campos:
//   · Categoría con AUTOCOMPLETE: sugiere las categorías que el tenant ya usó
//     (chips) → evita typos y NO fragmenta/pierde las existentes (Spec 068).
//   · Características: texto libre multilínea que el cliente verá en el detalle
//     del catálogo en línea.
// Solo presentación: los controllers y el guardado los maneja el formulario.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/text_normalize.dart';

class AdvancedProductOptions extends StatefulWidget {
  final TextEditingController categoryController;
  final TextEditingController characteristicsController;

  /// Categorías que el tenant ya usó (de GET /products/categories, con fallback
  /// local). Se ofrecen como chips; tocar una pega el texto EXACTO existente.
  final List<String> categorySuggestions;

  const AdvancedProductOptions({
    super.key,
    required this.categoryController,
    required this.characteristicsController,
    this.categorySuggestions = const [],
  });

  @override
  State<AdvancedProductOptions> createState() => _AdvancedProductOptionsState();
}

class _AdvancedProductOptionsState extends State<AdvancedProductOptions> {
  // Normaliza para COMPARAR (insensible a mayúsculas/tildes/espacios), nunca
  // para mutar lo guardado. Usa la clave compartida foldKey.
  String _norm(String s) => foldKey(s);

  /// Sugerencias filtradas por lo que va escribiendo, deduplicadas, máx. 8.
  /// Esconde la que ya coincide exactamente (no tiene sentido re-sugerirla).
  List<String> get _filtered {
    final q = _norm(widget.categoryController.text);
    final seen = <String>{};
    final out = <String>[];
    for (final raw in widget.categorySuggestions) {
      final c = raw.trim();
      final n = _norm(c);
      if (n.isEmpty || seen.contains(n)) continue;
      seen.add(n);
      if (q.isEmpty || (n.contains(q) && n != q)) out.add(c);
      if (out.length >= 8) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Categoría',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Organiza su catálogo y deja que sus clientes filtren en línea.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('product_category_field'),
          controller: widget.categoryController,
          style: const TextStyle(fontSize: 18),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ej: Gaseosas, Aseo, Granos',
            prefixIcon:
                const Icon(Icons.category_rounded, color: AppTheme.textSecondary),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        if (filtered.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < filtered.length; i++)
                ActionChip(
                  key: Key('category_suggestion_$i'),
                  label: Text(filtered[i]),
                  avatar: const Icon(Icons.add_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    widget.categoryController.text = filtered[i];
                    widget.categoryController.selection =
                        TextSelection.collapsed(offset: filtered[i].length);
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        const Text('Características (opcional)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Detalles que el cliente verá en el detalle del producto en línea.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('product_characteristics_field'),
          controller: widget.characteristicsController,
          style: const TextStyle(fontSize: 17),
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Ej: Sin azúcar · Marca Nacional · Picante medio',
            alignLabelWithHint: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}
