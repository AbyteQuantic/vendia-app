// Spec: specs/033-difusion-promociones/spec.md
//
// Selector de audiencia de una promoción (F033 — spec §4, AC-04).
//
// El dueño elige a quién avisarle la promoción:
//   - 5 FilterChips RFM pre-armados (Todos / Frecuentes / VIP /
//     Dormidos / Recientes) — al tocar uno se consulta la audiencia al
//     backend.
//   - "A mano": lista de clientes con checkbox + buscador.
//   - Contador en vivo: "Audiencia: 47 clientes seleccionados".
//   - Banner contextual según el tamaño (AudienceSizeAdvisor).
//
// Al confirmar, devuelve la lista de Customer seleccionados al llamador
// (la promotion_detail_screen) que dispara la cola o la Lista de
// Difusión.
//
// Gerontodiseño: chips grandes, filas táctiles ≥48dp, textos ≥17pt,
// probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/customer.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/promotion_audience_filter.dart';
import 'audience_size_advisor.dart';

class AudienceSelectorScreen extends StatefulWidget {
  /// UUID de la promoción cuya audiencia se está armando.
  final String promotionId;

  /// Inyectable para tests.
  final ApiService? apiOverride;

  const AudienceSelectorScreen({
    super.key,
    required this.promotionId,
    this.apiOverride,
  });

  @override
  State<AudienceSelectorScreen> createState() =>
      _AudienceSelectorScreenState();
}

class _AudienceSelectorScreenState extends State<AudienceSelectorScreen> {
  late final ApiService _api;
  final _searchCtrl = TextEditingController();

  /// Filtro RFM activo. Default: todos.
  PromotionAudienceFilter _filter = PromotionAudienceFilter.all;

  /// Resultado del filtro RFM activo — los clientes que el backend
  /// devolvió para ese segmento.
  List<Customer> _candidates = [];

  /// IDs de los clientes efectivamente seleccionados. En modo RFM son
  /// todos los candidatos; en modo manual los marca el dueño.
  final Set<String> _selectedIds = {};

  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _loadFilter(PromotionAudienceFilter.all);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isManual => _filter == PromotionAudienceFilter.manual;

  /// Carga la audiencia para [filter]. Para los filtros RFM selecciona
  /// automáticamente todos los candidatos; para `manual` carga la lista
  /// completa de clientes y deja la selección al dueño.
  Future<void> _loadFilter(PromotionAudienceFilter filter) async {
    setState(() {
      _filter = filter;
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.fetchPromotionAudience(
        widget.promotionId,
        filter: filter.wire,
      );
      final raw = (res['data'] as List?) ?? const [];
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(Customer.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _selectedIds
          ..clear()
          // Filtros RFM → todos seleccionados de entrada. Manual → el
          // dueño elige, así que arranca vacío.
          ..addAll(filter == PromotionAudienceFilter.manual
              ? const <String>[]
              : list
                  .where((c) => c.phone.trim().isNotEmpty)
                  .map((c) => c.id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar la audiencia';
      });
    }
  }

  void _onFilterChip(PromotionAudienceFilter filter) {
    HapticFeedback.selectionClick();
    _loadFilter(filter);
  }

  void _toggleCustomer(Customer c, bool selected) {
    HapticFeedback.selectionClick();
    setState(() {
      if (selected) {
        _selectedIds.add(c.id);
      } else {
        _selectedIds.remove(c.id);
      }
    });
  }

  /// Clientes seleccionados (objetos completos) — la audiencia final.
  List<Customer> get _selectedCustomers =>
      _candidates.where((c) => _selectedIds.contains(c.id)).toList();

  List<Customer> get _visibleCandidates {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _candidates;
    return _candidates
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.phone.toLowerCase().contains(q))
        .toList();
  }

  void _confirm() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(_selectedCustomers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: const Text(
          'Elegir audiencia',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterChips(),
            _buildCounter(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildFilterChips() {
    const filters = PromotionAudienceFilter.values;
    return SizedBox(
      height: 54,
      child: ListView.separated(
        key: const Key('audience_filter_chips'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final filter = filters[i];
          final selected = _filter == filter;
          return FilterChip(
            key: Key('audience_filter_${filter.wire}'),
            label: Text(
              filter.label,
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
            onSelected: (_) => _onFilterChip(filter),
          );
        },
      ),
    );
  }

  Widget _buildCounter() {
    final count = _selectedIds.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audiencia: $count '
            '${count == 1 ? 'cliente seleccionado' : 'clientes seleccionados'}',
            key: const Key('audience_counter'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _filter.description,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          AudienceSizeAdvisor(count: count),
        ],
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
              onPressed: () => _loadFilter(_filter),
              child:
                  const Text('Reintentar', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
      );
    }
    if (_candidates.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No hay clientes en este segmento.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 17, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    final visible = _visibleCandidates;
    return Column(
      children: [
        if (_isManual)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              key: const Key('audience_search'),
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o teléfono',
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
        Expanded(
          child: ListView.separated(
            key: const Key('audience_customer_list'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: visible.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) => _customerTile(visible[i]),
          ),
        ),
      ],
    );
  }

  Widget _customerTile(Customer c) {
    final hasPhone = c.phone.trim().isNotEmpty;
    final selected = _selectedIds.contains(c.id);
    return CheckboxListTile(
      key: Key('audience_customer_${c.id}'),
      value: selected,
      // Sin teléfono → no se puede mandar por WhatsApp (spec R4).
      onChanged: hasPhone ? (v) => _toggleCustomer(c, v ?? false) : null,
      activeColor: AppTheme.primary,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(
        c.name.isNotEmpty ? c.name : 'Cliente sin nombre',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: hasPhone ? AppTheme.textPrimary : Colors.grey,
        ),
      ),
      subtitle: Text(
        hasPhone ? c.phone : 'Sin teléfono',
        style: TextStyle(
          fontSize: 14,
          color: hasPhone ? AppTheme.textSecondary : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final count = _selectedIds.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            key: const Key('audience_confirm'),
            onPressed: count == 0 ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.borderColor,
            ),
            child: Text(
              count == 0
                  ? 'Seleccione clientes'
                  : 'Continuar con $count '
                      '${count == 1 ? 'cliente' : 'clientes'}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}
