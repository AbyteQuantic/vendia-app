import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'onboarding_controller.dart';

class StepIdentity extends StatefulWidget {
  final OnboardingController controller;
  final VoidCallback onNext;

  const StepIdentity({
    super.key,
    required this.controller,
    required this.onNext,
  });

  @override
  State<StepIdentity> createState() => _StepIdentityState();
}

class _StepIdentityState extends State<StepIdentity> {
  final _formKey = GlobalKey<FormState>();
  final _ownerCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _businessCtrl.dispose();
    super.dispose();
  }

  void _handleNext() {
    if (_formKey.currentState!.validate()) {
      widget.controller.ownerName = _ownerCtrl.text.trim();
      widget.controller.businessName = _businessCtrl.text.trim();
      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¡Hola! ¿Cómo se llama usted\ny su negocio?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Solo necesitamos dos datos para empezar.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 40),

          // Campo: Nombre del dueño
          Text('Su nombre', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          TextFormField(
            controller: _ownerCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Ej: Doña Rosa García',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
              ),
              prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primary, size: 26),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Por favor ingrese su nombre'
                : null,
          ),
          const SizedBox(height: 28),

          // Campo: Nombre del local
          Text('Nombre del negocio',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          TextFormField(
            controller: _businessCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Ej: La Esperanza',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
              ),
              prefixIcon: const Icon(Icons.storefront_outlined,
                  color: AppTheme.primary, size: 26),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Por favor ingrese el nombre de su negocio'
                : null,
          ),
          const Spacer(),

          ElevatedButton(
            onPressed: _handleNext,
            child: const Text('Siguiente →'),
          ),
        ],
      ),
    );
  }
}
