import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Post-save "megáfono" view — shows the banner in large format and
/// gives the shopkeeper two distribution paths: a WhatsApp broadcast
/// to opted-in customers, or a copy-paste fallback.
///
/// Sending to many contacts via `wa.me/?text=` in rapid succession is
/// how Meta flags accounts, so the flow opens ONE chat per tap — the
/// user drives the pace. For a store with 100+ opted-in customers we
/// also surface the "lista de difusión" suggestion.
class PromoShareScreen extends StatefulWidget {
  final String promoName;
  final String? bannerUrl;
  final List<String> products;
  final double totalPromo;

  const PromoShareScreen({
    super.key,
    required this.promoName,
    required this.bannerUrl,
    required this.products,
    required this.totalPromo,
  });

  @override
  State<PromoShareScreen> createState() => _PromoShareScreenState();
}

class _PromoShareScreenState extends State<PromoShareScreen> {
  List<Map<String, dynamic>> _eligibleCustomers = [];
  bool _loadingCustomers = true;
  String _businessName = '';
  String _storeSlug = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadBusinessCtx();
  }

  Future<void> _loadBusinessCtx() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _businessName = prefs.getString('vendia_business_name') ?? 'nuestra tienda';
      _storeSlug = prefs.getString('vendia_store_slug') ?? '';
    });
  }

  Future<void> _loadCustomers() async {
    try {
      final api = ApiService(AuthService());
      final res = await api.fetchCustomers(page: 1, perPage: 500);
      final raw = (res['data'] as List?) ?? const [];
      final filtered = raw
          .cast<Map<String, dynamic>>()
          .where((c) =>
              (c['marketing_opt_in'] as bool? ?? false) &&
              (c['phone'] as String? ?? '').trim().length >= 7)
          .toList();
      if (!mounted) return;
      setState(() {
        _eligibleCustomers = filtered;
        _loadingCustomers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCustomers = false);
    }
  }

  String _cop(num n) {
    final i = n.round();
    final s = i.toString();
    final buf = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i2 = start; i2 < s.length; i2 += 3) {
      if (i2 > 0) buf.write('.');
      buf.write(s.substring(i2, i2 + 3));
    }
    return buf.toString();
  }

  String _buildMessage(String? customerName) {
    final hi = (customerName?.isNotEmpty ?? false) ? '¡Hola $customerName!' : '¡Hola!';
    final link = _storeSlug.isEmpty
        ? ''
        : '\nPide aquí: https://vendia.co/$_storeSlug/menu';
    return '$hi 👋\n'
        'Tenemos una súper promo en $_businessName:\n'
        '🎉 *${widget.promoName}*\n'
        'Solo por ${_cop(widget.totalPromo)} te llevas: ${widget.products.join(', ')}.$link';
  }

  String _normalisePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length == 10 && digits.startsWith('3')) {
      digits = '57$digits'; // Colombian mobile
    }
    return digits;
  }

  Future<void> _openWhatsAppFor(Map<String, dynamic> c) async {
    final phone = _normalisePhone(c['phone'] as String);
    final msg = Uri.encodeComponent(_buildMessage(c['name'] as String?));
    final url = Uri.parse('https://wa.me/$phone?text=$msg');
    HapticFeedback.lightImpact();
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('WhatsApp no está disponible en este dispositivo')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al abrir WhatsApp: $e')));
      }
    }
  }

  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: _buildMessage(null)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Mensaje copiado. Pégalo en una lista de difusión de WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
        title: const Text(
          '¡Promo lista! 🎉',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _bannerTile(),
            const SizedBox(height: 16),
            Text(
              widget.promoName,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              widget.products.join(' · '),
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _broadcastCard(),
            const SizedBox(height: 12),
            _copyCard(),
            if (_eligibleCustomers.length > 10) ...[
              const SizedBox(height: 12),
              _broadcastTipCard(),
            ],
            if (!_loadingCustomers && _eligibleCustomers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Ningún cliente tiene marketing habilitado todavía. '
                    'Ve a "Clientes" y activa el consentimiento para enviarles '
                    'promociones por WhatsApp.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bannerTile() {
    final url = widget.bannerUrl;
    // 16:9 — consistente con el preview del PromoBuilderStep4 y con el
    // slot "Special Offers" del catálogo web. Si dejáramos esto 1:1 el
    // usuario vería aquí un cuadrado, compartiría por WhatsApp una
    // imagen horizontal, y en el catálogo web la imagen quedaría cover
    // recortada — tres resultados distintos del "mismo banner".
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null
            ? const Center(
                child: Icon(Icons.image_outlined,
                    size: 64, color: AppTheme.textSecondary),
              )
            : url.startsWith('http') || url.startsWith('data:')
                ? Image.network(url, fit: BoxFit.cover)
                : Image.file(File(url), fit: BoxFit.cover),
      ),
    );
  }

  Widget _broadcastCard() {
    final count = _eligibleCustomers.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_rounded,
                  color: Color(0xFF25D366), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Enviar a tus clientes',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      _loadingCustomers
                          ? 'Cargando contactos…'
                          : '$count clientes con WhatsApp habilitado',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingCustomers)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._eligibleCustomers.map(_customerTile),
        ],
      ),
    );
  }

  Widget _customerTile(Map<String, dynamic> c) {
    final name = (c['name'] as String?) ?? 'Cliente';
    final phone = (c['phone'] as String?) ?? '';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: AppTheme.primary, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(name, style: const TextStyle(fontSize: 16)),
      subtitle: Text(phone),
      trailing: ElevatedButton.icon(
        onPressed: () => _openWhatsAppFor(c),
        icon: const Icon(Icons.send_rounded, size: 18),
        label: const Text('Enviar'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _copyCard() {
    return InkWell(
      onTap: _copyMessage,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.content_copy_rounded),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Copiar mensaje para pegar en una lista de difusión',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _broadcastTipCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.tips_and_updates_rounded,
              color: AppTheme.warning, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tienes muchos contactos — te recomendamos crear una "lista de '
              'difusión" en WhatsApp y pegar el mensaje copiado. Así envías a '
              'todos de una sola vez y evitas que Meta te bloquee.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
