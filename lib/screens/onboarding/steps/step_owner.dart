import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';

class StepOwner extends StatelessWidget {
  final OnboardingStepperController controller;
  final GlobalKey<FormState> formKey;

  const StepOwner({
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
            _label('Nombre'),
            const SizedBox(height: 10),
            _field(
              key: const Key('owner_name'),
              hint: 'Pedro',
              icon: Icons.person_outline_rounded,
              initialValue: controller.ownerName,
              onSaved: (v) => controller.ownerName = v!.trim(),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingrese su nombre' : null,
            ),
            const SizedBox(height: 24),
            _label('Apellido'),
            const SizedBox(height: 10),
            _field(
              key: const Key('owner_lastname'),
              hint: 'Martínez',
              icon: Icons.badge_outlined,
              initialValue: controller.ownerLastName,
              onSaved: (v) => controller.ownerLastName = v!.trim(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingrese su apellido'
                  : null,
            ),
            const SizedBox(height: 24),
            _label('Número de celular'),
            const SizedBox(height: 10),
            _field(
              key: const Key('owner_phone'),
              hint: '310 000 0000',
              icon: Icons.phone_outlined,
              keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              initialValue: controller.phone,
              onSaved: (v) => controller.phone = v!.trim(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingrese su número';
                if (v.trim().length < 7) return 'Número muy corto';
                return null;
              },
            ),
            const SizedBox(height: 24),
            _label('Clave de acceso (PIN)'),
            const SizedBox(height: 10),
            _PinField(
              initialValue: controller.pin,
              onSaved: (v) => controller.pin = v!.trim(),
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
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? initialValue,
    void Function(String?)? onSaved,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
      initialValue: initialValue,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
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

class _PinField extends StatefulWidget {
  final String? initialValue;
  final void Function(String?)? onSaved;

  const _PinField({this.initialValue, this.onSaved});

  @override
  State<_PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<_PinField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const Key('owner_pin'),
      initialValue: widget.initialValue,
      keyboardType: TextInputType.number,
      obscureText: !_visible,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      style: const TextStyle(fontSize: 22, letterSpacing: 6),
      decoration: InputDecoration(
        hintText: '• • • •',
        prefixIcon:
            const Icon(Icons.lock_outline, color: AppTheme.primary, size: 26),
        suffixIcon: IconButton(
          icon: Icon(
            _visible ? Icons.visibility_off : Icons.visibility,
            color: AppTheme.textSecondary,
          ),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
      onSaved: widget.onSaved,
      validator: (v) {
        if (v == null || v.isEmpty) return 'Ingrese su clave';
        if (v.length < 4) return 'Mínimo 4 dígitos';
        return null;
      },
    );
  }
}
