import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Perfil del Negocio — Gerontodiseño: textos grandes, alto contraste,
/// cero fricción. Fetch real al backend, sin datos hardcodeados.
class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nitCtrl = TextEditingController();

  late final ApiService _api;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  String? _logoUrl;
  String? _selectedBusinessType;

  static const _businessTypes = [
    ('tienda_barrio', 'Tienda / Minimarket'),
    ('bar', 'Restaurante / Bar'),
    ('comidas_rapidas', 'Comidas Rápidas'),
    ('miscelanea', 'Panadería / Miscelánea'),
    ('muebles', 'Ferretería / Muebles'),
    ('manufactura', 'Manufactura'),
    ('reparacion', 'Reparación'),
    ('minimercado', 'Minimercado'),
  ];

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _fetchProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nitCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await _api.fetchBusinessProfile();
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = data['business_name'] ?? '';
        _nitCtrl.text = data['nit'] ?? '';
        _logoUrl = (data['logo_url'] as String?)?.isNotEmpty == true
            ? data['logo_url']
            : null;
        _selectedBusinessType = data['business_type'];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Error al cargar perfil: $e', isError: true);
    }
  }

  void _showLogoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Cambiar Logo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            _LogoOptionTile(
              icon: Icons.photo_library_rounded,
              color: const Color(0xFF3B82F6),
              title: 'Subir foto de la galería',
              subtitle: 'Elija una imagen de su teléfono',
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndUploadLogo();
              },
            ),
            const SizedBox(height: 12),
            _LogoOptionTile(
              icon: Icons.auto_awesome_rounded,
              color: const Color(0xFF8B5CF6),
              title: 'Crear logo mágico con IA',
              subtitle: 'Diseño profesional automático',
              onTap: () {
                Navigator.of(ctx).pop();
                _generateLogoWithAI();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadLogo() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (photo == null || !mounted) return;

    setState(() => _uploadingLogo = true);
    try {
      final result = await _api.uploadLogo(File(photo.path));
      final newUrl = result['logo_url'] as String?;
      if (newUrl != null && mounted) {
        setState(() => _logoUrl = newUrl);
        await AuthService().updateLogoUrl(newUrl);
        _showSnack('Logo actualizado');
      }
    } catch (e) {
      if (mounted) _showSnack('Error al subir logo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _generateLogoWithAI() async {
    final name = _nameCtrl.text.trim();
    final type = _selectedBusinessType;

    if (name.isEmpty || type == null) {
      _showSnack(
        'Por favor, escriba el nombre y tipo de negocio primero para que la IA sepa qué dibujar.',
        isError: true,
      );
      return;
    }

    // Find friendly label for business type
    final typeLabel = _businessTypes
        .where((t) => t.$1 == type)
        .map((t) => t.$2)
        .firstOrNull ?? type;

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 16),
              CircularProgressIndicator(color: Color(0xFF8B5CF6), strokeWidth: 3),
              SizedBox(height: 24),
              Text(
                'Diseñando su logo...\nesto tomará unos segundos',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await _api.generateLogoAI(
        businessName: name,
        businessType: typeLabel,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog

      final newUrl = result['logo_url'] as String?;
      if (newUrl != null) {
        setState(() => _logoUrl = newUrl);
        await AuthService().updateLogoUrl(newUrl);
        _showSnack('Logo creado con IA exitosamente');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      _showSnack('Error al generar logo: $e', isError: true);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      final updates = <String, dynamic>{
        'business_name': _nameCtrl.text.trim(),
        'nit': _nitCtrl.text.trim(),
      };
      if (_selectedBusinessType != null) {
        updates['business_type'] = _selectedBusinessType;
      }

      await _api.updateBusinessProfile(updates);
      if (!mounted) return;
      _showSnack('Perfil guardado correctamente');
    } catch (e) {
      if (mounted) _showSnack('Error al guardar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 18)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Perfil del Negocio',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _buildBody(),
      bottomNavigationBar: _loading ? null : _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // ── Logo ──────────────────────────────────────────────
            _buildLogoSection(),
            const SizedBox(height: 32),

            // ── Nombre del Negocio ────────────────────────────────
            _buildLabel('Nombre del Negocio *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(
                  fontSize: 20, color: Colors.black87, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                hintText: 'Ej: Tienda Don José',
                prefixIcon: Icon(Icons.storefront_rounded, size: 24),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),

            // ── NIT / RUT ─────────────────────────────────────────
            _buildLabel('NIT / RUT (Opcional)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nitCtrl,
              style: const TextStyle(fontSize: 20, color: Colors.black87),
              decoration: const InputDecoration(
                hintText: 'Ej: 900.123.456-7',
                prefixIcon: Icon(Icons.badge_rounded, size: 24),
              ),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),

            // ── Tipo de Negocio ───────────────────────────────────
            _buildLabel('Tipo de Negocio'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedBusinessType,
              isExpanded: true,
              style: const TextStyle(
                  fontSize: 20, color: Colors.black87, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.category_rounded, size: 24),
              ),
              dropdownColor: Colors.white,
              items: _businessTypes.map((t) {
                return DropdownMenuItem(
                  value: t.$1,
                  child: Text(t.$2,
                      style: const TextStyle(
                          fontSize: 20, color: Colors.black87)),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedBusinessType = v),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: _uploadingLogo ? null : _showLogoOptions,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceGrey,
                  border: Border.all(color: AppTheme.borderColor, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(child: _buildLogoContent()),
              ),
              if (_uploadingLogo)
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3),
                  ),
                ),
              if (!_uploadingLogo)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primary,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _logoUrl != null ? 'Toque para cambiar' : 'Toque para agregar logo',
          style: const TextStyle(
              fontSize: 16, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildLogoContent() {
    if (_logoUrl != null) {
      return Image.network(
        _logoUrl!,
        width: 140,
        height: 140,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2),
          );
        },
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo_rounded,
            size: 40, color: AppTheme.primary.withValues(alpha: 0.5)),
        const SizedBox(height: 4),
        Text(
          'Agregar',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _saveProfile,
          icon: _saving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : const Text('\u{1F4BE}', style: TextStyle(fontSize: 24)),
          label: Text(
            _saving ? 'Guardando...' : 'Guardar Cambios',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppTheme.success.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
    );
  }
}

class _LogoOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LogoOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 15, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 28),
          ],
        ),
      ),
    );
  }
}
