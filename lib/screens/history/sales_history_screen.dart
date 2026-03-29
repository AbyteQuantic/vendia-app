import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import 'receipt_detail_screen.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  String _selectedFilter = 'hoy';
  final _searchCtrl = TextEditingController();

  // Mock sale data
  final List<Map<String, dynamic>> _mockSales = [
    {
      'time': '2:30 PM',
      'total': '\$15.000',
      'method': 'cash',
      'receipt': '#1045',
    },
    {
      'time': '1:15 PM',
      'total': '\$8.500',
      'method': 'card',
      'receipt': '#1044',
    },
    {
      'time': '12:00 PM',
      'total': '\$23.200',
      'method': 'transfer',
      'receipt': '#1043',
    },
    {
      'time': '10:45 AM',
      'total': '\$5.000',
      'method': 'cash',
      'receipt': '#1042',
    },
    {
      'time': '9:20 AM',
      'total': '\$32.800',
      'method': 'card',
      'receipt': '#1041',
    },
  ];

  IconData _methodIcon(String method) {
    return switch (method) {
      'card' => Icons.credit_card_rounded,
      'transfer' => Icons.swap_horiz_rounded,
      _ => Icons.payments_rounded,
    };
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Historial de Ventas',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Historial de ventas',
        child: Column(
          children: [
            // Filter pills
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Row(
                children: [
                  _FilterPill(
                    label: 'Hoy',
                    value: 'hoy',
                    selected: _selectedFilter,
                    onTap: (v) => setState(() => _selectedFilter = v),
                  ),
                  const SizedBox(width: 10),
                  _FilterPill(
                    label: 'Ayer',
                    value: 'ayer',
                    selected: _selectedFilter,
                    onTap: (v) => setState(() => _selectedFilter = v),
                  ),
                  const SizedBox(width: 10),
                  _FilterPill(
                    label: 'Elegir Fecha',
                    value: 'fecha',
                    selected: _selectedFilter,
                    isOutline: true,
                    onTap: (v) {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedFilter = v);
                    },
                  ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'Buscar por recibo o total',
                    hintStyle: const TextStyle(
                        fontSize: 18, color: AppTheme.textSecondary),
                    prefixIcon: const Icon(Icons.search_rounded, size: 24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: AppTheme.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sale cards list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _mockSales.length,
                itemBuilder: (_, i) {
                  final sale = _mockSales[i];
                  return _SaleCard(
                    time: sale['time'] as String,
                    total: sale['total'] as String,
                    method: sale['method'] as String,
                    receipt: sale['receipt'] as String,
                    methodIcon: _methodIcon(sale['method'] as String),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceiptDetailScreen(
                            receiptNumber: sale['receipt'] as String,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final bool isOutline;
  final ValueChanged<String> onTap;

  const _FilterPill({
    required this.label,
    required this.value,
    required this.selected,
    this.isOutline = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap(value);
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.textPrimary
              : (isOutline ? Colors.transparent : AppTheme.surfaceGrey),
          borderRadius: BorderRadius.circular(22),
          border: isOutline && !isSelected
              ? Border.all(color: AppTheme.borderColor, width: 1.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final String time;
  final String total;
  final String method;
  final String receipt;
  final IconData methodIcon;
  final VoidCallback onTap;

  const _SaleCard({
    required this.time,
    required this.total,
    required this.method,
    required this.receipt,
    required this.methodIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Venta $receipt, $total, $time',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Time
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    receipt,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Method icon
              Icon(methodIcon, size: 24, color: AppTheme.textSecondary),
              const SizedBox(width: 16),
              // Total
              Text(
                total,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  size: 24, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
