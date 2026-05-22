// Spec: specs/033-difusion-promociones/spec.md
//
// Pantalla "Mis promociones" (F033 — spec §4 "Histórico", AC-09).
//
// Lista histórica de las promociones de difusión del tenant con:
//   - FilterChips por estado (todas / activas / programadas / vencidas).
//   - FAB para crear una promoción nueva.
//   - Cada tarjeta muestra título, estado, vigencia y métricas básicas
//     (audiencia / enviados / visitas).
//
// Solo es alcanzable cuando la capacidad enable_promotions está ON (el
// dashboard la gatea — AC-11).
//
// Gerontodiseño: textos ≥17pt, filas táctiles, probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/broadcast_promotion.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'promotion_detail_screen.dart';
import 'promotion_form_screen.dart';

/// Color del chip de estado de una promoción.
Color promotionStateColor(BroadcastPromotionState state) {
  switch (state) {
    case BroadcastPromotionState.scheduled:
      return AppTheme.warning;
    case BroadcastPromotionState.active:
      return AppTheme.success;
    case BroadcastPromotionState.expired:
      return AppTheme.textSecondary;
  }
}

class PromotionsListScreen extends StatefulWidget {
  /// Inyectable para tests.
  final ApiService? apiOverride;

  const PromotionsListScreen({super.key, this.apiOverride});

  @override
  State<PromotionsListScreen> createState() => _PromotionsListScreenState();
}

class _PromotionsListScreenState extends State<PromotionsListScreen> {
  late final ApiService _api;

  List<BroadcastPromotion> _promotions = [];
  bool _loading = true;
  String? _error;

  /// Filtro activo. Null → todas.
  BroadcastPromotionState? _filter;

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
      final res = await _api.listBroadcastPromotions();
      final raw = (res['data'] as List?) ?? const [];
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(BroadcastPromotion.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _promotions = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar las promociones';
      });
    }
  }

  List<BroadcastPromotion> get _filtered {
    if (_filter == null) return _promotions;
    final now = DateTime.now();
    return _promotions.where((p) => p.stateAt(now) == _filter).toList();
  }

  Future<void> _openNew() async {
    HapticFeedback.lightImpact();
    final created = await Navigator.of(context).push<BroadcastPromotion>(
      MaterialPageRoute(
        builder: (_) =>
            PromotionFormScreen(apiOverride: widget.apiOverride),
      ),
    );
    if (created != null) await _load();
  }

  Future<void> _openDetail(BroadcastPromotion promo) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PromotionDetailScreen(
          promotionId: promo.id,
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
          'Mis promociones',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('promotions_new_fab'),
        onPressed: _openNew,
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
            _filterChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    const filters = <(String, BroadcastPromotionState?)>[
      ('Todas', null),
      ('Activas', BroadcastPromotionState.active),
      ('Programadas', BroadcastPromotionState.scheduled),
      ('Vencidas', BroadcastPromotionState.expired),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        key: const Key('promotions_filter_chips'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, state) = filters[i];
          final selected = _filter == state;
          return FilterChip(
            key: Key('promotions_filter_${state?.name ?? 'all'}'),
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
            onSelected: (_) {
              HapticFeedback.selectionClick();
              setState(() => _filter = state);
            },
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                _filter == null
                    ? 'Aún no tiene promociones.\n'
                        'Toque "Nueva" para crear la primera.'
                    : 'No hay promociones con ese filtro.',
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
        key: const Key('promotions_list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _PromotionCard(
          promotion: results[i],
          onTap: () => _openDetail(results[i]),
        ),
      ),
    );
  }
}

/// Tarjeta de una promoción en la lista.
class _PromotionCard extends StatelessWidget {
  final BroadcastPromotion promotion;
  final VoidCallback onTap;

  const _PromotionCard({required this.promotion, required this.onTap});

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = promotion.state;
    final color = promotionStateColor(state);
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
                      promotion.title.isNotEmpty
                          ? promotion.title
                          : 'Sin título',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.event_rounded,
                      size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Vigencia: ${_fmtDate(promotion.validFrom)} - '
                    '${_fmtDate(promotion.validUntil)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Metric(
                    icon: Icons.group_rounded,
                    label: 'Audiencia',
                    value: '${promotion.audienceCount}',
                  ),
                  _Metric(
                    icon: Icons.send_rounded,
                    label: 'Enviados',
                    value: '${promotion.sentCount}',
                  ),
                  _Metric(
                    icon: Icons.visibility_rounded,
                    label: 'Visitas',
                    value: '${promotion.visitCount}',
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

/// Una métrica compacta de la tarjeta.
class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(
            '$value ',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
