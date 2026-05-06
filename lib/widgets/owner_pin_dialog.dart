import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/app_error.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Ask the cashier to enter the 4-digit PIN dictated by the owner.
/// Returns true on match, false on wrong PIN or dismissal.
///
/// Gerontodiseño: huge touch targets (60px), numeric keypad, instant
/// validation on 4th digit, one clear error line. Used to gate new-customer
/// fiado and other restricted actions.
Future<bool> askOwnerPin(
  BuildContext context, {
  String title = 'Confirmación del propietario',
  String subtitle =
      'Pida al propietario que ingrese su PIN de 4 dígitos para continuar.',
  ApiService? apiOverride,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OwnerPinDialog(
      title: title,
      subtitle: subtitle,
      apiOverride: apiOverride,
    ),
  );
  return result ?? false;
}

class _OwnerPinDialog extends StatefulWidget {
  const _OwnerPinDialog({
    required this.title,
    required this.subtitle,
    this.apiOverride,
  });

  final String title;
  final String subtitle;
  final ApiService? apiOverride;

  @override
  State<_OwnerPinDialog> createState() => _OwnerPinDialogState();
}

class _OwnerPinDialogState extends State<_OwnerPinDialog> {
  final _controller = TextEditingController();
  late final ApiService _api;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final pin = _controller.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'Ingrese 4 dígitos');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });

    String? errorMessage;
    try {
      final ok = await _api.verifyOwnerPin(pin);
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
        return;
      }
      errorMessage = 'PIN incorrecto';
    } on AppError catch (e) {
      developer.log('verifyOwnerPin AppError: ${e.message}',
          name: 'OwnerPinDialog');
      errorMessage = 'Error de conexión. Intenta de nuevo.';
    } catch (e, st) {
      developer.log('verifyOwnerPin unexpected error: $e',
          name: 'OwnerPinDialog', error: e, stackTrace: st);
      errorMessage = 'Error al verificar. Intenta de nuevo.';
    } finally {
      // ALWAYS reset loading state when there's an error, so the
      // cashier can retry or cancel — this is the freeze fix.
      if (mounted && errorMessage != null) {
        HapticFeedback.heavyImpact();
        setState(() {
          _checking = false;
          _error = errorMessage;
          _controller.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.admin_panel_settings_rounded,
              color: AppTheme.primary, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.subtitle,
              style: const TextStyle(fontSize: 16, height: 1.3)),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_checking,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              errorText: _error,
            ),
            onChanged: (v) {
              if (v.length == 4) _verify();
            },
          ),
          if (_checking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
