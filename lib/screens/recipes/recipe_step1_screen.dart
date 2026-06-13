// Spec: specs/001-insumos-recetas/spec.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'recipe_step2_screen.dart';

/// Recipe creation step 1: Photo, name, category, and price.
///
/// Feature 001: el wizard de recetas dejó de ser prototipo. Este paso
/// recoge el nombre, la categoría y el precio de venta que escribe el
/// tendero — ya no usa valores mock fijos — y los pasa al paso 2, donde
/// se eligen insumos reales (plan §5, T-24).
class RecipeStep1Screen extends StatefulWidget {
  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const RecipeStep1Screen({super.key, this.api});

  @override
  State<RecipeStep1Screen> createState() => _RecipeStep1ScreenState();
}

class _RecipeStep1ScreenState extends State<RecipeStep1Screen> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _selectedCategory = 'Comidas';
  String? _nameError;

  // F043 slice manual: foto + descripción + porción. La foto se guarda como
  // XFile (web-safe: se sube con readAsBytes, nunca con XFile.path) y sus
  // bytes para la previsualización. La porción es un atajo por chips para
  // reducir fricción (Art. I); vacía = sin porción.
  XFile? _photo;
  Uint8List? _photoBytes;
  String? _selectedPortion;

  static const List<String> _portions = [
    'Personal',
    'Para compartir',
    'Familiar',
  ];

  // Categorías por defecto del menú. No son parte del contrato de
  // Feature 001 (la receta guarda un texto libre); se ofrecen como
  // atajo para reducir fricción (Art. I).
  final List<Map<String, String>> _categories = [
    {'emoji': '\u{1F37D}️', 'name': 'Comidas'},
    {'emoji': '\u{1F32D}', 'name': 'Perros Calientes'},
    {'emoji': '\u{1F354}', 'name': 'Hamburguesas'},
    {'emoji': '\u{1F355}', 'name': 'Pizzas'},
    {'emoji': '\u{1F964}', 'name': 'Bebidas'},
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Emoji asociado a la categoría seleccionada (decorativo).
  String get _categoryEmoji => _categories.firstWhere(
        (c) => c['name'] == _selectedCategory,
        orElse: () => _categories.first,
      )['emoji']!;

  /// Convierte el texto del precio ("5.000") a un entero en COP.
  int _parsePrice() {
    final raw = _priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(raw) ?? 0;
  }

  /// Toma o escoge la foto del plato. Web-safe: guarda el XFile y sus
  /// bytes (con `readAsBytes`, nunca `XFile.path`, que en web es un blob).
  Future<void> _takePhoto() async {
    HapticFeedback.lightImpact();
    final source = await _pickSource();
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (photo == null || !mounted) return;

    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photo = photo;
      _photoBytes = bytes;
    });
  }

  /// Hoja inferior cámara/galería con objetivos táctiles grandes (Art. I).
  Future<ImageSource?> _pickSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              key: const Key('recipe_photo_camera'),
              leading: const Icon(Icons.camera_alt_rounded,
                  size: 32, color: AppTheme.primary),
              title: const Text('Tomar foto',
                  style: TextStyle(
                      fontSize: 20, color: AppTheme.textPrimary)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('recipe_photo_gallery'),
              leading: const Icon(Icons.photo_library_rounded,
                  size: 32, color: AppTheme.primary),
              title: const Text('Escoger de la galería',
                  style: TextStyle(
                      fontSize: 20, color: AppTheme.textPrimary)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _addCategory() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Nueva categoria...', style: TextStyle(fontSize: 18)),
        backgroundColor: AppTheme.primary,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _goToStep2() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Escriba el nombre del producto');
      return;
    }
    setState(() => _nameError = null);
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeStep2Screen(
          productName: name,
          salePrice: _parsePrice().toDouble(),
          emoji: _categoryEmoji,
          category: _selectedCategory,
          description: _descCtrl.text.trim(),
          portion: _selectedPortion ?? '',
          photo: _photo,
          api: widget.api,
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      width: 200,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.shade400,
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: Colors.grey.shade400,
          radius: 20,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_rounded,
                size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 8),
            Text(
              'Tomar foto del plato',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPreview(Uint8List bytes) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(
            bytes,
            width: 200,
            height: 160,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.edit_rounded,
                size: 20, color: Colors.white),
          ),
        ),
      ],
    );
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
          tooltip: 'Volver',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Crear Receta (1/3)',
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Photo placeholder / preview ---
                    GestureDetector(
                      key: const Key('recipe_photo_tap'),
                      onTap: _takePhoto,
                      child: _photoBytes != null
                          ? _photoPreview(_photoBytes!)
                          : _photoPlaceholder(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _photoBytes != null
                          ? 'Toque la foto para cambiarla.'
                          : 'Toque para abrir la camara o la galer\u00eda.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // --- Name field ---
                    const Text(
                      'Nombre del producto',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('field_recipe_name'),
                      controller: _nameCtrl,
                      style: const TextStyle(
                          fontSize: 20, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Ej: Perro Caliente Sencillo',
                        errorText: _nameError,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // --- Description field (F043) ---
                    const Text(
                      'Descripción (opcional)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('field_recipe_description'),
                      controller: _descCtrl,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                          fontSize: 20, color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        hintText:
                            'Ej: Pan artesanal, salchicha, papas y salsas',
                      ),
                    ),

                    const SizedBox(height: 28),

                    // --- Category dropdown ---
                    const Text(
                      '\u00bfEn que categoria va?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGrey,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: AppTheme.borderColor, width: 1.5),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCategory,
                                isExpanded: true,
                                style: const TextStyle(
                                  fontSize: 20,
                                  color: AppTheme.textPrimary,
                                  fontFamily: 'Roboto',
                                ),
                                icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 28),
                                items: _categories.map((cat) {
                                  return DropdownMenuItem<String>(
                                    value: cat['name'],
                                    child: Text(
                                        '${cat['emoji']} ${cat['name']}'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  HapticFeedback.selectionClick();
                                  if (val != null) {
                                    setState(
                                        () => _selectedCategory = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _addCategory,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(56, 56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Icon(Icons.add_rounded,
                                size: 28, color: Colors.white),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // --- Portion chips (F043, opcional) ---
                    const Text(
                      '\u00bfQu\u00e9 porci\u00f3n es? (opcional)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _portions.map((p) {
                        final selected = _selectedPortion == p;
                        return ChoiceChip(
                          key: Key('recipe_portion_$p'),
                          label: Text(
                            p,
                            style: TextStyle(
                              fontSize: 18,
                              color: selected
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                            ),
                          ),
                          selected: selected,
                          showCheckmark: false,
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.surfaceGrey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(
                                color: AppTheme.borderColor),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            // Toque de nuevo = deseleccionar (sin porci\u00f3n).
                            setState(() =>
                                _selectedPortion = selected ? null : p);
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 28),

                    // --- Price field ---
                    const Text(
                      '\u00bfA como lo va a vender?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('field_recipe_price'),
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.success,
                      ),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        prefixStyle: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.success,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppTheme.success, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppTheme.success, width: 2.5),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // --- Bottom button ---
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
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
                        color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    key: const Key('btn_recipe_to_step2'),
                    onPressed: _goToStep2,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'Agregar ingredientes',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ));

    const dashWidth = 8.0;
    const dashSpace = 5.0;

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, end.clamp(0, metric.length)),
          paint,
        );
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
