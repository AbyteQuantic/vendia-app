import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import 'analytics_screen.dart';
import 'suppliers_screen.dart';
import '../security/sos_contacts_screen.dart';

class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  /// Returns a greeting based on current hour.
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '!Buenos dias, Don Pedro!';
    if (hour < 18) return '!Buenas tardes, Don Pedro!';
    return '!Buenas noches, Don Pedro!';
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
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
          ),
        ),
        title: const Text(
          'Centro de Mando',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header with gradient ──────────────────────────────────
            _buildHeader(),
            const SizedBox(height: 20),

            // ── Section 1: Necesita su atencion ──────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Necesita su atencion',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AlertCard(
                    emoji: '\u26A0\uFE0F',
                    message: '3 productos sin precio',
                    buttonLabel: 'Asignar',
                    cardColor: const Color(0xFFFEE2E2),
                    borderColor: const Color(0xFFEF4444),
                    buttonGradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                  ),
                  const SizedBox(height: 10),
                  _AlertCard(
                    emoji: '\uD83D\uDEA8',
                    message: '2 productos por agotarse',
                    buttonLabel: 'Pedir',
                    cardColor: const Color(0xFFFEF3C7),
                    borderColor: const Color(0xFFF59E0B),
                    buttonGradient: const [Color(0xFF10B981), Color(0xFF059669)],
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                  ),
                  const SizedBox(height: 10),
                  _AlertCard(
                    emoji: '\u23F3',
                    message: '5 productos cerca a vencer',
                    buttonLabel: 'Promo',
                    cardColor: const Color(0xFFF3E8FF),
                    borderColor: const Color(0xFF8B5CF6),
                    buttonGradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Section 2: Salud del inventario ──────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Salud del inventario',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InventoryStatCard(
                          label: 'Mercancia actual',
                          value: '\$1.500.000',
                          valueColor: const Color(0xFF059669),
                          bgColor: const Color(0xFFD1FAE5),
                          borderColor: const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InventoryStatCard(
                          label: 'Le alcanza para',
                          value: '\u2248 4 dias',
                          valueColor: const Color(0xFF2563EB),
                          bgColor: const Color(0xFFDBEAFE),
                          borderColor: const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Section 3: Radar / Tip ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF667EEA).withValues(alpha: 0.08),
                      const Color(0xFF764BA2).withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('\uD83D\uDCA1', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Cerveza Corona se vende mucho esta semana en Bogota. \u00BFAgregarla?',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Section 4: Acciones rapidas ──────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Acciones rapidas',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.camera_alt_rounded,
                          label: 'Factura IA',
                          gradient: const [Color(0xFF667EEA), Color(0xFF764BA2)],
                          onTap: () {
                            HapticFeedback.lightImpact();
                            // Navigate to inventory scan when available
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.inventory_2_rounded,
                          label: 'Inventario',
                          gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                          onTap: () {
                            HapticFeedback.lightImpact();
                            // Navigate to inventory when available
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickActionButton(
                          icon: Icons.group_rounded,
                          label: 'Proveedores',
                          gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SuppliersScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // SOS Security quick action
                  SizedBox(
                    width: double.infinity,
                    child: _QuickActionButton(
                      icon: Icons.shield_rounded,
                      label: '🚨 SOS / Seguridad',
                      gradient: const [Color(0xFFFF6B6B), Color(0xFFDC2626)],
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SosContactsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Mis Cuentas shortcut ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AnalyticsScreen(),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart_rounded,
                          color: Colors.white, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'Ver Mis Cuentas',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF667EEA),
            Color(0xFF764BA2),
            Color(0x80FF6B6B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _greeting(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'El viernes juega la Seleccion \uD83C\uDDE8\uD83C\uDDF4\u26BD',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alert Card ───────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final String emoji;
  final String message;
  final String buttonLabel;
  final Color cardColor;
  final Color borderColor;
  final List<Color> buttonGradient;
  final VoidCallback onTap;

  const _AlertCard({
    required this.emoji,
    required this.message,
    required this.buttonLabel,
    required this.cardColor,
    required this.borderColor,
    required this.buttonGradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: buttonGradient),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inventory Stat Card ──────────────────────────────────────────────────────

class _InventoryStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color bgColor;
  final Color borderColor;

  const _InventoryStatCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Action Button ──────────────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
