// Spec: specs/098-aporte-automatico-fotos-colaborativo/spec.md
//
// Pantalla de Términos y Servicios de VendIA (Fase 1). Muestra el texto
// completo [kVendiaTermsText], scrolleable, con el estilo del design system.
// Se abre desde el checkbox del registro y desde el modal de re-aceptación
// del login.
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'terms_text.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Términos y Servicios',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Text(
              kVendiaTermsText.trim(),
              style: const TextStyle(
                fontSize: 17,
                height: 1.5,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
