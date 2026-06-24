// Spec: specs/042-modulo-eventos/spec.md
//
// Difusión del evento a los clientes (F042). Espeja el "megáfono" de
// promociones (PromoShareScreen): lista los clientes con consentimiento de
// marketing y abre UN chat de WhatsApp por toque (enviar en ráfaga marca la
// cuenta en Meta), con un mensaje listo que incluye el link de inscripción.
// También permite copiar el mensaje (listas de difusión) y compartir a redes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';
import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../utils/event_money.dart';
import '../../utils/markdown_plain.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'event_feedback.dart';

const _eventAccent = Color(0xFF0EA5E9);

class EventBroadcastScreen extends StatefulWidget {
  final Event event;
  final String? slug;
  final ApiService? apiOverride;

  const EventBroadcastScreen({
    super.key,
    required this.event,
    this.slug,
    this.apiOverride,
  });

  @override
  State<EventBroadcastScreen> createState() => _EventBroadcastScreenState();
}

class _EventBroadcastScreenState extends State<EventBroadcastScreen> {
  late final ApiService _api;
  List<Map<String, dynamic>> _customers = [];
  final Set<String> _sent = {};
  String _businessName = 'nuestro negocio';
  String _slug = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _slug = widget.slug ?? '';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _businessName =
          prefs.getString('vendia_business_name') ?? _businessName;
      if (_slug.isEmpty) {
        _slug = prefs.getString('vendia_store_slug') ?? '';
      }
    } catch (_) {/* ignore */}
    await _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final res = await _api.fetchCustomers(page: 1, perPage: 500);
      final raw = (res['data'] as List?) ?? const [];
      final filtered = raw
          .cast<Map<String, dynamic>>()
          .where((c) =>
              (c['marketing_opt_in'] as bool? ?? false) &&
              (c['phone'] as String? ?? '').trim().length >= 7)
          .toList();
      if (!mounted) return;
      setState(() {
        _customers = filtered;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _catalogLink =>
      _slug.isEmpty ? '' : ApiConfig.publicCatalogUrlFor(_slug);

  String _message(String? customerName) {
    final e = widget.event;
    final hi = (customerName?.trim().isNotEmpty ?? false)
        ? '¡Hola $customerName!'
        : '¡Hola!';
    final price = e.isFree ? 'Gratis' : formatEventMoney(e.price, e.currency);
    final when =
        e.startAt != null ? ' · ${_formatDate(e.startAt!)}' : '';
    final desc = e.description.trim().isEmpty
        ? ''
        : '\n${markdownToWhatsApp(e.description.trim())}';
    final link = _catalogLink.isEmpty ? '' : '\n\nInscríbete aquí: $_catalogLink';
    return '$hi 👋\n'
        'Te invito a *${e.title}* en $_businessName.\n'
        '${EventType.label(e.type)} · ${EventModality.label(e.modality)}$when\n'
        'Inscripción: $price$desc$link';
  }

  String _normalisePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length == 10 && digits.startsWith('3')) digits = '57$digits';
    return digits;
  }

  Future<void> _sendTo(Map<String, dynamic> c) async {
    final phone = _normalisePhone(c['phone'] as String);
    final msg = Uri.encodeComponent(_message(c['name'] as String?));
    HapticFeedback.lightImpact();
    final ok = await launchUrl(Uri.parse('https://wa.me/$phone?text=$msg'),
        mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (ok) {
      setState(() => _sent.add((c['id'] ?? c['phone']).toString()));
    } else {
      showEventSnack(context, 'WhatsApp no está disponible en este dispositivo.',
          kind: EventSnackKind.error);
    }
  }

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: _message(null)));
    showEventSnack(context,
        'Mensaje copiado. Pégalo en una lista de difusión de WhatsApp.',
        kind: EventSnackKind.success);
  }

  void _shareToSocial() {
    Share.share(_message(null), subject: widget.event.title);
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showEventSnack(context, 'No pudimos abrir la app.',
          kind: EventSnackKind.error);
    }
  }

  void _shareWhatsApp() =>
      _openUrl('https://wa.me/?text=${Uri.encodeComponent(_message(null))}');

  void _shareFacebook() {
    if (_catalogLink.isEmpty) {
      _shareToSocial();
      return;
    }
    _openUrl(
        'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_catalogLink)}');
  }

  void _shareX() => _openUrl(
      'https://twitter.com/intent/tweet?text=${Uri.encodeComponent(_message(null))}');

  void _copyLink() {
    if (_catalogLink.isEmpty) {
      showEventSnack(context,
          'Configura el enlace de tu tienda en Perfil del negocio.',
          kind: EventSnackKind.info);
      return;
    }
    Clipboard.setData(ClipboardData(text: _catalogLink));
    showEventSnack(context, 'Link copiado', kind: EventSnackKind.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Difundir evento'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _preview(widget.event),
                const SizedBox(height: 16),
                _messageCard(),
                const SizedBox(height: 16),
                _socialSection(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.groups_rounded, color: _eventAccent),
                    const SizedBox(width: 8),
                    Text('Enviar a mis clientes (${_customers.length})',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Toca enviar para abrir el chat de cada cliente. Envía uno por '
                  'uno: así WhatsApp no marca tu número.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                if (_customers.isEmpty)
                  _emptyCustomers()
                else ...[
                  if (_customers.length > 10) _broadcastTip(),
                  ..._customers.map(_customerTile),
                ],
              ],
            ),
    );
  }

  // Compartir el evento en redes sociales (cada una abre su app/sitio).
  Widget _socialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.public_rounded, color: _eventAccent),
            SizedBox(width: 8),
            Text('Compartir en redes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _socialBtn(
                key: const Key('social_whatsapp'),
                icon: Icons.chat_rounded,
                color: const Color(0xFF25D366),
                label: 'WhatsApp',
                onTap: _shareWhatsApp),
            _socialBtn(
                icon: Icons.facebook_rounded,
                color: const Color(0xFF1877F2),
                label: 'Facebook',
                onTap: _shareFacebook),
            _socialBtn(
                icon: Icons.alternate_email_rounded,
                color: Colors.black,
                label: 'X',
                onTap: _shareX),
            _socialBtn(
                icon: Icons.link_rounded,
                color: Colors.blueGrey,
                label: 'Copiar link',
                onTap: _copyLink),
            _socialBtn(
                key: const Key('social_more'),
                icon: Icons.ios_share_rounded,
                color: _eventAccent,
                label: 'Más',
                onTap: _shareToSocial),
          ],
        ),
      ],
    );
  }

  Widget _socialBtn({
    Key? key,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 58,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _messageCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Mensaje',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: _copyMessage,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copiar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_message('[nombre]'),
              style: const TextStyle(fontSize: 13.5, height: 1.35)),
        ],
      ),
    );
  }

  Widget _customerTile(Map<String, dynamic> c) {
    final id = (c['id'] ?? c['phone']).toString();
    final name = (c['name'] as String?)?.trim();
    final sent = _sent.contains(id);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _eventAccent.withValues(alpha: 0.12),
          child: Text(
            ((name?.isNotEmpty ?? false) ? name![0] : '?').toUpperCase(),
            style: const TextStyle(
                color: _eventAccent, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(name?.isNotEmpty == true ? name! : 'Cliente',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text((c['phone'] as String?) ?? ''),
        trailing: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor:
                sent ? Colors.grey.shade300 : const Color(0xFF25D366),
            foregroundColor: sent ? Colors.black54 : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 38),
          ),
          onPressed: () => _sendTo(c),
          icon: Icon(sent ? Icons.check_rounded : Icons.send_rounded, size: 16),
          label: Text(sent ? 'Enviado' : 'Enviar'),
        ),
      ),
    );
  }

  Widget _broadcastTip() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                    fontSize: 12.5, color: Colors.black87, height: 1.35),
                children: [
                  TextSpan(
                      text: '¿Muchos clientes? ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                      text:
                          'Toca "Copiar" y pega el mensaje en una lista de difusión '
                          'de WhatsApp para enviarlo a todos a la vez.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCustomers() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.contacts_rounded, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('Aún no tienes clientes con consentimiento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Ve a "Clientes" y activa el consentimiento para poder enviarles '
            'mensajes. Mientras tanto, usa "Compartir" o "Copiar" arriba.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _preview(Event e) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 180,
            width: double.infinity,
            color: const Color(0xFFF1F5F9),
            child: e.posterUrl.isNotEmpty
                ? (e.posterUrl.startsWith('data:image')
                    ? Image.memory(
                        base64Decode(
                            e.posterUrl.substring(e.posterUrl.indexOf(',') + 1)),
                        fit: BoxFit.contain)
                    : Image.network(e.posterUrl, fit: BoxFit.contain))
                : Container(
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0EA5E9), Color(0xFF1E3A8A)],
                      ),
                    ),
                    child: const Text('🎫', style: TextStyle(fontSize: 44)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(formatEventPrice(e.price, e.currency),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _eventAccent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    final l = d.toLocal();
    return '${l.day} de ${months[l.month - 1]} de ${l.year}';
  }
}
