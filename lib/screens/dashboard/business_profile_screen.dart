// Spec: specs/023-capacidades-opcionales-negocio/spec.md
// Spec: specs/028-copy-fiar-credito-configurable/spec.md
// Spec: specs/029-precios-multi-tier/spec.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/image_normalizer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/logo_ai_editor_sheet.dart';

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
  final _addressCtrl = TextEditingController();
  double _latitude = 0;
  double _longitude = 0;
  bool _gettingLocation = false;

  late final ApiService _api;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  String? _logoUrl;
  // Selección ÚNICA — el backend acepta un array pero la UX enforce
  // una sola categoría para evitar combinaciones ambiguas de feature
  // flags. Se persiste como lista de 1 en el payload para no romper
  // el contrato del wire.
  // Multi-select: un tenant puede declarar una o varias categorías
  // (ej. tienda de barrio + comidas rápidas). El header del Dashboard
  // las muestra todas; este form permite marcar/desmarcar cualquiera.
  // El backend acepta el array y la unión de las capacidades implícitas
  // (impliedCapabilities) se calcula sobre todos los tipos en el cliente.
  final Set<String> _selectedTypes = <String>{};

  // F036: las capacidades opcionales (F023/F029/F030/F031/F033) se
  // movieron a la pantalla dedicada "Capacidades del negocio"
  // (business_capabilities_screen.dart). El perfil del negocio queda
  // solo con los DATOS del negocio: nombre, NIT, logo, tipo, dirección.

  // 1:1 con la whitelist del backend (models.ValidBusinessTypes,
  // migración 020). Cada entry es (valor_snake_case, ícono, etiqueta).
  // Cualquier cambio en la columna de valor debe ir acompañado de una
  // migración — handlers.validateBusinessTypes rechaza cualquier otro
  // string con HTTP 400 antes de que llegue al DB CHECK.
  static const _businessTypes = [
    ('tienda_barrio', Icons.store_rounded, 'Tienda de Barrio'),
    ('minimercado', Icons.local_grocery_store_rounded, 'Minimercado'),
    ('deposito_construccion', Icons.inventory_2_rounded, 'Depósito / Ferretería'),
    ('restaurante', Icons.restaurant_rounded, 'Restaurante'),
    ('comidas_rapidas', Icons.fastfood_rounded, 'Comidas Rápidas'),
    ('bar', Icons.local_bar_rounded, 'Bar / Discoteca'),
    ('manufactura', Icons.precision_manufacturing_rounded, 'Manufactura'),
    ('reparacion_muebles', Icons.build_rounded, 'Reparación / Servicios'),
    ('emprendimiento_general', Icons.rocket_launch_rounded, 'Emprendimiento General'),
    // F042 — academias/institutos: al elegirlo se activa el módulo de Eventos.
    ('academias_instituciones', Icons.school_rounded, 'Academias e Instituciones'),
  ];

  // Legacy values that early-2026 tenants still carry in storage.
  // Maps each deprecated value to its new canonical one so the screen
  // can render a valid selection even before the user saves the new
  // choice (which would then overwrite the legacy string server-side).
  static const _legacyTypeRemap = {
    'muebles': 'reparacion_muebles',
    'reparacion': 'reparacion_muebles',
    'miscelanea': 'emprendimiento_general',
  };

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
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await _api.fetchBusinessProfile();
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = data['business_name'] ?? '';
        _nitCtrl.text = data['nit'] ?? '';
        _addressCtrl.text = data['address'] ?? '';
        _latitude = (data['latitude'] as num?)?.toDouble() ?? 0;
        _longitude = (data['longitude'] as num?)?.toDouble() ?? 0;
        _logoUrl = (data['logo_url'] as String?)?.isNotEmpty == true
            ? data['logo_url']
            : null;

        // Hidratar TODAS las categorías del array — el modelo soporta
        // multi-select y antes el UI solo mostraba la primera (bug
        // reportado: el header listaba 3 pero el form mostraba 1, y
        // guardar borraba las demás). Remapea legacy values al pasar.
        _selectedTypes.clear();
        final types = data['business_types'];
        if (types is List) {
          for (final raw in types) {
            if (raw is String && raw.isNotEmpty) {
              final canonical = _legacyTypeRemap[raw] ?? raw;
              _selectedTypes.add(canonical);
            }
          }
        }
        // Fallback al campo escalar `business_type` para tenants
        // pre-migración 020.
        if (_selectedTypes.isEmpty &&
            data['business_type'] is String &&
            (data['business_type'] as String).isNotEmpty) {
          final raw = data['business_type'] as String;
          _selectedTypes.add(_legacyTypeRemap[raw] ?? raw);
        }

        // F036: las capacidades opcionales ya no se hidratan acá — se
        // gestionan en "Capacidades del negocio".

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Error al cargar perfil: $e', isError: true);
    }
  }

  // ── Logo Options ──────────────────────────────────────────────────────────

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
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87),
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
      // Pass the XFile directly — the service reads its bytes, which
      // works on web (no filesystem) and mobile. Avoids `dart:io File`.
      final result = await _api.uploadLogo(photo);
      final newUrl = result['logo_url'] as String?;
      if (newUrl != null && mounted) {
        setState(() => _logoUrl = newUrl);
        await AuthService().updateLogoUrl(newUrl);
        _showSnack('Logo actualizado');
      }
    } on ImageNormalizationException catch (e) {
      // Spec 010 (FR-04 / AC-05): the picked photo could not be decoded
      // (e.g. a HEIC file the browser cannot handle). Show the clear,
      // actionable Spanish message instead of a raw exception dump.
      if (mounted) _showSnack(e.message, isError: true);
    } catch (e) {
      if (mounted) _showSnack('Error al subir logo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _generateLogoWithAI() async {
    final name = _nameCtrl.text.trim();
    // Pasamos a la IA la PRIMERA categoría elegida (la principal). Si
    // el dueño selecciona varias, la primera es la más representativa
    // (suele ser la que más vende). Sin selección no podemos generar.
    final selected = _selectedTypes.isNotEmpty ? _selectedTypes.first : null;

    if (name.isEmpty || selected == null) {
      _showSnack(
        'Por favor, escriba el nombre y seleccione al menos una categoría de negocio para que la IA sepa qué dibujar.',
        isError: true,
      );
      return;
    }

    // Use the friendly label for the prompt so Gemini sees Spanish
    // copy instead of the snake_case enum value.
    final typeLabel = _businessTypes
            .where((t) => t.$1 == selected)
            .map((t) => t.$3)
            .firstOrNull ??
        selected;

    if (!mounted) return;
    // Editor con IA: el tendero escribe especificaciones (colores, estilo,
    // símbolos), genera, previsualiza y puede iterar hasta que le guste.
    // La IA exige ≥12 chars de detalle, así que pedirlos NO es opcional —
    // antes se generaba sin `details` y el backend lo rechazaba.
    await showLogoAiEditor(
      context,
      currentLogoUrl: _logoUrl,
      onGenerate: (specs) async {
        final result = await _api.generateLogoAI(
          businessName: name,
          businessType: typeLabel,
          details: specs,
        );
        return result['logo_url'] as String?;
      },
      onSaved: (url) async {
        setState(() => _logoUrl = url);
        await AuthService().updateLogoUrl(url);
        if (mounted) _showSnack('Logo actualizado con IA');
      },
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _captureLocation() async {
    setState(() => _gettingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          _showSnack('Permiso de ubicacion denegado', isError: true);
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _latitude = pos.latitude;
          _longitude = pos.longitude;
        });
      }

      // Reverse geocode NATIVO (móvil) → dirección + ciudad (locality).
      String localCity = '';
      try {
        final placemarks = await placemarkFromCoordinates(
            pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty && mounted) {
          final p = placemarks.first;
          localCity = p.locality ?? '';
          final addr = [p.street, p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          if (addr.isNotEmpty && _addressCtrl.text.isEmpty) {
            setState(() => _addressCtrl.text = addr);
          }
        }
      } catch (_) {} // geocoding may fail, GPS coords still saved

      // Spec 072 — persiste ubicación + ciudad. La ciudad del geocoder nativo
      // (móvil) es la primaria; si vino vacía (web), el backend usa Photon.
      String city = '';
      try {
        final res = await ApiService(AuthService()).updateStoreLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          city: localCity,
        );
        city = (res['city'] ?? '').toString();
      } catch (_) {}

      if (mounted) {
        _showSnack(city.isNotEmpty ? 'Ubicación guardada · $city' : 'Ubicación capturada');
      }
    } catch (e) {
      if (mounted) _showSnack('Error al obtener ubicacion: $e', isError: true);
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTypes.isEmpty) {
      _showSnack('Seleccione al menos una categoría de negocio',
          isError: true);
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      // F036: el perfil persiste SOLO los datos del negocio. Las
      // capacidades opcionales se guardan desde "Capacidades del
      // negocio"; el cuaderno desde CreditSettingsScreen (F035).
      final updates = <String, dynamic>{
        'business_name': _nameCtrl.text.trim(),
        'nit': _nitCtrl.text.trim(),
        // Multi-select: enviamos el array completo de categorías
        // marcadas por el dueño. Backend ya acepta multi-tipo.
        'business_types': _selectedTypes.toList(),
        'address': _addressCtrl.text.trim(),
        if (_latitude != 0) 'latitude': _latitude,
        if (_longitude != 0) 'longitude': _longitude,
      };

      final response = await _api.updateBusinessProfile(updates);
      // Refrescar cache local de feature_flags + business_types — al
      // cambiar el tipo de negocio o toggles desde aquí, el Dashboard
      // (que lee de disco) tiene que ver el cambio al volver.
      await AuthService().saveFeatureFlagsFromProfile(response);

      if (!mounted) return;
      _showSnack('Perfil guardado correctamente');
      Navigator.of(context).pop();
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

  // ── Build ──────────────────────────────────────────────────────────────────

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
                  fontSize: 20,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500),
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

            // ── Dirección del local ────────────────────────────────
            _buildLabel('Dirección del local'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _addressCtrl,
              style: const TextStyle(fontSize: 20, color: Colors.black87),
              decoration: const InputDecoration(
                hintText: 'Ej: Cra 5 #12-34, Bogotá',
                prefixIcon: Icon(Icons.location_on_rounded, size: 24),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _gettingLocation ? null : _captureLocation,
                icon: _gettingLocation
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                label: Text(
                  _gettingLocation
                      ? 'Obteniendo ubicacion...'
                      : _latitude != 0
                          ? 'Ubicacion capturada'
                          : 'Capturar mi ubicacion actual',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _latitude != 0
                      ? AppTheme.success : AppTheme.primary,
                  side: BorderSide(
                    color: _latitude != 0
                        ? AppTheme.success : AppTheme.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Categorías del negocio (MULTI-SELECT) ─────────────
            _buildLabel(
                'Seleccione una o varias categorías de su negocio'),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Toque para marcar o desmarcar. Puede combinar varias '
                '(ej. tienda + comidas rápidas).',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.3,
                ),
              ),
            ),
            _buildBusinessTypeGrid(),

            // F036: las capacidades opcionales se gestionan ahora en la
            // pantalla "Capacidades del negocio" (Mi Negocio →
            // Capacidades del negocio). El cuaderno de créditos vive en
            // CreditSettingsScreen (F035). Este perfil queda solo con
            // los DATOS del negocio.

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessTypeGrid() {
    // Multi-select grid mapped 1:1 to models.ValidBusinessTypes.
    // GridView en lugar de Wrap para que las cards mantengan el
    // mismo tamaño bajo Gerontodiseño. Tap alterna selección.
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: _businessTypes.map((t) {
        final value = t.$1;
        final icon = t.$2;
        final label = t.$3;
        final selected = _selectedTypes.contains(value);
        return Semantics(
          button: true,
          selected: selected,
          label: label,
          child: GestureDetector(
            key: Key('profile_btype_$value'),
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                if (selected) {
                  _selectedTypes.remove(value);
                } else {
                  _selectedTypes.add(value);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? AppTheme.primary
                      : const Color(0xFFD6D0C8),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Checkbox indicator — multi-select. Cuadrado con tilde
                  // cuando está marcado; cuadrado vacío con borde cuando
                  // no. Visual consistente con que se pueden marcar
                  // varios.
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary
                            : const Color(0xFFB0A99A),
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? AppTheme.primary : const Color(0xFF6B6B6B),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
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

  // F035: _buildCreditLabelSection() se trasladó a credit_settings_screen.dart.
  // El estado _creditLabelMode + load/save de credit_label_mode también se
  // remueven más abajo para evitar UI fantasma.

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
          style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87)),
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

// F035: _CreditLabelOption se trasladó a credit_settings_screen.dart
// como _VocabOption. Esta pantalla ya no lo necesita.
