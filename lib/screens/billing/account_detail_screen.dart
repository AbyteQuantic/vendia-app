import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vendia_pos/theme/app_theme.dart';
import 'package:vendia_pos/utils/format_cop.dart';
import 'add_abono_sheet.dart';

/// "Detalle de Cuenta Abierta" — shows an open account's products,
/// abono (partial payment) history, and actions for the cashier.
class AccountDetailScreen extends StatefulWidget {
  final String accountUuid;
  final String label; // e.g. "Mesa 4"
  final String waiterName;

  const AccountDetailScreen({
    super.key,
    required this.accountUuid,
    required this.label,
    required this.waiterName,
  });

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  // ─── Mock data ───
  final List<_MockProduct> _products = [
    _MockProduct(name: 'Cerveza Águila', qty: 2, price: 5000),
    _MockProduct(name: 'Empanada', qty: 3, price: 2500),
    _MockProduct(name: 'Gaseosa Cola', qty: 5, price: 2500),
    _MockProduct(name: 'Arroz con pollo', qty: 1, price: 15000),
  ];

  final List<_MockAbono> _abonos = [
    _MockAbono(amount: 10000, date: 'Hoy 2:30 PM'),
    _MockAbono(amount: 5000, date: 'Ayer 4:15 PM'),
  ];

  double get _total =>
      _products.fold(0.0, (sum, p) => sum + p.subtotal);

  double get _totalAbonado =>
      _abonos.fold(0.0, (sum, a) => sum + a.amount);

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 20),
            _buildSectionHeader('Productos'),
            const SizedBox(height: 8),
            _buildProductList(),
            const SizedBox(height: 24),
            _buildSectionHeader('Historial de Abonos'),
            const SizedBox(height: 8),
            _buildAbonoList(),
            const SizedBox(height: 100), // spacing for bottom bar
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ─── AppBar ───
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Semantics(
        label: 'Volver atrás',
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 28),
          color: AppTheme.textPrimary,
          tooltip: 'Volver',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Cuenta Abierta',
              style: TextStyle(
                color: Color(0xFFD97706),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      centerTitle: false,
    );
  }

  // ─── Summary Card ───
  Widget _buildSummaryCard() {
    final saldoPendiente = _total - _totalAbonado;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total de la cuenta
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total de la cuenta',
                style: TextStyle(
                  fontSize: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                formatCOP(_total),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF6B6B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Abonado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Abonado',
                style: TextStyle(
                  fontSize: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                formatCOP(_totalAbonado),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 12),
          // Saldo pendiente
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Saldo pendiente',
                style: TextStyle(
                  fontSize: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                formatCOP(saldoPendiente),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Section Header ───
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  // ─── Product List ───
  Widget _buildProductList() {
    return Column(
      children: _products.map((product) {
        return Semantics(
          label:
              '${product.name}, cantidad ${product.qty}, subtotal ${formatCOP(product.subtotal)}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 18,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'x${product.qty}',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatCOP(product.subtotal),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Abono List ───
  Widget _buildAbonoList() {
    if (_abonos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Sin abonos registrados',
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey.shade500,
          ),
        ),
      );
    }

    return Column(
      children: _abonos.map((abono) {
        return Semantics(
          label: 'Abono de ${formatCOP(abono.amount)}, ${abono.date}',
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Abono ${formatCOP(abono.amount)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        abono.date,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatCOP(abono.amount),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Bottom Bar ───
  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Row(
        children: [
          // ABONAR button
          Expanded(
            child: Semantics(
              label: 'Registrar abono parcial',
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _showAbonoSheet(),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.payments_rounded,
                            color: Colors.white, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'ABONAR',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // COBRAR TODO button
          Expanded(
            child: Semantics(
              label: 'Cobrar el total de la cuenta',
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Cerrando cuenta...',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'COBRAR TODO',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Abono Bottom Sheet ───
  void _showAbonoSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddAbonoSheet(
        saldoPendiente: _total - _totalAbonado,
        onConfirm: (amount) {
          setState(() {
            _abonos.insert(0, _MockAbono(amount: amount, date: 'Ahora'));
          });
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Abono de ${formatCOP(amount)} registrado',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        },
      ),
    );
  }
}

// ─── Mock Data Classes ───

class _MockProduct {
  final String name;
  final int qty;
  final double price;

  _MockProduct({
    required this.name,
    required this.qty,
    required this.price,
  });

  double get subtotal => qty * price;
}

class _MockAbono {
  final double amount;
  final String date;

  _MockAbono({
    required this.amount,
    required this.date,
  });
}
