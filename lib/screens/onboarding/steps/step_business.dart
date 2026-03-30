import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

class StepBusiness extends StatefulWidget {
  final OnboardingStepperController controller;
  final GlobalKey<FormState> formKey;

  const StepBusiness({
    super.key,
    required this.controller,
    required this.formKey,
  });

  @override
  State<StepBusiness> createState() => _StepBusinessState();
}

class _StepBusinessState extends State<StepBusiness> {
  bool _locationLoading = false;
  bool _locationFound = false;
  String? _locationError;
  final _addressCtrl = TextEditingController();
  final _addressDetailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.controller.address.isNotEmpty) {
      _locationFound = true;
      _addressCtrl.text = widget.controller.address;
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _addressDetailCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });

    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Permiso de ubicación denegado';
            _locationLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError =
              'Permiso denegado permanentemente.\nActívelo en Configuración del teléfono.';
          _locationLoading = false;
        });
        return;
      }

      // Get position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      // Reverse geocode
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      String address = '';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty)
            p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        ];
        address = parts.join(', ');
      }

      if (address.isEmpty) {
        address =
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      }

      setState(() {
        _addressCtrl.text = address;
        _locationFound = true;
        _locationLoading = false;
      });
      widget.controller.address = address;
    } catch (e) {
      setState(() {
        _locationError = 'No se pudo obtener la ubicación.\nIntente de nuevo.';
        _locationLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Nombre del negocio'),
            const SizedBox(height: 10),
            _field(
              key: const Key('biz_name'),
              hint: 'Ej: Don Pedro',
              icon: Icons.storefront_outlined,
              initialValue: widget.controller.businessName,
              onSaved: (v) => widget.controller.businessName = v!.trim(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingrese el nombre del negocio'
                  : null,
            ),
            const SizedBox(height: 24),
            _label('Razón social (opcional)'),
            const SizedBox(height: 10),
            _field(
              key: const Key('biz_razon'),
              hint: 'Ej: Pedro Martínez S.A.S.',
              icon: Icons.business_outlined,
              initialValue: widget.controller.razonSocial,
              onSaved: (v) =>
                  widget.controller.razonSocial = v?.trim() ?? '',
            ),
            const SizedBox(height: 24),
            _label('NIT / RUT (opcional)'),
            const SizedBox(height: 10),
            _field(
              key: const Key('biz_nit'),
              hint: 'Ej: 900.123.456-1',
              icon: Icons.numbers_outlined,
              initialValue: widget.controller.nit,
              onSaved: (v) => widget.controller.nit = v?.trim() ?? '',
            ),
            const SizedBox(height: 24),

            // ── Dirección con GPS ─────────────────────────────────────────
            _label('Ubicación del negocio'),
            const SizedBox(height: 10),

            if (!_locationFound) ...[
              // Estado "Antes": Botón mágico de GPS
              GestureDetector(
                key: const Key('btn_gps_location'),
                onTap: _locationLoading ? null : _getLocation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _locationLoading
                          ? [
                              const Color(0xFFF0F4FF),
                              const Color(0xFFE8EEFF),
                            ]
                          : [
                              const Color(0xFFEEF2FF),
                              const Color(0xFFE0E7FF),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (_locationLoading) ...[
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Buscando su ubicación...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF667EEA),
                                Color(0xFF1A2FA0),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppTheme.primary.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Usar mi ubicación actual',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Toque aquí estando en su negocio',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Error de ubicación
              if (_locationError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppTheme.error, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _locationError!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Link para escribir manualmente
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () {
                    setState(() => _locationFound = true);
                  },
                  child: Text(
                    'Prefiero escribir la dirección',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ],

            if (_locationFound) ...[
              // Estado "Después": Campo pre-llenado editable
              Text(
                _addressCtrl.text.isNotEmpty
                    ? 'Dirección encontrada (puede editarla):'
                    : 'Escriba la dirección de su negocio:',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),

              // Campo de dirección editable
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextFormField(
                  key: const Key('biz_address'),
                  controller: _addressCtrl,
                  style: const TextStyle(fontSize: 20),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Ej: Carrera 4 #12-50',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Icon(Icons.location_on_rounded,
                          color: AppTheme.success, size: 26),
                    ),
                    filled: true,
                    fillColor: _addressCtrl.text.isNotEmpty
                        ? const Color(0xFFF0FDF4) // verde muy claro = éxito
                        : const Color(0xFFF8F7F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: _addressCtrl.text.isNotEmpty
                            ? AppTheme.success.withValues(alpha: 0.3)
                            : const Color(0xFFE8E4DF),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                          color: AppTheme.primary, width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    widget.controller.address = v.trim();
                    setState(() {});
                  },
                  onSaved: (v) =>
                      widget.controller.address = v?.trim() ?? '',
                ),
              ),

              const SizedBox(height: 8),
              Text(
                'Ej: Al lado de la panadería, esquina con la iglesia',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                ),
              ),

              // Botón para re-capturar GPS
              if (_addressCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _locationFound = false;
                        _addressCtrl.clear();
                        widget.controller.address = '';
                      });
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text(
                      'Capturar ubicación de nuevo',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      );

  Widget _field({
    required Key key,
    required String hint,
    required IconData icon,
    String? initialValue,
    void Function(String?)? onSaved,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
      initialValue: initialValue,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
          fontWeight: FontWeight.w400,
          fontStyle: FontStyle.italic,
        ),
        prefixIcon: Icon(icon, color: AppTheme.primary, size: 26),
      ),
      onSaved: onSaved,
      validator: validator,
    );
  }
}
