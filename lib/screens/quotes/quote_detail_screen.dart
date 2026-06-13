// Spec: specs/031-cotizaciones/spec.md
//       specs/032-email-saliente/spec.md  (pasa tenantName al canal Email)
//
// Pantalla "Detalle de cotización" (F031 — AC-09).
//
// Muestra una cotización completa: header con folio + estado coloreado,
// cliente, líneas de items, totales, vigencia y nota. Las acciones son
// contextuales según el estado (FSM del plan §3):
//   - Enviar      → solo en `borrador`.
//   - Convertir en venta → solo en `aprobada`.
//   - Editar      → en `borrador` y `enviada` (AC-11).
//   - Reenviar    → en `enviada` (reabre la bottom-sheet de envío).
//
// El detalle puede recibir la [Quote] completa (cuando viene de la
// lista con datos cacheados) o solo el [quoteId] y la carga sola.
//
// Gerontodiseño: textos ≥17pt, botones ≥56dp, probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/quote.dart';
import '../../models/quote_item.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import '../../widgets/send_quote_sheet.dart';
import 'quote_form_screen.dart';
import 'quotes_list_screen.dart' show quoteStatusColor;

class QuoteDetailScreen extends StatefulWidget {
  /// UUID de la cotización a mostrar. Requerido cuando no se pasa
  /// [initialQuote].
  final String quoteId;

  /// Cotización ya cargada — evita un fetch extra si la lista la tenía.
  /// Aun así se refresca desde el servidor al montar.
  final Quote? initialQuote;

  /// Inyectable para tests.
  final ApiService? apiOverride;

  const QuoteDetailScreen({
    super.key,
    required this.quoteId,
    this.initialQuote,
    this.apiOverride,
  });

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  late final ApiService _api;
  late final AuthService _auth;

  Quote? _quote;
  bool _loading = true;
  bool _actionRunning = false;
  String? _error;

  /// Host público del catálogo — usado para armar el link de la
  /// cotización en la bottom-sheet de envío.
  String _publicHost = 'https://tienda.vendia.store';

  /// Nombre del negocio — usado por el canal Email (F032) para el
  /// asunto y cuerpo del correo. Se carga del almacenamiento local.
  String _tenantName = '';

  @override
  void initState() {
    super.initState();
    _auth = AuthService();
    _api = widget.apiOverride ?? ApiService(_auth);
    _quote = widget.initialQuote;
    _load();
    _loadPublicHost();
    _loadTenantName();
  }

  /// Carga el nombre del negocio para precargar el email (F032).
  /// Falla en silencio — el sheet usa un texto genérico si queda vacío.
  Future<void> _loadTenantName() async {
    try {
      final name = await _auth.getBusinessName();
      if (name != null && name.trim().isNotEmpty && mounted) {
        setState(() => _tenantName = name.trim());
      }
    } catch (_) {
      // Mantener vacío.
    }
  }

  Future<void> _load() async {
    if (mounted && _quote == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _api.getQuote(widget.quoteId);
      if (!mounted) return;
      setState(() {
        _quote = Quote.fromJson(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_quote == null) {
          _error = 'No se pudo cargar la cotización';
        }
      });
    }
  }

  /// Resuelve el origen del catálogo público. Falla en silencio — el
  /// default (`tienda.vendia.store`) cubre el caso offline.
  Future<void> _loadPublicHost() async {
    try {
      final slug = await _api.fetchStoreSlug();
      final base = (slug['base_url'] as String?)?.trim();
      if (base != null && base.isNotEmpty) {
        final uri = Uri.tryParse(base);
        if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
          final port = uri.hasPort ? ':${uri.port}' : '';
          if (mounted) {
            setState(() => _publicHost = '${uri.scheme}://${uri.host}$port');
          }
        }
      }
    } catch (_) {
      // Mantener el default.
    }
  }

  // ── Acciones ───────────────────────────────────────────────────────

  Future<void> _send() async {
    final quote = _quote;
    if (quote == null) return;
    setState(() => _actionRunning = true);
    HapticFeedback.lightImpact();
    try {
      final res = await _api.sendQuote(quote.id);
      final updated = Quote.fromJson(res);
      if (!mounted) return;
      setState(() {
        _quote = updated;
        _actionRunning = false;
      });
      await showSendQuoteSheet(
        context,
        quote: updated,
        publicHost: _publicHost,
        tenantName: _tenantName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionRunning = false);
      _snack('No se pudo enviar la cotización', isError: true);
    }
  }

  Future<void> _resend() async {
    final quote = _quote;
    if (quote == null) return;
    await showSendQuoteSheet(
      context,
      quote: quote,
      publicHost: _publicHost,
      tenantName: _tenantName,
    );
  }

  /// Marca la cotización como aprobada SIN crear la venta todavía (el
  /// cliente dijo "sí" por WhatsApp/teléfono/en persona — el caso común;
  /// el link público casi no se usa). Cierra el círculo que hoy deja el
  /// estado 'aprobada' inalcanzable. Reusa el endpoint backend que ya
  /// valida la FSM (solo enviada → aprobada).
  Future<void> _markApproved() async {
    final quote = _quote;
    if (quote == null) return;
    final ok = await _confirm(
      title: '¿El cliente aprobó?',
      message: 'La cotización por ${formatCOP(quote.total)} quedará marcada '
          'como APROBADA, lista para convertir en venta.',
      confirmLabel: 'Sí, aprobó',
    );
    if (ok != true) return;
    await _runQuoteAction(
      () => _api.markQuoteStatus(quote.id, QuoteStatus.aprobada.wire),
      okMsg: 'Cotización aprobada. Ya puede convertirla en venta.',
      errMsg: 'No se pudo marcar como aprobada',
    );
  }

  /// Marca la cotización como rechazada (acción destructiva — va en el
  /// menú de overflow, no en un botón grande, para evitar toques por error).
  Future<void> _markRejected() async {
    final quote = _quote;
    if (quote == null) return;
    final ok = await _confirm(
      title: '¿Rechazar esta cotización?',
      message: 'Quedará marcada como RECHAZADA. Podrá duplicarla más '
          'adelante si el cliente cambia de opinión.',
      confirmLabel: 'Rechazar',
      destructive: true,
    );
    if (ok != true) return;
    await _runQuoteAction(
      () => _api.markQuoteStatus(quote.id, QuoteStatus.rechazada.wire),
      okMsg: 'Cotización rechazada.',
      errMsg: 'No se pudo marcar como rechazada',
    );
  }

  /// Convierte la cotización en venta (descuenta inventario). Atajo desde
  /// 'enviada': encadena aprobar + convertir en un solo gesto ("hágale,
  /// me lo llevo"). Desde 'aprobada' convierte directo.
  Future<void> _convert() async {
    final quote = _quote;
    if (quote == null) return;
    final fromSent = quote.status == QuoteStatus.enviada;
    final ok = await _confirm(
      title: 'Convertir en venta',
      message: fromSent
          ? 'Se dará por APROBADA, se creará una venta por '
              '${formatCOP(quote.total)} y se descontará el inventario. '
              '¿Continuar?'
          : 'Se creará una venta con los mismos productos y se descontará '
              'el inventario. ¿Continuar?',
      confirmLabel: 'Convertir',
    );
    if (ok != true) return;

    setState(() => _actionRunning = true);
    HapticFeedback.lightImpact();
    try {
      // enviada → convertida NO es transición legal: primero aprobar.
      if (fromSent) {
        await _api.markQuoteStatus(quote.id, QuoteStatus.aprobada.wire);
      }
      final res = await _api.convertQuote(quote.id);
      // convertQuote devuelve {sale_id, quote} — la cotización actualizada
      // está en res['quote'], NO en el envelope completo (bug previo).
      final quoteJson = (res['quote'] as Map<String, dynamic>?) ?? res;
      final updated = Quote.fromJson(quoteJson);
      if (!mounted) return;
      setState(() {
        _quote = updated;
        _actionRunning = false;
      });
      _snack('Venta creada. Inventario descontado.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionRunning = false);
      _snack('No se pudo convertir la cotización', isError: true);
    }
  }

  /// Diálogo de confirmación estándar (gerontodiseño: texto grande,
  /// botones cómodos, modo USTED).
  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 20)),
        content: Text(message, style: const TextStyle(fontSize: 16, height: 1.35)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            style: destructive
                ? ElevatedButton.styleFrom(backgroundColor: AppTheme.error)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  /// Ejecuta una acción que devuelve la cotización actualizada (envelope
  /// {data: quote} ya desenvuelto por _extractData → un quote map), con
  /// spinner, recarga y snackbar.
  Future<void> _runQuoteAction(
    Future<Map<String, dynamic>> Function() action, {
    required String okMsg,
    required String errMsg,
  }) async {
    setState(() => _actionRunning = true);
    HapticFeedback.lightImpact();
    try {
      final res = await action();
      final updated = Quote.fromJson(res);
      if (!mounted) return;
      setState(() {
        _quote = updated;
        _actionRunning = false;
      });
      _snack(okMsg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionRunning = false);
      final msg = e is AppError && e.message.trim().isNotEmpty
          ? e.message
          : errMsg;
      _snack(msg, isError: true);
    }
  }

  Future<void> _edit() async {
    final quote = _quote;
    if (quote == null) return;
    HapticFeedback.lightImpact();
    final updated = await Navigator.of(context).push<Quote>(
      MaterialPageRoute(
        builder: (_) => QuoteFormScreen(
          existing: quote,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    if (updated != null && mounted) {
      // Editar una `enviada` crea la V2 — recargamos por id de la V2.
      setState(() => _quote = updated);
      await _load();
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
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
        title: Text(
          quote?.folio.isNotEmpty == true ? quote!.folio : 'Cotización',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          if (quote != null && quote.status.canEdit)
            IconButton(
              key: const Key('quote_detail_edit'),
              icon: const Icon(Icons.edit_rounded,
                  color: AppTheme.primary, size: 24),
              tooltip: 'Editar',
              onPressed: _actionRunning ? null : _edit,
            ),
          // "Marcar como rechazada" va en el overflow (acción destructiva,
          // no un botón grande, para evitar toques por error — concilio).
          if (quote != null &&
              (quote.status == QuoteStatus.enviada ||
                  quote.status == QuoteStatus.aprobada))
            PopupMenuButton<String>(
              key: const Key('quote_detail_overflow'),
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppTheme.textPrimary),
              onSelected: (v) {
                if (v == 'reject') _markRejected();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'reject',
                  child: Text('Marcar como rechazada',
                      style: TextStyle(fontSize: 16, color: AppTheme.error)),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: quote == null ? null : _actionBar(quote),
    );
  }

  Widget _buildBody() {
    if (_loading && _quote == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _quote == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppTheme.warning),
            const SizedBox(height: 12),
            Text(_error!,
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
    final quote = _quote!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _statusHeader(quote),
        const SizedBox(height: 16),
        _customerCard(quote),
        const SizedBox(height: 16),
        _itemsCard(quote),
        const SizedBox(height: 16),
        _totalsCard(quote),
        if (quote.note.isNotEmpty) ...[
          const SizedBox(height: 16),
          _noteCard(quote),
        ],
      ],
    );
  }

  Widget _statusHeader(Quote quote) {
    final color = quoteStatusColor(quote.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_rounded, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.folio.isNotEmpty ? quote.folio : 'Sin folio',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Estado: ${quote.status.label}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (quote.validUntil != null)
                  Text(
                    'Válida hasta ${_formatDate(quote.validUntil!)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerCard(Quote quote) {
    return _card(
      child: Row(
        children: [
          const Icon(Icons.person_rounded,
              color: AppTheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              quote.customerName.isNotEmpty
                  ? quote.customerName
                  : 'Sin cliente',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(Quote quote) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Productos y servicios',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (quote.items.isEmpty)
            const Text(
              'Sin líneas.',
              style:
                  TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            )
          else
            ...quote.items.map(_itemRow),
        ],
      ),
    );
  }

  Widget _itemRow(QuoteItem item) {
    final qtyText =
        item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            item.isInventoryItem
                ? Icons.inventory_2_rounded
                : Icons.edit_note_rounded,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '$qtyText x ${formatCOP(item.unitPrice)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatCOP(item.subtotal),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalsCard(Quote quote) {
    return _card(
      child: Column(
        children: [
          _totalRow('Subtotal', quote.subtotal),
          if (quote.discountTotal > 0)
            _totalRow('Descuento', -quote.discountTotal),
          if (quote.taxRate > 0)
            _totalRow(
                'IVA (${(quote.taxRate * 100).round()}%)', quote.taxAmount),
          const Divider(height: 20),
          _totalRow('Total', quote.total, emphasize: true),
        ],
      ),
    );
  }

  Widget _noteCard(Quote quote) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nota',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            quote.note,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 20 : 16,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            formatCOP(amount),
            style: TextStyle(
              fontSize: emphasize ? 20 : 16,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: child,
    );
  }

  /// Barra de acciones contextuales según el estado de la cotización.
  Widget _actionBar(Quote quote) {
    final actions = <Widget>[];

    // Enviar — solo en borrador (AC-06).
    if (quote.status.canSend) {
      actions.add(_primaryButton(
        buttonKey: const Key('quote_detail_send'),
        icon: Icons.send_rounded,
        label: 'Enviar cotización',
        onTap: _send,
      ));
    }

    // ENVIADA — el cliente aún no ha respondido por el link. Lo común es
    // que apruebe por WhatsApp/en persona, así que el tendero necesita
    // cerrar el círculo a mano (concilio 2026-06-13):
    //   PRINCIPAL: "Convertir en venta" (atajo: aprobar + convertir).
    //   SECUNDARIO: "El cliente aprobó" (solo marca aprobada).
    //   SECUNDARIO: "Reenviar cotización".
    if (quote.status == QuoteStatus.enviada) {
      actions.add(_primaryButton(
        buttonKey: const Key('quote_detail_convert'),
        icon: Icons.point_of_sale_rounded,
        label: 'Convertir en venta',
        onTap: _convert,
      ));
      actions.add(_secondaryButton(
        buttonKey: const Key('quote_detail_approve'),
        icon: Icons.check_circle_outline_rounded,
        label: 'El cliente aprobó',
        onTap: _markApproved,
      ));
      actions.add(_secondaryButton(
        buttonKey: const Key('quote_detail_resend'),
        icon: Icons.share_rounded,
        label: 'Reenviar cotización',
        onTap: _resend,
      ));
    }

    // APROBADA — lista para cerrar. Convertir en venta (AC-09).
    if (quote.status.canConvert) {
      actions.add(_primaryButton(
        buttonKey: const Key('quote_detail_convert'),
        icon: Icons.point_of_sale_rounded,
        label: 'Convertir en venta',
        onTap: _convert,
      ));
    }


    if (actions.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: actions,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required Key buttonKey,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          key: buttonKey,
          onPressed: _actionRunning ? null : onTap,
          icon: _actionRunning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Icon(icon, size: 24),
          label: Text(
            label,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  /// Acción secundaria — tinte azul al 10%, texto del color primario,
  /// sin el peso visual del botón principal (jerarquía clara, concilio).
  Widget _secondaryButton({
    required Key buttonKey,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          key: buttonKey,
          onPressed: _actionRunning ? null : onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
            foregroundColor: AppTheme.primary,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          icon: Icon(icon, size: 22),
          label: Text(label),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
