// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Pantalla genérica para un módulo del catálogo con render_type `webview`.
// La app no embebe un WebView (evitamos sumar la dependencia webview_flutter
// en esta fase); abre la URL configurada en el navegador con url_launcher.
// Una URL vacía/ inválida no rompe — muestra un mensaje claro.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

class ModuleWebviewScreen extends StatelessWidget {
  final String title;
  final String? url;

  const ModuleWebviewScreen({super.key, required this.title, this.url});

  Future<void> _open(BuildContext context) async {
    final raw = url?.trim() ?? '';
    final uri = Uri.tryParse(raw);
    if (raw.isEmpty || uri == null || !uri.hasScheme) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este módulo no tiene un enlace válido.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = (url?.trim().isNotEmpty ?? false);
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
              Icon(Icons.open_in_new_rounded,
                  size: 64, color: AppTheme.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (hasUrl)
                ElevatedButton.icon(
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Abrir'),
                )
              else
                const Text('Este módulo aún no tiene un enlace configurado.',
                    style:
                        TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
