// Spec: specs/105-hito-restaurante-comandas/spec.md — F4 (QR localizador).
//
// Pantalla de éxito del cobro de MOSTRADOR PREPAGO: reemplaza el localizador
// físico de las cadenas. El cajero se la muestra al cliente:
//   · Número de pedido GIGANTE — es el feature principal: 40-60% de los
//     clientes 50+ no escanea QR; el cajero canta el número y listo.
//   · QR a la página viva /t/{token} — el celular del cliente cambia solo a
//     "¡SU PEDIDO ESTÁ LISTO!" (verde, vibración) cuando el chef lo marca.
//   · Botón WhatsApp MANUAL (wa.me) — jamás "automático": sin la API de
//     Meta prometer eso sería deshonesto (decisión del concilio).
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';

class OrderLocatorScreen extends StatefulWidget {
  final String orderLabel; // "Pedido 7"
  final String sessionToken;
  final ApiService? apiOverride;

  const OrderLocatorScreen({
    super.key,
    required this.orderLabel,
    required this.sessionToken,
    this.apiOverride,
  });

  @override
  State<OrderLocatorScreen> createState() => _OrderLocatorScreenState();
}

class _OrderLocatorScreenState extends State<OrderLocatorScreen> {
  String? _url;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  Future<void> _resolveUrl() async {
    try {
      final api = widget.apiOverride ?? ApiService(AuthService());
      final slug = await api.fetchStoreSlug();
      final base = (slug['base_url'] as String?)?.trim() ?? '';
      if (base.isEmpty) throw Exception('sin dominio');
      // base_url llega con el slug de la tienda (…/brasas); el localizador
      // vive en la raíz del dominio público: {origin}/t/{token}.
      final origin = Uri.parse(base).origin;
      if (mounted) {
        setState(() {
          _url = '$origin/t/${widget.sessionToken}';
          _resolving = false;
        });
      }
    } catch (_) {
      // Sin red o sin dominio: el número gigante sigue siendo el canal.
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _shareWhatsApp() async {
    final msg = Uri.encodeComponent(
      'Su pedido ${widget.orderLabel} quedó registrado. '
      'Siga su estado en vivo aquí: ${_url ?? ''} — le avisará cuando esté listo.',
    );
    final uri = Uri.parse('https://wa.me/?text=$msg');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* sin WhatsApp instalado: no rompe el flujo */}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: glassAppBar(
        title: 'Pedido enviado a cocina',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppUI.s24),
          child: Column(
            children: [
              // ── Número GIGANTE ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: AppUI.s24, horizontal: AppUI.s16),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(AppUI.radius),
                  boxShadow: AppUI.shadow,
                ),
                child: Column(
                  children: [
                    const Text(
                      'SU TURNO',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: AppUI.s8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.orderLabel,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppUI.s16),

              if (_resolving)
                const Padding(
                  padding: EdgeInsets.all(AppUI.s24),
                  child: CircularProgressIndicator(),
                )
              else if (_url != null) ...[
                SoftCard(
                  padding: const EdgeInsets.all(AppUI.s16),
                  child: Column(
                    children: [
                      const Text(
                        'El cliente escanea y su celular le avisa cuando esté listo',
                        textAlign: TextAlign.center,
                        style: AppUI.bodyStrong,
                      ),
                      const SizedBox(height: AppUI.s12),
                      QrImageView(
                        key: ValueKey('qr:$_url'),
                        data: _url!,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppUI.s12),
                AppButton(
                  label: 'Enviar link por WhatsApp',
                  icon: Icons.send_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: _shareWhatsApp,
                ),
              ] else
                SoftCard(
                  padding: const EdgeInsets.all(AppUI.s16),
                  child: Text(
                    'Sin conexión: cante el número cuando el pedido esté listo.',
                    textAlign: TextAlign.center,
                    style: AppUI.bodySoft.copyWith(color: AppTheme.warning),
                  ),
                ),

              const SizedBox(height: AppUI.s16),
              AppButton(
                label: 'Entendido',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
