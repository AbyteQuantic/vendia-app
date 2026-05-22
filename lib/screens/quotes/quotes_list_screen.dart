// Spec: specs/031-cotizaciones/spec.md
//
// Pantalla "Mis cotizaciones" (F031 — AC-12).
//
// Lista histórica de las cotizaciones del tenant con:
//   - FilterChips por estado (todas / borrador / enviada / aprobada /
//     rechazada / vencida / convertida).
//   - Buscador por folio o nombre de cliente.
//   - FAB para crear una cotización nueva.
//
// Cada tarjeta muestra folio, cliente, estado coloreado y total. Tap
// navega al detalle.
//
// Solo es alcanzable cuando la capacidad enable_quotes está ON (el
// dashboard la gatea — AC-13).
//
// Gerontodiseño: textos ≥17pt, filas táctiles, probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/quote.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import 'quote_detail_screen.dart';
import 'quote_form_screen.dart';

/// Color del chip de estado de una cotización — compartido por la lista
/// y el detalle.
Color quoteStatusColor(QuoteStatus status) {
  switch (status) {
    case QuoteStatus.borrador:
      return AppTheme.textSecondary;
    case QuoteStatus.enviada:
      return AppTheme.primary;
    case QuoteStatus.aprobada:
      return AppTheme.success;
    case QuoteStatus.convertida:
      return AppTheme.success;
    case QuoteStatus.rechazada:
      return AppTheme.error;
    case QuoteStatus.vencida:
      return AppTheme.warning;
    case QuoteStatus.reemplazada:
      return AppTheme.textSecondary;
  }
}

class QuotesListScreen extends StatefulWidget {
  /// Inyectable para tests — en producción se usa el ApiService default.
  final ApiService? apiOverride;

  const QuotesListScreen({super.key, this.apiOverride});

  @override
  State<QuotesListScreen> createState() => _QuotesListScreenState();
}

class _QuotesListScreenState extends State<QuotesListScreen> {
  late final ApiService _api;
  final _searchCtrl = TextEditingController();

  List<Quote> _quotes = [];
  bool _loading = true;
  String _query = '';
  String? _error;

  /// Estado de filtro activo. Null → "Todas".
  QuoteStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _api.listQuotes(
        status: _statusFilter?.wire,
        limit: 200,
      );
      final raw = (res['data'] as List?) ?? const [];
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(Quote.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _quotes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar las cotizaciones';
      });
    }
  }

  /// Filtrado client-side por folio / cliente y por estado.
  List<Quote> get _filtered {
    final q = _query.trim().toLowerCase();
    return _quotes.where((quote) {
      if (_statusFilter != null && quote.status != _statusFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return quote.folio.toLowerCase().contains(q) ||
          quote.customerName.toLowerCase().contains(q);
    }).toList();
  }

  void _onStatusFilterChanged(QuoteStatus? status) {
    HapticFeedback.selectionClick();
    setState(() => _statusFilter = status);
    // Re-consultamos para que el filtro también aplique server-side.
    _load();
  }

  Future<void> _openNewQuote() async {
    HapticFeedback.lightImpact();
    final created = await Navigator.of(context).push<Quote>(
      MaterialPageRoute(
        builder: (_) => QuoteFormScreen(apiOverride: widget.apiOverride),
      ),
    );
    if (created != null) await _load();
  }

  Future<void> _openDetail(Quote quote) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuoteDetailScreen(
          quoteId: quote.id,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    await _load();
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
          'Mis cotizaciones',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('quotes_new_fab'),
        onPressed: _openNewQuote,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nueva',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: TextField(
                key: const Key('quotes_search'),
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Buscar por folio o cliente',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppTheme.primary, size: 24),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            _filterChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    // (label, status). Status null → "Todas".
    const filters = <(String, QuoteStatus?)>[
      ('Todas', null),
      ('Borrador', QuoteStatus.borrador),
      ('Enviada', QuoteStatus.enviada),
      ('Aprobada', QuoteStatus.aprobada),
      ('Rechazada', QuoteStatus.rechazada),
      ('Vencida', QuoteStatus.vencida),
      ('Convertida', QuoteStatus.convertida),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        key: const Key('quotes_filter_chips'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, status) = filters[i];
          final selected = _statusFilter == status;
          return FilterChip(
            key: Key('quotes_filter_${status?.wire ?? 'all'}'),
            label: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            selected: selected,
            showCheckmark: false,
            backgroundColor: Colors.white,
            selectedColor: AppTheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.borderColor),
            ),
            onSelected: (_) => _onStatusFilterChanged(status),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
    final results = _filtered;
    if (results.isEmpty) {
      final emptyMsg = _query.trim().isEmpty && _statusFilter == null
          ? 'Aún no tiene cotizaciones.\n'
              'Toque "Nueva" para crear la primera.'
          : 'No se encontraron cotizaciones con ese filtro.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                emptyMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('quotes_list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _QuoteCard(
          quote: results[i],
          onTap: () => _openDetail(results[i]),
        ),
      ),
    );
  }
}

/// Tarjeta de una cotización en la lista.
class _QuoteCard extends StatelessWidget {
  final Quote quote;
  final VoidCallback onTap;

  const _QuoteCard({required this.quote, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = quoteStatusColor(quote.status);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      quote.folio.isNotEmpty ? quote.folio : 'Sin folio',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      quote.status.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_rounded,
                      size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      quote.customerName.isNotEmpty
                          ? quote.customerName
                          : 'Sin cliente',
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatCOP(quote.total),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
