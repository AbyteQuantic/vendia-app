import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panic_button.dart';
import '../../widgets/sync_status_banner.dart';
import '../admin/admin_hub_screen.dart';
import '../fiar/fiar_screen.dart';
import '../inventory/add_merchandise_screen.dart';
import '../tables/tables_screen.dart';

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  String _chargeMode = 'pre_payment';

  @override
  void initState() {
    super.initState();
    _loadChargeMode();
  }

  Future<void> _loadChargeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('vendia_charge_mode') ?? 'pre_payment';
    if (mounted) setState(() => _chargeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final isPostPayment = _chargeMode == 'post_payment';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Semantics(
        label: 'Pantalla principal de VendIA',
        child: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      // Logo + Bell row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.point_of_sale_rounded,
                                color: Colors.white, size: 40),
                          ),
                          const Spacer(),
                          // Botón de pánico silencioso
                          PanicButton(
                            onPanicTriggered: () {
                              // TODO: send SOS via API
                            },
                          ),
                          const SizedBox(width: 8),
                          // KDS Notification bell
                          Semantics(
                            button: true,
                            label: 'Pedidos pendientes, 2 notificaciones',
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Proximamente: Panel de pedidos',
                                      style: TextStyle(fontSize: 18),
                                    ),
                                  ),
                                );
                              },
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: Stack(
                                  children: [
                                    const Center(
                                      child: Icon(
                                        Icons.notifications_rounded,
                                        color: AppTheme.textPrimary,
                                        size: 32,
                                      ),
                                    ),
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.error,
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: const Text(
                                          '2',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'VendIA',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '¿Qué desea hacer hoy?',
                        style: TextStyle(
                            fontSize: 18, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 32),
                      Expanded(
                        child: Column(
                          children: [
                            // Top row: VENDER + FIAR (or MESAS + FIAR for post_payment)
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: Key(isPostPayment
                                          ? 'btn_mesas'
                                          : 'btn_vender'),
                                      label: isPostPayment ? 'MESAS' : 'VENDER',
                                      icon: isPostPayment
                                          ? Icons.table_restaurant_rounded
                                          : Icons.shopping_cart_rounded,
                                      color: AppTheme.primary,
                                      onTap: () {
                                        if (isPostPayment) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const TablesScreen()),
                                          );
                                        } else {
                                          Navigator.of(context)
                                              .pushNamed('/pos');
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: const Key('btn_fiar'),
                                      label: 'FIAR',
                                      icon: Icons.menu_book_rounded,
                                      color: const Color(0xFFF59E0B),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => const FiarScreen()),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Middle row: INVENTARIO (+ VENDER if post_payment)
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  if (isPostPayment) ...[
                                    Expanded(
                                      child: _DashButton(
                                        keyVal: const Key('btn_vender'),
                                        label: 'VENDER',
                                        icon: Icons.shopping_cart_rounded,
                                        color: const Color(0xFF7C3AED),
                                        onTap: () => Navigator.of(context)
                                            .pushNamed('/pos'),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                  ],
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: const Key('btn_inventario'),
                                      label: 'INVENTARIO',
                                      icon: Icons.inventory_2_rounded,
                                      color: const Color(0xFF7C3AED),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AddMerchandiseScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _DashButton(
                                      keyVal: const Key('btn_administrar'),
                                      label: 'ADMINISTRAR',
                                      icon: Icons.settings_rounded,
                                      color: const Color(0xFF059669),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AdminHubScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashButton extends StatelessWidget {
  final Key keyVal;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DashButton({
    required this.keyVal,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: keyVal,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 56),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
