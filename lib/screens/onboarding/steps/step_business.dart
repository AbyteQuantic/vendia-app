import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

class StepBusiness extends StatelessWidget {
  final OnboardingStepperController controller;
  final GlobalKey<FormState> formKey;

  const StepBusiness({
    super.key,
    required this.controller,
    required this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Nombre de la tienda'),
            const SizedBox(height: 10),
            _field(
              key: const Key('biz_name'),
              hint: 'Tienda Don Pedro',
              icon: Icons.storefront_outlined,
              initialValue: controller.businessName,
              onSaved: (v) => controller.businessName = v!.trim(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingrese el nombre de la tienda'
                  : null,
            ),
            const SizedBox(height: 24),
            _label('Razón social (opcional)'),
            const SizedBox(height: 10),
            _field(
              key: const Key('biz_razon'),
              hint: 'Pedro Martínez S.A.S.',
              icon: Icons.business_outlined,
              initialValue: controller.razonSocial,
              onSaved: (v) => controller.razonSocial = v?.trim() ?? '',
            ),
            const SizedBox(height: 24),
            _label('NIT / RUT (opcional)'),
            const SizedBox(height: 10),
            _field(
              key: const Key('biz_nit'),
              hint: '900.123.456-1',
              icon: Icons.numbers_outlined,
              initialValue: controller.nit,
              onSaved: (v) => controller.nit = v?.trim() ?? '',
            ),
            const SizedBox(height: 24),
            _label('Dirección (opcional)'),
            const SizedBox(height: 10),
            _field(
              key: const Key('biz_address'),
              hint: 'Calle 12 #34-56, Barrio El Carmen',
              icon: Icons.location_on_outlined,
              initialValue: controller.address,
              onSaved: (v) => controller.address = v?.trim() ?? '',
            ),
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
        prefixIcon: Icon(icon, color: AppTheme.primary, size: 26),
      ),
      onSaved: onSaved,
      validator: validator,
    );
  }
}
