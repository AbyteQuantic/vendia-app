import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vendia_pos/screens/pos/account_qr_screen.dart';
import 'package:vendia_pos/screens/billing/account_detail_screen.dart';
import 'package:vendia_pos/utils/format_cop.dart';

/// "Cuentas Abiertas" (Parqueadero) — shows all open tabs/tables
/// with pending payments. The tendero can show QR or close & charge.
class OpenAccountsScreen extends StatefulWidget {
  const OpenAccountsScreen({super.key});

  @override
  State<OpenAccountsScreen> createState() => _OpenAccountsScreenState();
}

class _OpenAccountsScreenState extends State<OpenAccountsScreen> {
  // Mock data — will be replaced with real OrderTicket data
  final List<_MockAccount> _accounts = [
    _MockAccount(
      uuid: 'acc-001',
      label: 'Mesa 4',
      itemCount: 5,
      waiterName: 'Carlos',
      total: 45000,
      abonado: 15000,
      color: const Color(0xFFF59E0B),
    ),
    _MockAccount(
      uuid: 'acc-002',
      label: 'Mesa 7',
      itemCount: 3,
      waiterName: 'Rosa',
      total: 32500,
      abonado: 0,
      color: const Color(0xFF667EEA),
    ),
    _MockAccount(
      uuid: 'acc-003',
      label: 'Mesa 2',
      itemCount: 8,
      waiterName: 'Carlos',
      total: 50000,
      abonado: 20000,
      color: const Color(0xFF10B981),
    ),
  ];

  double get _totalPending =>
      _accounts.fold(0.0, (sum, a) => sum + a.saldoPendiente);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _accounts.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _buildAccountCard(_accounts[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cuentas Abiertas',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_accounts.length} mesas con cuenta abierta',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Total pendiente: ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              Text(
                formatCOP(_totalPending),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(_MockAccount account) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top: avatar + info + price
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [account.color, account.color.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(
                      account.label.replaceAll('Mesa ', ''),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.label,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        '${account.itemCount} artículos · Mesero: ${account.waiterName}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatCOP(account.saldoPendiente),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF6B6B),
                      ),
                    ),
                    Text(
                      account.abonado > 0
                          ? 'Abonado: ${formatCOP(account.abonado)}'
                          : 'Sin abonos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: account.abonado > 0
                            ? const Color(0xFF10B981)
                            : const Color(0xFFFF6B6B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Buttons: Mostrar QR + Cobrar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                // QR Button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountQrScreen(
                            accountLabel: account.label,
                            cartLabel: 'Cuenta Abierta',
                            accountUuid: account.uuid,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_2_rounded,
                              size: 20, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Mostrar QR',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Ver Detalle Button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountDetailScreen(
                            accountUuid: account.uuid,
                            label: account.label,
                            waiterName: account.waiterName,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_rounded,
                              size: 20, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Ver Cuenta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          const Text(
            'No hay pedidos\npendientes',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cuando un mesero envíe un pedido,\naparecerá aquí automáticamente',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.home_rounded),
            label: const Text('Volver al inicio'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(260, 64),
              side: const BorderSide(color: Color(0xFF667EEA), width: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              textStyle:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockAccount {
  final String uuid;
  final String label;
  final int itemCount;
  final String waiterName;
  final double total;
  final double abonado;
  final Color color;

  _MockAccount({
    required this.uuid,
    required this.label,
    required this.itemCount,
    required this.waiterName,
    required this.total,
    required this.abonado,
    required this.color,
  });

  double get saldoPendiente => total - abonado;
}
