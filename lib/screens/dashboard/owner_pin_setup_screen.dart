import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Owner-only screen to set (or replace) the 4-digit PIN that cashiers will
/// enter to unlock restricted actions like creating a new fiado for an
/// unknown customer, voiding a past sale, etc.
class OwnerPinSetupScreen extends StatefulWidget {
  const OwnerPinSetupScreen({super.key});

  @override
  State<OwnerPinSetupScreen> createState() => _OwnerPinSetupScreenState();
}

class _OwnerPinSetupScreenState extends State<OwnerPinSetupScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  late final ApiService _api;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pin.text.trim();
    final confirm = _confirm.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'El PIN debe tener 4 dígitos');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Los PIN no coinciden');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await _api.setOwnerPin(pin);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _success = 'PIN guardado. Dígite este PIN cuando el cajero lo pida.';
        _pin.clear();
        _confirm.clear();
      });
    } on AppError catch (e) {
      HapticFeedback.heavyImpact();
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PIN del propietario',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Este PIN de 4 dígitos se lo pedirán a tus cajeros cuando quieran '
                'hacer acciones sensibles, como fiar a un cliente nuevo o anular '
                'una venta antigua. No se lo digas a nadie que no sea de confianza.',
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Nuevo PIN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 8),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Confirmar PIN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 8),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 16)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 12),
              Text(_success!,
                  style: const TextStyle(
                      color: Color(0xFF059669), fontSize: 16)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text('Guardar PIN',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
