import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Detailed list of products whose expiration date falls within the
/// backend's warning window. Read-only for now — the shopkeeper uses
/// this list to plan promotions or rotate stock; editing dates still
/// happens from the inventory screen.
class ExpiringProductsScreen extends StatefulWidget {
  const ExpiringProductsScreen({super.key});

  @override
  State<ExpiringProductsScreen> createState() =>
      _ExpiringProductsScreenState();
}

class _ExpiringProductsScreenState extends State<ExpiringProductsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  static const _monthAbbr = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ApiService(AuthService());
      final list = await api.fetchExpiringProducts();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo cargar la lista. Revise su conexión.';
          _loading = false;
        });
      }
    }
  }

  /// Days between today and the given ISO date. Negative = already expired.
  int? _daysUntil(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final expDate = DateTime(parsed.year, parsed.month, parsed.day);
    return expDate.difference(todayDate).inDays;
  }

  String _displayDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return '${parsed.day} ${_monthAbbr[parsed.month - 1]} ${parsed.year}';
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Por vencer',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, style: const TextStyle(fontSize: 17)),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.check_circle_rounded,
              size: 80, color: AppTheme.success),
          SizedBox(height: 12),
          Center(
            child: Text(
              'No hay productos por vencer',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Todo su inventario está vigente',
              style: TextStyle(
                  fontSize: 16, color: AppTheme.textSecondary),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = _items[i];
        final name = p['name'] as String? ?? 'Sin nombre';
        final stock = p['stock'] as int? ?? 0;
        final iso = p['expiry_date'] as String?;
        final days = _daysUntil(iso);

        Color severityColor;
        String severityLabel;
        if (days == null) {
          severityColor = AppTheme.textSecondary;
          severityLabel = '—';
        } else if (days < 0) {
          severityColor = AppTheme.error;
          severityLabel = 'Vencido hace ${-days} día${-days == 1 ? '' : 's'}';
        } else if (days == 0) {
          severityColor = AppTheme.error;
          severityLabel = 'Vence hoy';
        } else if (days <= 3) {
          severityColor = AppTheme.error;
          severityLabel = 'Vence en $days día${days == 1 ? '' : 's'}';
        } else {
          severityColor = AppTheme.warning;
          severityLabel = 'Vence en $days días';
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: severityColor.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.event_rounded,
                    color: severityColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      severityLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: severityColor,
                      ),
                    ),
                    if (iso != null && iso.isNotEmpty)
                      Text(
                        '${_displayDate(iso)} · Stock: $stock',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
