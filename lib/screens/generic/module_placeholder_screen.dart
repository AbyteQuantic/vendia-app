// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Pantalla genérica "próximamente" para un módulo del catálogo cuyo
// render_type es `placeholder`, o cuyo `native_screen_key` no existe en la
// versión instalada de la app (degradación segura — FR-10/AC-09).

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

class ModulePlaceholderScreen extends StatelessWidget {
  final String title;

  const ModulePlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty_rounded,
                  size: 72, color: AppTheme.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              const Text(
                'Próximamente',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta opción estará disponible pronto en tu app.',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
