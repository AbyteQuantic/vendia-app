// Spec: specs/033-difusion-promociones/spec.md
//
// Pantalla "Detalle de promoción" (F033 — spec §4 "Histórico", AC-09).
//
// Muestra una promoción completa con:
//   - Header con foto, título, descripción, vigencia y estado.
//   - Items en oferta.
//   - Métricas: audiencia / enviados / visitas.
//   - Botón "Enviar" → bottom-sheet de canales (SendPromotionSheet).
//   - Log de envíos (cliente, canal, estado, si visitó el link).
//
// El flujo de envío por WhatsApp encadena: elegir audiencia
// (AudienceSelectorScreen) → crear deliveries → cola modo express
// (WhatsappQueueScreen). Si la audiencia es grande, el dueño puede
// derivar a la Lista de Difusión (BroadcastListHelperScreen).
//
// Gerontodiseño: textos ≥17pt, botones ≥56dp, probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_config.dart';
import '../../models/broadcast_promotion.dart';
import '../../models/customer.dart';
import '../../models/promotion_delivery.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/promotion_message_template.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/send_promotion_sheet.dart';
import 'audience_selector_screen.dart';
import 'broadcast_list_helper_screen.dart';
import 'promotion_form_screen.dart';
import 'promotions_list_screen.dart';
import 'whatsapp_queue_screen.dart';

class PromotionDetailScreen extends StatefulWidget {
  final String promotionId;

  /// Inyectable para tests.
  final ApiService? apiOverride;

  const PromotionDetailScreen({
    super.key,
    required this.promotionId,
    this.apiOverride,
  });

  @override
  State<PromotionDetailScreen> createState() =>
      _PromotionDetailScreenState();
}

class _PromotionDetailScreenState extends State<PromotionDetailScreen> {
  late final ApiService _api;

  BroadcastPromotion? _promotion;
  List<PromotionDelivery> _deliveries = [];
  bool _loading = true;
  String? _error;

  static const String _publicHost = ApiConfig.publicSiteUrl;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _api.getBroadcastPromotion(widget.promotionId);
      final promo = BroadcastPromotion.fromJson(res);
      final rawDeliveries = (res['deliveries'] as List?) ?? const [];
      final deliveries = rawDeliveries
          .whereType<Map<String, dynamic>>()
          .map(PromotionDelivery.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _promotion = promo;
        _deliveries = deliveries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar la promoción';
      });
    }
  }

  Future<void> _edit() async {
    final promo = _promotion;
    if (promo == null) return;
    HapticFeedback.lightImpact();
    final updated = await Navigator.of(context).push<BroadcastPromotion>(
      MaterialPageRoute(
        builder: (_) => PromotionFormScreen(
          existing: promo,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    if (updated != null) await _load();
  }

  void _openSendSheet() {
    final promo = _promotion;
    if (promo == null) return;
    HapticFeedback.lightImpact();
    showSendPromotionSheet(
      context,
      promotion: promo,
      publicHost: _publicHost,
      onWhatsAppQueue: _startWhatsAppFlow,
    );
  }

  /// Encadena: elegir audiencia → crear deliveries → cola modo express.
  Future<void> _startWhatsAppFlow() async {
    final promo = _promotion;
    if (promo == null) return;

    final audience =
        await Navigator.of(context).push<List<Customer>>(
      MaterialPageRoute(
        builder: (_) => AudienceSelectorScreen(
          promotionId: promo.id,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    if (audience == null || audience.isEmpty || !mounted) return;

    // Audiencia grande → ofrecer la Lista de Difusión como alternativa.
    if (audience.length > 50) {
      final useBroadcast = await _askBroadcastForLargeAudience();
      if (useBroadcast == true && mounted) {
        _openBroadcastHelper(promo, audience);
        return;
      }
      if (!mounted) return;
    }

    // Crear los deliveries `queued` en backend.
    List<PromotionDelivery> queue;
    try {
      final res = await _api.createPromotionDeliveries(
        promo.id,
        customerIds: audience.map((c) => c.id).toList(),
        channel: PromotionChannel.whatsapp.wire,
      );
      final raw = (res['data'] as List?) ?? const [];
      queue = raw
          .whereType<Map<String, dynamic>>()
          .map(PromotionDelivery.fromJson)
          .toList(growable: false);
    } catch (e) {
      if (mounted) _snack('No se pudo armar la cola de envío');
      return;
    }
    if (queue.isEmpty || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WhatsappQueueScreen(
          promotion: promo,
          deliveries: queue,
          publicHost: _publicHost,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    await _load();
  }

  Future<bool?> _askBroadcastForLargeAudience() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audiencia grande',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        content: const Text(
          'Tiene más de 50 clientes. La cola asistida le tomaría '
          'varios minutos. ¿Prefiere crear una Lista de Difusión de '
          'WhatsApp Business para enviar de un solo toque?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Usar la cola',
                style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Lista de Difusión',
                style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _openBroadcastHelper(
      BroadcastPromotion promo, List<Customer> audience) {
    final link = promo.publicUrl(_publicHost);
    final message = renderPromotionMessage(
      template: promo.messageTemplate,
      // El mensaje de la difusión no se personaliza por cliente — va
      // sin nombre, así que el fallback "Hola 👋" aplica.
      customerName: '',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BroadcastListHelperScreen(
          customers: audience,
          message: link.isEmpty ? message : '$message\n$link',
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Promoción',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
          if (_promotion != null)
            IconButton(
              key: const Key('promo_detail_edit'),
              icon: const Icon(Icons.edit_rounded,
                  color: AppTheme.primary),
              tooltip: 'Editar',
              onPressed: _edit,
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar:
          _promotion == null ? null : _buildSendBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _promotion == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppTheme.warning),
            const SizedBox(height: 12),
            Text(_error ?? 'Promoción no encontrada',
                style: const TextStyle(
                    fontSize: 17, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child:
                  const Text('Reintentar', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
      );
    }

    final promo = _promotion!;
    final state = promo.state;
    final color = promotionStateColor(state);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (promo.imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              promo.imageUrl,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                promo.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                state.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        if (promo.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            promo.description,
            style: const TextStyle(
                fontSize: 16, height: 1.4, color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Vigencia: ${_fmtDate(promo.validFrom)} - '
          '${_fmtDate(promo.validUntil)}',
          style: const TextStyle(
              fontSize: 15, color: AppTheme.textSecondary),
        ),
        if (promo.couponCode.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Cupón: ${promo.couponCode}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildMetrics(promo),
        if (promo.items.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Items en oferta',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ...promo.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.local_offer_rounded,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.productName,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    Text(
                      item.discountPct != null
                          ? '-${item.discountPct!.toStringAsFixed(0)}%'
                          : '\$${item.promoPrice?.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              )),
        ],
        const SizedBox(height: 20),
        const Text(
          'Log de envíos',
          style:
              TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        _buildDeliveryLog(),
      ],
    );
  }

  Widget _buildMetrics(BroadcastPromotion promo) {
    Widget metric(IconData icon, String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.primary, size: 22),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        metric(Icons.group_rounded, 'Audiencia',
            '${promo.audienceCount}'),
        const SizedBox(width: 10),
        metric(Icons.send_rounded, 'Enviados', '${promo.sentCount}'),
        const SizedBox(width: 10),
        metric(Icons.visibility_rounded, 'Visitas',
            '${promo.visitCount}'),
      ],
    );
  }

  Widget _buildDeliveryLog() {
    if (_deliveries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Todavía no le ha enviado esta promoción a nadie.',
          style: TextStyle(
              fontSize: 15, color: AppTheme.textSecondary),
        ),
      );
    }
    return Column(
      key: const Key('promo_delivery_log'),
      children: _deliveries.map((d) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.customerName.isNotEmpty
                            ? d.customerName
                            : 'Cliente',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${d.channel.wire} · ${d.status.label}'
                        '${d.wasVisited ? ' · visitó el link' : ''}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  d.wasVisited
                      ? Icons.visibility_rounded
                      : (d.status == PromotionDeliveryStatus.sent
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded),
                  size: 20,
                  color: d.wasVisited
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSendBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            key: const Key('promo_detail_send'),
            onPressed: _openSendSheet,
            icon: const Icon(Icons.send_rounded, size: 24),
            label: const Text(
              'Enviar promoción',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
