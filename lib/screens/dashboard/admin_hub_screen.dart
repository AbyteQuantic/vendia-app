import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';

/// Admin Hub — Business configuration screen with Gerontodiseño.
class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        title: const Text(
          'Mi Negocio',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // ── Section: Perfil ──────────────────────────────────────
            _SectionHeader(title: 'Perfil', icon: Icons.storefront_rounded),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.person_rounded,
              iconColor: AppTheme.primary,
              title: 'Perfil del Negocio',
              subtitle: 'Nombre, NIT, logo y tipo de catálogo',
              onTap: () => _showComingSoon(context),
            ),

            // ── Section: Operación ──────────────────────────────────
            const SizedBox(height: 20),
            _SectionHeader(title: 'Operación', icon: Icons.settings_rounded),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.table_restaurant_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'Gestión de Mesas',
              subtitle: '¿Cuántas mesas tiene su local?',
              onTap: () => _showMesasConfig(context),
            ),
            _SettingsTile(
              icon: Icons.menu_book_rounded,
              iconColor: const Color(0xFF6D28D9),
              title: 'Configuración de Fiados',
              subtitle: 'Habilitar o deshabilitar el cuaderno',
              trailing: Switch.adaptive(
                value: true, // TODO: read from settings
                activeColor: const Color(0xFF6D28D9),
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  // TODO: persist setting
                },
              ),
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.receipt_long_rounded,
              iconColor: const Color(0xFFEA580C),
              title: 'Métodos de Pago',
              subtitle: 'Nequi, Daviplata y transferencias',
              onTap: () => _showComingSoon(context),
            ),

            // ── Section: Equipo ─────────────────────────────────────
            const SizedBox(height: 20),
            _SectionHeader(title: 'Equipo', icon: Icons.people_rounded),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.badge_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Empleados y Permisos',
              subtitle: 'Cajeros, meseros y PINs de acceso',
              onTap: () => _showComingSoon(context),
            ),

            // ── Section: Dispositivos ───────────────────────────────
            const SizedBox(height: 20),
            _SectionHeader(
                title: 'Dispositivos', icon: Icons.devices_rounded),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.print_rounded,
              iconColor: const Color(0xFF6366F1),
              title: 'Impresora y Recibos',
              subtitle: 'Conectar Bluetooth, mensaje de factura',
              onTap: () => _showComingSoon(context),
            ),
            _SettingsTile(
              icon: Icons.wifi_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'Conexión y Sincronización',
              subtitle: 'Estado del servidor y datos pendientes',
              onTap: () => _showComingSoon(context),
            ),

            // ── Logout ──────────────────────────────────────────────
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () async {
                HapticFeedback.mediumImpact();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    title: const Text('¿Cerrar sesión?',
                        style: TextStyle(fontSize: 22)),
                    content: const Text(
                      'Sus datos locales se mantendrán guardados.',
                      style: TextStyle(fontSize: 17),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar',
                            style: TextStyle(fontSize: 18)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Cerrar sesión',
                            style: TextStyle(
                                fontSize: 18, color: AppTheme.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await AuthService().logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                }
              },
              child: Container(
                width: double.infinity,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: AppTheme.error, size: 24),
                    SizedBox(width: 10),
                    Text('Cerrar Sesión',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.error)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Center(
              child: Text(
                'VendIA v2.0',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Próximamente disponible',
            style: TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showMesasConfig(BuildContext context) {
    final ctrl = TextEditingController(text: '12'); // TODO: read from settings
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('¿Cuántas mesas tiene su local?',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 48, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(
                      fontSize: 48, color: Colors.grey.shade300),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    // TODO: persist table count to settings
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✅ ${ctrl.text} mesas configuradas',
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
                  label: const Text('Guardar',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
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
}

// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.textSecondary, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.5)),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 14, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
