// Spec: specs/043-menu-restaurante-recetas/spec.md
//
// Editor de "Importar menú desde la cámara" (F043, Fase 2). Recibe los platos
// que la IA leyó de la foto de la carta (nombre, descripción, precio, porción,
// categoría) y deja que el tendero los revise/edite/elimine antes de
// publicarlos. Al guardar, cada plato se crea como Product con
// is_menu_item=true → alimenta la sección "Menú restaurante" del catálogo
// público (Fase 3). Todo editable (Art. I: cero fricción, tenderos 50+).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_input.dart';

/// Categorías sugeridas por la IA (spec §6, decisión 5). Texto libre permitido
/// pero el selector ofrece estas para no obligar a teclear.
const List<String> kMenuCategories = [
  'Entradas',
  'Platos fuertes',
  'Bebidas',
  'Postres',
  'Adiciones',
  'Otros',
];

/// Procedencia de la foto del plato. Distingue una ILUSTRACIÓN de muestra
/// generada por IA desde el nombre (sample) de la FOTO REAL del plato subida
/// por el tendero (real, mejorada o no). El catálogo público etiqueta la
/// muestra para no engañar al comensal (F043). `none` = aún sin foto.
enum DishImageKind { none, sample, real }

/// Un plato editable en memoria. Mutable a propósito: es estado local de un
/// formulario, no un modelo de dominio (Art. de inmutabilidad aplica a datos
/// compartidos, no a controladores de un editor efímero).
class EditableDish {
  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController price;
  final TextEditingController portion;
  String category;

  /// URL de la foto (muestra IA o real). Vive en memoria hasta "Publicar",
  /// donde se incluye en createProduct — nunca se crea un producto antes
  /// (concilio opción C: sin productos fantasma, sin perder ediciones).
  String? imageUrl;

  /// Procedencia de [imageUrl]. Gobierna el badge y si "Mejorar con IA" es
  /// alcanzable (solo sobre foto real, nunca sobre una muestra).
  DishImageKind imageKind = DishImageKind.none;

  /// La foto real ya pasó por la mejora fiel con IA (estado F). Solo aplica
  /// cuando [imageKind] == real.
  bool photoEnhanced = false;

  EditableDish({
    required String name,
    required String description,
    required int price,
    required String portion,
    required this.category,
  })  : name = TextEditingController(text: name),
        description = TextEditingController(text: description),
        price = TextEditingController(text: price > 0 ? price.toString() : ''),
        portion = TextEditingController(text: portion);

  factory EditableDish.fromScan(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final price = rawPrice is num ? rawPrice.round() : 0;
    final cat = (json['category'] as String?)?.trim();
    return EditableDish(
      name: (json['name'] as String?)?.trim() ?? '',
      description: (json['description'] as String?)?.trim() ?? '',
      price: price,
      portion: (json['portion'] as String?)?.trim() ?? '',
      category: (cat != null && cat.isNotEmpty) ? cat : 'Platos fuertes',
    );
  }

  factory EditableDish.empty() => EditableDish(
        name: '',
        description: '',
        price: 0,
        portion: '',
        category: 'Platos fuertes',
      );

  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    portion.dispose();
  }

  bool get isValid => name.text.trim().length >= 2;

  Map<String, dynamic> toCreatePayload() {
    final priceVal = int.tryParse(price.text.replaceAll('.', '').trim()) ?? 0;
    final data = <String, dynamic>{
      'name': name.text.trim(),
      'price': priceVal,
      'stock': 0, // los platos del menú no llevan inventario por unidad
      'category': category,
      'is_menu_item': true,
    };
    final desc = description.text.trim();
    if (desc.isNotEmpty) data['description'] = desc;
    final port = portion.text.trim();
    if (port.isNotEmpty) data['portion'] = port;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      data['image_url'] = imageUrl;
      // Provenance al catálogo público: una muestra IA se etiqueta como tal
      // para no engañar al comensal; una foto real (mejorada o no) no.
      data['photo_is_sample'] = imageKind == DishImageKind.sample;
    }
    return data;
  }
}

class MenuImportScreen extends StatefulWidget {
  /// Platos crudos devueltos por `POST /menu/scan-photo`.
  final List<Map<String, dynamic>> scannedDishes;

  /// Inyectable para tests; en producción usa el ApiService default.
  final ApiService? apiOverride;

  const MenuImportScreen({
    super.key,
    required this.scannedDishes,
    this.apiOverride,
  });

  @override
  State<MenuImportScreen> createState() => _MenuImportScreenState();
}

class _MenuImportScreenState extends State<MenuImportScreen> {
  late final List<EditableDish> _dishes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dishes = widget.scannedDishes.map(EditableDish.fromScan).toList();
    if (_dishes.isEmpty) _dishes.add(EditableDish.empty());
  }

  @override
  void dispose() {
    for (final d in _dishes) {
      d.dispose();
    }
    super.dispose();
  }

  void _addDish() {
    HapticFeedback.lightImpact();
    setState(() => _dishes.add(EditableDish.empty()));
  }

  void _removeDish(int index) {
    HapticFeedback.lightImpact();
    final removed = _dishes.removeAt(index);
    setState(() {});
    removed.dispose();
  }

  Future<void> _saveAll() async {
    final valid = _dishes.where((d) => d.isValid).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escribe al menos el nombre de un plato (mínimo 2 letras) para '
            'guardar tu menú.',
            style: TextStyle(fontSize: 15),
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final api = widget.apiOverride ?? ApiService(AuthService());
    var created = 0;
    final errors = <String>[];

    for (final dish in valid) {
      try {
        await api.createProduct(dish.toCreatePayload());
        created++;
      } on AppError catch (e) {
        errors.add('${dish.name.text.trim()}: ${e.message}');
      } catch (e) {
        errors.add('${dish.name.text.trim()}: $e');
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (created > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errors.isEmpty
                ? '¡Listo! Guardamos $created plato(s) en tu menú. Ya aparecen '
                    'en tu catálogo en línea.'
                : 'Guardamos $created plato(s). ${errors.length} no se '
                    'pudieron guardar.',
            style: const TextStyle(fontSize: 15),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No pudimos guardar tu menú. ${errors.isNotEmpty ? errors.first : 'Intenta de nuevo.'}',
            style: const TextStyle(fontSize: 15),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Revisa tu menú'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'La IA leyó ${_dishes.length} plato(s) de tu carta. Revisa el '
              'nombre, precio y descripción — puedes editar, agregar o quitar '
              'lo que quieras antes de publicarlo.',
              style: const TextStyle(
                  fontSize: 14, color: Colors.black54, height: 1.3),
            ),
          ),
          Expanded(
            child: ListView.separated(
              key: const Key('menu_import_list'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              itemCount: _dishes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _DishCard(
                key: ValueKey(_dishes[i]),
                dish: _dishes[i],
                index: i,
                api: widget.apiOverride,
                onRemove: () => _removeDish(i),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _saving
          ? null
          : FloatingActionButton.extended(
              key: const Key('menu_import_add'),
              heroTag: 'menu_add',
              onPressed: _addDish,
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primary,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar plato'),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            key: const Key('menu_import_save'),
            onPressed: _saving ? null : _saveAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _saving ? 'Guardando…' : 'Publicar en mi menú',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _DishCard extends StatefulWidget {
  final EditableDish dish;
  final int index;
  final VoidCallback onRemove;
  final ApiService? api;

  const _DishCard({
    super.key,
    required this.dish,
    required this.index,
    required this.onRemove,
    this.api,
  });

  @override
  State<_DishCard> createState() => _DishCardState();
}

class _DishCardState extends State<_DishCard> {
  bool _generatingDesc = false;
  bool _generatingSample = false; // estado B: creando muestra IA (name-based)
  bool _enhancingPhoto = false; // estado C: mejorando la foto real subida

  static const Color _purple = Color(0xFF7C3AED);

  void _snackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: AppTheme.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _snackInfo(String msg, {Color color = AppTheme.warning}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  bool get _busy => _generatingSample || _enhancingPhoto;

  /// Genera una FOTO de MUESTRA del plato con IA (concilio op. C): no crea
  /// producto. La muestra se basa en nombre + descripción (ingredientes) +
  /// presentación (cómo se sirve) → mucho más certera. Antes de generar
  /// pregunta la presentación de forma OPCIONAL (se puede omitir).
  Future<void> _generateSample() async {
    if (_busy) return; // dedupe doble-tap
    final d = widget.dish;
    final name = d.name.text.trim();
    if (name.length < 2) {
      _snackError('Escriba primero el nombre del plato.');
      return;
    }
    final presentation = await _askPresentation();
    // null = el tendero cerró la hoja sin decidir → no generamos.
    if (!mounted || presentation == null) return;

    setState(() => _generatingSample = true);
    try {
      final api = widget.api ?? ApiService(AuthService());
      final url = await api.generateMenuImage(
        name: name,
        category: d.category,
        description: d.description.text.trim(),
        presentation: presentation,
      );
      if (!mounted) return;
      if (url.isNotEmpty) {
        setState(() {
          d.imageUrl = url;
          d.imageKind = DishImageKind.sample;
          d.photoEnhanced = false;
        });
      } else {
        _snackError('No pudimos crear la foto. Intente de nuevo.');
      }
    } on AppError catch (e) {
      _snackError(e.message);
    } catch (_) {
      _snackError('No pudimos crear la foto. Intente de nuevo.');
    } finally {
      if (mounted) setState(() => _generatingSample = false);
    }
  }

  /// Sube la foto REAL del plato (cámara o galería) y la mejora con IA de
  /// forma FIEL (recorta fondo + luz de estudio, sin redibujar). Web-safe:
  /// usa bytes (`readAsBytes`), nunca `XFile.path`. Si la mejora falla, se
  /// conserva la foto real subida SIN mejorar (nunca se pierde lo del tendero).
  Future<void> _pickAndEnhance(ImageSource source) async {
    if (_busy) return;
    final d = widget.dish;
    final name = d.name.text.trim();
    if (name.length < 2) {
      _snackError('Escriba primero el nombre del plato.');
      return;
    }
    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.lengthInBytes > 8 * 1024 * 1024) {
      _snackInfo('La foto es muy pesada, intente con otra');
      return;
    }

    setState(() => _enhancingPhoto = true);
    try {
      final api = widget.api ?? ApiService(AuthService());
      final url = await api.enhanceMenuImage(
        imageBytes: bytes,
        name: name,
        category: d.category,
        mimeType: picked.mimeType ?? 'image/jpeg',
        filename: picked.name.isNotEmpty ? picked.name : 'plato.jpg',
      );
      if (!mounted) return;
      if (url.isNotEmpty) {
        setState(() {
          d.imageUrl = url;
          d.imageKind = DishImageKind.real;
          d.photoEnhanced = true;
        });
      } else {
        _snackError('No pudimos mejorar la foto. Intente de nuevo.');
      }
    } on AppError catch (e) {
      // La foto real ya está en manos del tendero; la mejora es best-effort.
      // No se pierde nada: queda el plato sin foto mejorada y se avisa.
      _snackInfo('No pudimos mejorar la foto, pero puede intentar de nuevo. '
          '($e)');
    } catch (_) {
      _snackInfo('No pudimos mejorar la foto, pero puede intentar de nuevo.');
    } finally {
      if (mounted) setState(() => _enhancingPhoto = false);
    }
  }

  /// Pregunta OPCIONAL por cómo se sirve el plato, para que la muestra IA sea
  /// más certera. Devuelve '' si el tendero omite la presentación, o `null` si
  /// cierra la hoja sin decidir (en cuyo caso no se genera nada).
  Future<String?> _askPresentation() async {
    final controller = TextEditingController();
    const styles = ['En plato', 'Para llevar', 'En vaso', 'En bandeja'];
    // Acompañamientos típicos para que la muestra IA se parezca al plato real
    // (un corrientazo: sopa, arroz, proteína, acompañamientos, jugo).
    const sides = [
      'Sopa', 'Arroz', 'Plátano maduro', 'Papa a la francesa',
      'Ensalada', 'Aguacate', 'Arepa', 'Frijoles', 'Jugo',
    ];
    String style = '';
    final selectedSides = <String>{};
    final apartSides = <String>{}; // acompañamientos que van en plato APARTE

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('¿Cómo se sirve el plato? (opcional)',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Entre más detalle, más parecida queda la muestra.',
                    style: TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: styles
                      .map((c) => ChoiceChip(
                            label: Text(c, style: const TextStyle(fontSize: 15)),
                            selected: style == c,
                            backgroundColor: AppTheme.surfaceGrey,
                            selectedColor: _purple.withValues(alpha: 0.18),
                            onSelected: (_) => setSheet(() => style = style == c ? '' : c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 18),
                const Text('¿Con qué acompañamientos?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('Escoja los que trae el plato.',
                    style: TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sides
                      .map((c) => FilterChip(
                            label: Text(c, style: const TextStyle(fontSize: 15)),
                            selected: selectedSides.contains(c),
                            backgroundColor: AppTheme.surfaceGrey,
                            selectedColor: _purple.withValues(alpha: 0.18),
                            checkmarkColor: _purple,
                            onSelected: (sel) => setSheet(() {
                              if (sel) {
                                selectedSides.add(c);
                              } else {
                                selectedSides.remove(c);
                                apartSides.remove(c); // limpiar si se deselecciona
                              }
                            }),
                          ))
                      .toList(),
                ),
                // ¿Cuáles van en plato aparte? (sopa/jugo casi siempre) — para que
                // la muestra IA salga realista: incluido vs aparte.
                if (selectedSides.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('¿Alguno va en plato aparte?',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Toque los que NO van sobre el plato principal (ej: sopa, jugo).',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedSides
                        .map((c) => FilterChip(
                              label: Text(c, style: const TextStyle(fontSize: 15)),
                              selected: apartSides.contains(c),
                              avatar: apartSides.contains(c)
                                  ? const Icon(Icons.call_split_rounded, size: 16, color: _purple)
                                  : null,
                              backgroundColor: AppTheme.surfaceGrey,
                              selectedColor: _purple.withValues(alpha: 0.18),
                              showCheckmark: false,
                              onSelected: (sel) => setSheet(() =>
                                  sel ? apartSides.add(c) : apartSides.remove(c)),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Otro detalle (ej: en hoja de plátano)',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(''),
                        child: const Text('Omitir', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _purple,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(
                            _composePresentation(style, selectedSides, apartSides, controller.text.trim())),
                        child: const Text('Crear foto', style: TextStyle(fontSize: 16)),
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
    controller.dispose();
    return result;
  }

  /// Compone la presentación para el prompt de IA: estilo + acompañamientos
  /// (distinguiendo los que van EN EL MISMO PLATO de los que van APARTE) +
  /// detalle libre. Ej: "En plato, con arroz y frijoles en el mismo plato,
  /// sopa y jugo en plato aparte".
  String _composePresentation(
      String style, Set<String> sides, Set<String> apart, String extra) {
    final parts = <String>[];
    if (style.isNotEmpty) parts.add(style);
    final enPlato =
        sides.where((s) => !apart.contains(s)).map((s) => s.toLowerCase()).toList();
    final aparte =
        sides.where((s) => apart.contains(s)).map((s) => s.toLowerCase()).toList();
    if (enPlato.isNotEmpty) parts.add('con ${enPlato.join(', ')} en el mismo plato');
    if (aparte.isNotEmpty) parts.add('${aparte.join(', ')} en plato aparte');
    if (extra.isNotEmpty) parts.add(extra);
    return parts.join(', ');
  }

  /// Genera la descripción del plato con IA a partir del nombre + categoría
  /// y la precarga en el campo (el tendero la edita). Necesita un nombre.
  Future<void> _generateDescription() async {
    final d = widget.dish;
    final name = d.name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escribe primero el nombre del plato.',
            style: TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _generatingDesc = true);
    try {
      final api = widget.api ?? ApiService(AuthService());
      final desc = await api.generateMenuDescription(
        name: name,
        category: d.category,
      );
      if (!mounted) return;
      if (desc.isNotEmpty) {
        d.description.text = desc;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos generar la descripción. Intenta de nuevo.',
              style: TextStyle(fontSize: 15)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } on AppError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message, style: const TextStyle(fontSize: 15)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos generar la descripción. Intenta de nuevo.',
              style: TextStyle(fontSize: 15)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _generatingDesc = false);
    }
  }

  /// Sección de foto del plato — máquina de 6 estados (concilio 2026-06-13):
  ///   A vacío          → [Tomar foto][Galería] + link "muestra con IA"
  ///   B creando muestra→ spinner "Creando la foto…"
  ///   C mejorando real → spinner "Mejorando su foto…"
  ///   D con muestra    → miniatura + badge "Muestra (IA)" + reemplazar + otra muestra
  ///   E con foto real  → miniatura + badge "Su foto" + reemplazar + "✨ Mejorar con IA"
  ///   F real mejorada  → miniatura + badge "Su foto" + reemplazar + "Mejorar otra vez"
  Widget _photoSection(EditableDish d) {
    if (_generatingSample) {
      return _spinnerBox('Creando la foto… esto tarda unos segundos');
    }
    if (_enhancingPhoto) {
      return _spinnerBox('Mejorando su foto… un momento');
    }
    if (d.imageKind == DishImageKind.none || d.imageUrl == null) {
      return _emptyState();
    }
    return _withPhotoState(d);
  }

  Widget _spinnerBox(String label) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child:
                CircularProgressIndicator(strokeWidth: 2.5, color: _purple),
          ),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }

  /// Estado A — sin foto. Camino PRINCIPAL: foto real (Tomar foto / Galería →
  /// mejora fiel). Plan B explícito debajo: crear una de muestra con IA.
  Widget _emptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _photoActionButton(
                key: Key('menu_dish_photo_camera_${widget.index}'),
                icon: Icons.camera_alt_rounded,
                label: 'Tomar foto',
                color: AppTheme.primary,
                onPressed: () => _pickAndEnhance(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _photoActionButton(
                key: Key('menu_dish_photo_gallery_${widget.index}'),
                icon: Icons.photo_library_rounded,
                label: 'Galería',
                color: AppTheme.success,
                onPressed: () => _pickAndEnhance(ImageSource.gallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            key: Key('menu_dish_ai_photo_${widget.index}'),
            onPressed: _generateSample,
            style: TextButton.styleFrom(foregroundColor: _purple),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('¿No tiene foto? Crear una de muestra con IA',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  /// Estados D/E/F — ya hay foto. Miniatura + badge según procedencia + fila
  /// para reemplazar por foto real + acción principal según el tipo.
  Widget _withPhotoState(EditableDish d) {
    final isSample = d.imageKind == DishImageKind.sample;
    final isReal = d.imageKind == DishImageKind.real;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(d.imageUrl!,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            width: 84,
                            height: 84,
                            color: AppTheme.surfaceGrey,
                            child: const Icon(Icons.broken_image_rounded,
                                color: Colors.black38),
                          )),
                ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isSample ? AppTheme.warning : AppTheme.success)
                          .withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(isSample ? 'Muestra (IA)' : 'Su foto',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _photoActionButton(
                          key: Key('menu_dish_photo_camera_${widget.index}'),
                          icon: Icons.camera_alt_rounded,
                          label: 'Tomar foto',
                          color: AppTheme.primary,
                          dense: true,
                          onPressed: () => _pickAndEnhance(ImageSource.camera),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _photoActionButton(
                          key: Key('menu_dish_photo_gallery_${widget.index}'),
                          icon: Icons.photo_library_rounded,
                          label: 'Galería',
                          color: AppTheme.success,
                          dense: true,
                          onPressed: () => _pickAndEnhance(ImageSource.gallery),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Acción principal según procedencia.
        if (isSample)
          TextButton.icon(
            key: Key('menu_dish_ai_photo_${widget.index}'),
            onPressed: _generateSample,
            style: TextButton.styleFrom(foregroundColor: _purple),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Otra muestra',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          )
        else if (isReal)
          OutlinedButton.icon(
            key: Key('menu_dish_enhance_${widget.index}'),
            onPressed: () => _pickAndEnhance(ImageSource.gallery),
            style: OutlinedButton.styleFrom(
              foregroundColor: _purple,
              side: const BorderSide(color: Color(0x337C3AED)),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text(d.photoEnhanced ? 'Mejorar otra vez' : '✨ Mejorar con IA',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  /// Botón de foto compacto. FittedBox para que el texto nunca desborde a
  /// 360dp (~300dp útiles, dos botones lado a lado).
  Widget _photoActionButton({
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool dense = false,
  }) {
    return SizedBox(
      height: dense ? 40 : 46,
      child: OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: dense ? 17 : 19),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: dense ? 13 : 14.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dish;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _photoSection(d),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: d.name,
                  label: 'Nombre del plato',
                  hint: 'Ej: Bandeja Paisa',
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              IconButton(
                key: Key('menu_dish_remove_${widget.index}'),
                tooltip: 'Quitar plato',
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              // Genera la descripción con IA desde el nombre del plato.
              TextButton.icon(
                key: Key('menu_dish_ai_desc_${widget.index}'),
                onPressed: _generatingDesc ? null : _generateDescription,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: _generatingDesc
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF7C3AED)),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_generatingDesc ? 'Generando…' : 'Descripción con IA',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          _Field(
            controller: d.description,
            label: 'Descripción',
            hint: 'Ingredientes o detalles (opcional)',
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: d.price,
                  label: 'Precio',
                  hint: '0',
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  prefix: '\$ ',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  controller: d.portion,
                  label: 'Porción',
                  hint: 'Ej: Personal',
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CategorySelector(
            value: d.category,
            onChanged: (v) => setState(() => d.category = v),
          ),
        ],
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CategorySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Categoría',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kMenuCategories.map((cat) {
            final selected = cat == value;
            return ChoiceChip(
              label: Text(cat),
              selected: selected,
              onSelected: (_) => onChanged(cat),
              labelStyle: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.surfaceGrey,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              side: BorderSide.none,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? prefix;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black54)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
