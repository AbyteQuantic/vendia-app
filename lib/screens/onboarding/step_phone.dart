import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import 'onboarding_controller.dart';

class StepPhone extends StatefulWidget {
  final OnboardingController controller;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const StepPhone({
    super.key,
    required this.controller,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<StepPhone> createState() => _StepPhoneState();
}

class _StepPhoneState extends State<StepPhone> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  bool _phoneValid = false;
  bool _pinVisible = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _handleNext() {
    if (_formKey.currentState!.validate()) {
      widget.controller.phone = _phoneCtrl.text.trim();
      widget.controller.password = _pinCtrl.text.trim();
      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Cuál es su número\nde celular?',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Esto será su nombre de usuario para entrar a VendIA.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),

            // ── Teléfono ────────────────────────────────────────────────────
            Text('Número de celular',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 22, letterSpacing: 2),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => setState(() => _phoneValid = v.length >= 7),
              decoration: InputDecoration(
                hintText: 'Ej: 310 000 0000',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                ),
                prefixIcon: const Icon(Icons.phone_outlined,
                    color: AppTheme.primary, size: 26),
                suffixIcon: _phoneCtrl.text.isNotEmpty
                    ? Icon(
                        _phoneValid ? Icons.check_circle : Icons.error_outline,
                        color: _phoneValid ? AppTheme.success : AppTheme.error,
                        size: 26,
                      )
                    : null,
              ),
              validator: (v) {
                if (v == null || v.isEmpty)
                  return 'Ingrese su número de celular';
                if (v.length < 7) return 'Mínimo 7 dígitos';
                return null;
              },
            ),

            const SizedBox(height: 28),

            // ── PIN de acceso ───────────────────────────────────────────────
            Text('Cree una clave de acceso',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Mínimo 4 dígitos. La usará para entrar cada vez.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: !_pinVisible,
              style: const TextStyle(fontSize: 22, letterSpacing: 6),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                hintText: '• • • •',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: const Icon(Icons.lock_outline,
                    color: AppTheme.primary, size: 26),
                suffixIcon: IconButton(
                  icon: Icon(
                    _pinVisible ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => setState(() => _pinVisible = !_pinVisible),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Cree una clave de acceso';
                if (v.length < 4) return 'Mínimo 4 dígitos';
                return null;
              },
            ),

            const SizedBox(height: 16),
            // Nota de seguridad
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security_rounded,
                      color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sus datos están protegidos. Solo usted puede acceder.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _phoneValid ? _handleNext : null,
              child: const Text('Siguiente →'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onBack,
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              child: const Text(
                '← Volver',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
