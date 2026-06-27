// Spec: specs/044-catalogo-publico-unificado/spec.md
//
// Crear un SERVICIO publicable (F044). Un servicio es un Product con
// is_service=true: sin inventario, pedible siempre que la tienda esté abierta.
// Generaliza el catálogo público a todo tipo de negocio (peluquería, taller,
// lavandería…), no solo restaurantes. Pantalla simple y enfocada (Art. I):
// nombre, precio, descripción, categoría y foto opcional — todo editable.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_input.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Categorías sugeridas para servicios (texto libre permitido). El catálogo
/// público agrupa por esta categoría.
const List<String> kServiceCategories = [
  'Servicios',
  'Mano de obra',
  'Reparaciones',
  'Domicilio',
  'Otros',
];

class CreateServiceScreen extends StatefulWidget {
  const CreateServiceScreen({super.key});

  @override
  State<CreateServiceScreen> createState() => _CreateServiceScreenState();
}

class _CreateServiceScreenState extends State<CreateServiceScreen> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  // Spec 084 — duración (para citas) + comisión del servicio. Solo se muestran
  // si el negocio liquida a profesionales (peluquería/barbería).
  final _durationCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  bool _staffMode = false;
  String _category = 'Servicios';
  XFile? _photo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AuthService().getFeatureFlags().then((f) {
      if (mounted && f.enableStaffCommissions) {
        setState(() => _staffMode = true);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    _commissionCtrl.dispose();
    super.dispose();
  }

  bool get _isValid => _nameCtrl.text.trim().length >= 2;

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('service_photo_camera'),
              leading:
                  const Icon(Icons.photo_camera_rounded, color: AppTheme.primary),
              title: const Text('Tomar foto', style: TextStyle(fontSize: 16)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('service_photo_gallery'),
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppTheme.primary),
              title: const Text('Elegir de la galería',
                  style: TextStyle(fontSize: 16)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked != null) setState(() => _photo = picked);
  }

  Future<void> _save() async {
    if (!_isValid) {
      _snack('Escribe el nombre del servicio (mínimo 2 letras).',
          AppTheme.warning);
      return;
    }
    setState(() => _saving = true);
    final api = ApiService(AuthService());
    try {
      final price =
          int.tryParse(_priceCtrl.text.replaceAll('.', '').trim()) ?? 0;
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'price': price,
        'stock': 0, // un servicio no lleva inventario
        'category': _category,
        'is_service': true,
      };
      final desc = _descCtrl.text.trim();
      if (desc.isNotEmpty) data['description'] = desc;

      // Spec 084 — duración (citas) + comisión por servicio (peluquería).
      if (_staffMode) {
        final dur = int.tryParse(_durationCtrl.text.trim());
        if (dur != null && dur > 0) data['duration_min'] = dur;
        final pct = double.tryParse(_commissionCtrl.text.trim());
        if (pct != null) data['commission_pct'] = pct;
      }

      final created = await api.createProduct(data);

      // Foto opcional: si la cargó, la subimos al producto recién creado.
      final uuid = (created['id'] ?? created['uuid'])?.toString();
      if (_photo != null && uuid != null && uuid.isNotEmpty) {
        try {
          await api.uploadProductPhoto(uuid, _photo!);
        } catch (_) {
          // La foto es opcional: si falla, el servicio igual queda creado.
        }
      }

      if (!mounted) return;
      _snack('¡Listo! "${_nameCtrl.text.trim()}" ya está en tu catálogo en línea.',
          AppTheme.success);
      Navigator.of(context).pop(true);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(e.message, AppTheme.error);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('No pudimos guardar el servicio. Intenta de nuevo.', AppTheme.error);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Crear servicio'),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16, left: 4),
            child: Text(
              'Publica un servicio en tu catálogo en línea (corte, reparación, '
              'mano de obra, domicilio…). No lleva inventario: tus clientes lo '
              'pueden pedir mientras tu tienda esté abierta.',
              style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.3),
            ),
          ),
          _PhotoPicker(photo: _photo, onTap: _pickPhoto),
          const SizedBox(height: 16),
          _Field(
            controller: _nameCtrl,
            label: 'Nombre del servicio',
            hint: 'Ej: Corte de cabello',
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _priceCtrl,
            label: 'Precio',
            hint: '0',
            keyboardType: TextInputType.number,
            inputFormatters: const [CurrencyInputFormatter()],
            prefix: '\$ ',
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _descCtrl,
            label: 'Descripción (opcional)',
            hint: 'Qué incluye el servicio',
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          // Spec 084 — duración (para reservar turnos) + comisión del profesional.
          if (_staffMode) ...[
            const SizedBox(height: 12),
            _Field(
              controller: _durationCtrl,
              label: 'Duración (minutos) — para reservar turnos',
              hint: 'Ej: 30',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _commissionCtrl,
              label: 'Comisión del profesional (%) — opcional',
              hint: 'Ej: 40',
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 16),
          const Text('Categoría',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kServiceCategories.map((cat) {
              final selected = cat == _category;
              return ChoiceChip(
                label: Text(cat),
                selected: selected,
                onSelected: (_) => setState(() => _category = cat),
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
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            key: const Key('create_service_save'),
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
              _saving ? 'Guardando…' : 'Publicar servicio',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final XFile? photo;
  final VoidCallback onTap;

  const _PhotoPicker({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('service_photo_picker'),
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: photo == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded,
                      size: 36, color: AppTheme.primary),
                  SizedBox(height: 8),
                  Text('Agregar foto (opcional)',
                      style: TextStyle(fontSize: 14, color: Colors.black54)),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: _ServicePreview(photo: photo!),
              ),
      ),
    );
  }
}

/// Vista previa cross-platform de la foto elegida: usa bytes (web-safe), nunca
/// `dart:io File`/`XFile.path` directo.
class _ServicePreview extends StatelessWidget {
  final XFile photo;
  const _ServicePreview({required this.photo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: photo.readAsBytes(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Image.memory(snap.data!, fit: BoxFit.cover, width: double.infinity);
      },
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
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.prefix,
    this.onChanged,
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
          onChanged: onChanged,
          style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: Colors.white,
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
