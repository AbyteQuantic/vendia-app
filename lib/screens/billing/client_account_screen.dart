import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/format_cop.dart';

class ClientAccountScreen extends StatefulWidget {
  final String accountUuid;

  const ClientAccountScreen({
    super.key,
    required this.accountUuid,
  });

  @override
  State<ClientAccountScreen> createState() => _ClientAccountScreenState();
}

class _ClientAccountScreenState extends State<ClientAccountScreen> {
  int _splitCount = 1;

  // ── Mock data ──────────────────────────────────────────────────────────

  final List<_ProductLine> _products = const [
    _ProductLine(name: 'Cerveza Águila', qty: 2, subtotal: 10000),
    _ProductLine(name: 'Empanada', qty: 3, subtotal: 7500),
    _ProductLine(name: 'Gaseosa Cola', qty: 5, subtotal: 12500),
    _ProductLine(name: 'Arroz con pollo', qty: 1, subtotal: 15000),
  ];

  final List<_AbonoLine> _abonos = const [
    _AbonoLine(amount: 10000, label: 'Hoy 2:30 PM'),
    _AbonoLine(amount: 5000, label: 'Ayer 4:15 PM'),
  ];

  // ── Computed values ────────────────────────────────────────────────────

  double get _total =>
      _products.fold(0.0, (sum, p) => sum + p.subtotal);

  double get _totalAbonado =>
      _abonos.fold(0.0, (sum, a) => sum + a.amount);

  double get _saldoPendiente => _total - _totalAbonado;

  double get _perPerson {
    final raw = _saldoPendiente / _splitCount;
    return ((raw / 50).ceil() * 50).toDouble();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStoreHeader(),
            _buildAccountBadge(),
            _buildProductsSection(),
            _buildAbonosSection(),
            _buildSaldoPendienteCard(),
            _buildPartirCuentaSection(),
            _buildWhatsAppButton(),
          ],
        ),
      ),
    );
  }

  // ── 1. Store Header ────────────────────────────────────────────────────

  Widget _buildStoreHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.store,
              color: Color(0xFF764BA2),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'La Tienda de Don José',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Tu cuenta en tiempo real',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withAlpha(204),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Account Badge ──────────────────────────────────────────────────

  Widget _buildAccountBadge() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EDFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_restaurant, color: Color(0xFF764BA2), size: 24),
            SizedBox(width: 8),
            Text(
              'Mesa 4 · Cuenta Abierta',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF764BA2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3. Products Section ───────────────────────────────────────────────

  Widget _buildProductsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Detalle del pedido',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._products.map(_buildProductRow),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  formatCOP(_total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(_ProductLine p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${p.name} x${p.qty}',
            style: const TextStyle(fontSize: 18),
          ),
          Text(
            formatCOP(p.subtotal.toDouble()),
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  // ── 4. Abonos Section ─────────────────────────────────────────────────

  Widget _buildAbonosSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: Color(0xFF10B981), width: 4),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pagos realizados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._abonos.map(_buildAbonoRow),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Total abonado:',
                  style: TextStyle(fontSize: 18),
                ),
                const Spacer(),
                Text(
                  formatCOP(_totalAbonado),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbonoRow(_AbonoLine a) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
          const SizedBox(width: 8),
          Text(
            'Abono ${formatCOP(a.amount.toDouble())}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            a.label,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ── 5. Saldo Pendiente Card ───────────────────────────────────────────

  Widget _buildSaldoPendienteCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saldo pendiente',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              Text(
                formatCOP(_saldoPendiente),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6B6B),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.warning, color: Colors.amber, size: 40),
        ],
      ),
    );
  }

  // ── 6. Partir Cuenta Section ──────────────────────────────────────────

  Widget _buildPartirCuentaSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people, color: Color(0xFF764BA2), size: 28),
                SizedBox(width: 8),
                Text(
                  '¿Dividir entre varios?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepperButton(
                  icon: Icons.remove,
                  gradient: false,
                  onTap: () {
                    if (_splitCount > 1) {
                      HapticFeedback.mediumImpact();
                      setState(() => _splitCount--);
                    }
                  },
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Text(
                      '$_splitCount',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'personas',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                _buildStepperButton(
                  icon: Icons.add,
                  gradient: true,
                  onTap: () {
                    if (_splitCount < 20) {
                      HapticFeedback.mediumImpact();
                      setState(() => _splitCount++);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EDFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'Cada persona paga:',
                    style: TextStyle(fontSize: 18),
                  ),
                  Text(
                    formatCOP(_perPerson),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF764BA2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required bool gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: gradient ? null : const Color(0xFFF3F4F6),
          gradient: gradient
              ? const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                )
              : null,
        ),
        child: Icon(
          icon,
          size: 28,
          color: gradient ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  // ── 7. WhatsApp Button ────────────────────────────────────────────────

  Widget _buildWhatsAppButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          // TODO: launch WhatsApp with invoice request
        },
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF25D366),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text(
                'Pedir factura por WhatsApp',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────

class _ProductLine {
  final String name;
  final int qty;
  final double subtotal;

  const _ProductLine({
    required this.name,
    required this.qty,
    required this.subtotal,
  });
}

class _AbonoLine {
  final double amount;
  final String label;

  const _AbonoLine({
    required this.amount,
    required this.label,
  });
}
