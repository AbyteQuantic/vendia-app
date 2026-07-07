// Spec: specs/098-aporte-automatico-fotos-colaborativo/spec.md
//
// Modal BLOQUEANTE de re-aceptación de términos (Fase 1, AC-02). Se muestra en
// el login / selector de workspace cuando la respuesta trae
// `terms_acceptance_required == true`. No es descartable: el tenant debe
// aceptar los términos actualizados (incluye la cláusula colaborativa de
// imágenes) para poder entrar. Al aceptar → POST /api/v1/terms/accept.
//
// Fail-safe: si la llamada falla (red), muestra el error y NO avanza — el
// usuario reintenta. "Salir" cierra devolviendo false (el caller hace logout).
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'terms_screen.dart';
import 'terms_text.dart';

/// Muestra el modal bloqueante. Devuelve `true` si el tenant aceptó (y el POST
/// /terms/accept fue exitoso); `false` si eligió "Salir".
Future<bool> showTermsReacceptDialog(
  BuildContext context,
  ApiService api,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => _TermsReacceptDialog(api: api),
  );
  return result ?? false;
}

class _TermsReacceptDialog extends StatefulWidget {
  const _TermsReacceptDialog({required this.api});

  final ApiService api;

  @override
  State<_TermsReacceptDialog> createState() => _TermsReacceptDialogState();
}

class _TermsReacceptDialogState extends State<_TermsReacceptDialog> {
  bool _accepting = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.api.acceptTerms();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _error =
            'No pudimos guardar su aceptación. Verifique su conexión e intente de nuevo.';
      });
    }
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TermsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Bloqueante: el botón físico Atrás no cierra el modal.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Términos actualizados',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                kVendiaTermsReacceptSummary,
                style: TextStyle(fontSize: 16, height: 1.45),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _accepting ? null : _openTerms,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text(
                  'Ver términos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 15),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: _accepting ? null : () => Navigator.of(context).pop(false),
            child: const Text('Salir', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: _accepting ? null : _accept,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _accepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text(
                    'Aceptar y continuar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}
