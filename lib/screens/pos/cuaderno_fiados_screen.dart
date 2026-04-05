import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

/// "El Cuaderno" — Accounts Receivable (Fiados) management screen.
/// Designed with Gerontodiseño: large touch targets, high contrast, no swipes.
class CuadernoFiadosScreen extends StatefulWidget {
  const CuadernoFiadosScreen({super.key});

  @override
  State<CuadernoFiadosScreen> createState() => _CuadernoFiadosScreenState();
}

class _CuadernoFiadosScreenState extends State<CuadernoFiadosScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // TODO: Replace with real data from API/local DB
  final List<_Deudor> _deudores = [
    _Deudor(
      name: 'Don Carlos',
      phone: '3105551234',
      balance: 45000,
      lastFiado: DateTime.now().subtract(const Duration(days: 2)),
    ),
    _Deudor(
      name: 'Doña María',
      phone: '3209876543',
      balance: 23500,
      lastFiado: DateTime.now().subtract(const Duration(days: 5)),
    ),
    _Deudor(
      name: 'Juan Pérez',
      phone: '3001234567',
      balance: 12000,
      lastFiado: DateTime.now().subtract(const Duration(hours: 8)),
    ),
  ];

  List<_Deudor> get _filtered {
    if (_searchQuery.isEmpty) return _deudores;
    final q = _searchQuery.toLowerCase();
    return _deudores.where((d) => d.name.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalDeuda =
        _deudores.fold<int>(0, (sum, d) => sum + d.balance);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          children: [
            Text('📓', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text(
              'El Cuaderno',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total por cobrar',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      Text(
                        _formatCOP(totalDeuda),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${_deudores.length} clientes',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 18),
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Buscar cliente...',
                  hintStyle: const TextStyle(
                      fontSize: 18, color: Color(0xFF9CA3AF)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Color(0xFF9CA3AF), size: 24),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8F7F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                ),
              ),
            ),

            // Deudores list
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay cuentas por cobrar',
                        style: TextStyle(
                            fontSize: 18, color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _DeudorCard(
                        deudor: _filtered[i],
                        onFiarMas: () => _fiarMas(_filtered[i]),
                        onAbono: () => _registrarAbono(_filtered[i]),
                        onWhatsApp: () => _sendWhatsApp(_filtered[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _fiarMas(_Deudor deudor) {
    HapticFeedback.mediumImpact();
    // Return to POS with this customer pre-loaded as fiado context
    Navigator.of(context).pop({
      'action': 'fiar_mas',
      'name': deudor.name,
      'phone': deudor.phone,
    });
  }

  void _registrarAbono(_Deudor deudor) {
    HapticFeedback.mediumImpact();
    final abonoCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Abono de ${deudor.name}',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Saldo: ${_formatCOP(deudor.balance)}',
                style: const TextStyle(
                    fontSize: 18, color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: abonoCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '\$0',
                  hintStyle: TextStyle(
                      fontSize: 32, color: Colors.grey.shade300),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text('\$',
                        style: TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary)),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 16, horizontal: 16),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final amount =
                        int.tryParse(abonoCtrl.text.trim()) ?? 0;
                    if (amount <= 0) return;
                    HapticFeedback.heavyImpact();
                    // TODO: persist abono to API/local DB
                    setState(() {
                      deudor.balance -= amount;
                      if (deudor.balance < 0) deudor.balance = 0;
                    });
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✅ Abono de ${_formatCOP(amount)} registrado para ${deudor.name}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded, size: 24),
                  label: const Text('Registrar Abono',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendWhatsApp(_Deudor deudor) {
    HapticFeedback.lightImpact();
    final phone = deudor.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final fullPhone = phone.startsWith('57') ? phone : '57$phone';
    final msg = Uri.encodeComponent(
      'Hola ${deudor.name}, le recordamos que tiene un saldo pendiente '
      'de ${_formatCOP(deudor.balance)} en nuestra tienda.\n\n'
      'Puede ver el detalle en:\n'
      'https://tienda.vendia.app/deuda/${deudor.name.hashCode.abs()}',
    );
    launchUrl(
      Uri.parse('https://wa.me/$fullPhone?text=$msg'),
      mode: LaunchMode.externalApplication,
    );
  }

  String _formatCOP(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEUDOR MODEL (temporary — will come from API/DB)
// ═══════════════════════════════════════════════════════════════════════════════

class _Deudor {
  final String name;
  final String phone;
  int balance;
  final DateTime lastFiado;

  _Deudor({
    required this.name,
    required this.phone,
    required this.balance,
    required this.lastFiado,
  });

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEUDOR CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _DeudorCard extends StatefulWidget {
  final _Deudor deudor;
  final VoidCallback onFiarMas;
  final VoidCallback onAbono;
  final VoidCallback onWhatsApp;

  const _DeudorCard({
    required this.deudor,
    required this.onFiarMas,
    required this.onAbono,
    required this.onWhatsApp,
  });

  @override
  State<_DeudorCard> createState() => _DeudorCardState();
}

class _DeudorCardState extends State<_DeudorCard> {
  bool _expanded = false;

  String _formatCOP(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buffer.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return 'Hace ${diff.inDays} día${diff.inDays > 1 ? 's' : ''}';
    if (diff.inHours > 0) return 'Hace ${diff.inHours} hora${diff.inHours > 1 ? 's' : ''}';
    return 'Hace un momento';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.deudor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _expanded = !_expanded);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // Main row
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF6D28D9).withValues(alpha: 0.12),
                    child: Text(
                      d.initials,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6D28D9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(_timeAgo(d.lastFiado),
                            style: const TextStyle(
                                fontSize: 14, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  // Balance
                  Text(
                    _formatCOP(d.balance),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),

              // Expanded actions
              if (_expanded) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                // 3 action buttons
                _ActionButton(
                  icon: Icons.add_shopping_cart_rounded,
                  label: 'Fiar más productos',
                  color: const Color(0xFF6D28D9),
                  onTap: widget.onFiarMas,
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.payments_rounded,
                  label: 'Registrar un Abono',
                  color: const Color(0xFF10B981),
                  onTap: widget.onAbono,
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.message_rounded,
                  label: 'Recordatorio WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: widget.onWhatsApp,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: color)),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 24),
          ],
        ),
      ),
    );
  }
}
