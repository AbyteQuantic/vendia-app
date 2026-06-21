// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/format_cop.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';

/// Mandados / Pendientes de compra (Spec 077): las listas de compra que el
/// tenant asignó (a proveedor/contacto/empleado), con su estado. Permite
/// marcar comprado/cancelado y reenviar.
class MandadosScreen extends StatefulWidget {
  final ApiService? api;
  const MandadosScreen({super.key, this.api});

  @override
  State<MandadosScreen> createState() => _MandadosScreenState();
}

class _MandadosScreenState extends State<MandadosScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _errands = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _api.fetchErrands();
      if (!mounted) return;
      setState(() {
        _errands = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar los pendientes.';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await _api.updateErrandStatus(id, status);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo actualizar.'), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _resend(Map<String, dynamic> e) async {
    final lines = (e['lines'] as List?) ?? [];
    final b = StringBuffer('Buenos días, necesito comprar:\n');
    for (final l in lines) {
      final m = Map<String, dynamic>.from(l as Map);
      final q = (m['qty'] as num?)?.toDouble() ?? 0;
      final qs = q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
      b.writeln('• ${m['name']} — $qs ${m['unit']}');
    }
    await Share.share(b.toString(), subject: 'Lista de compra');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Pendientes de compra', style: AppUI.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : _errands.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(AppUI.s24),
                      child: Text('Aún no tiene mandados.\nEnvíe una lista de compra desde "Comprar lo que falta".',
                          textAlign: TextAlign.center, style: AppUI.bodySoft),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        key: const Key('mandados_list'),
                        padding: const EdgeInsets.all(AppUI.s16),
                        itemCount: _errands.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
                        itemBuilder: (_, i) => _card(_errands[i]),
                      ),
                    ),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final id = e['id'].toString();
    final status = (e['status'] ?? 'pendiente').toString();
    final who = (e['assignee_name'] ?? '').toString();
    final total = (e['total_estimated'] as num?)?.toDouble() ?? 0;
    final lines = (e['lines'] as List?) ?? [];
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(who.isNotEmpty ? who : 'Compra de insumos', style: AppUI.bodyStrong)),
          _statusBadge(status),
        ]),
        const SizedBox(height: 4),
        Text('${lines.length} producto(s) · ${formatCOP(total)}', style: AppUI.bodySoft),
        const SizedBox(height: AppUI.s8),
        Row(children: [
          TextButton.icon(
            key: Key('resend_$id'),
            onPressed: () => _resend(e),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Reenviar'),
          ),
          const Spacer(),
          if (status != 'comprado' && status != 'cancelado') ...[
            TextButton(
              onPressed: () => _setStatus(id, 'cancelado'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: Key('done_$id'),
              onPressed: () => _setStatus(id, 'comprado'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success, foregroundColor: Colors.white, elevation: 0),
              child: const Text('Comprado'),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _statusBadge(String s) {
    final color = s == 'comprado'
        ? AppTheme.success
        : s == 'cancelado'
            ? AppTheme.error
            : s == 'enviado'
                ? AppTheme.primary
                : AppTheme.warning;
    return MinimalBadge(label: s, color: color);
  }
}
