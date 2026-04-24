import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import 'business_profile_screen.dart';
import 'branches_list_screen.dart';
import 'payment_methods_screen.dart';
import 'payment_quick_setup_screen.dart';
import 'printer_config_screen.dart';
import 'sync_screen.dart';
import 'table_floor_plan_screen.dart';
import 'employees_screen.dart';
import '../../services/margin_service.dart';
import 'catalog_virtual_screen.dart';
import 'panic_config_screen.dart';
import 'owner_pin_setup_screen.dart';

/// Admin Hub — Business configuration screen with Gerontodiseño.
class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({super.key});

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> {
  late final ApiService _api;
  bool _enableFiados = true;
  double _defaultMargin = 20;
  bool _configLoaded = false;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final data = await _api.fetchStoreConfig();
      if (!mounted) return;
      setState(() {
        _enableFiados = data['enable_fiados'] as bool? ?? true;
        _defaultMargin = (data['default_margin'] as num?)?.toDouble() ?? 20;
        MarginService.saveMargin(_defaultMargin);
        _configLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _configLoaded = true);
    }
  }

  Future<void> _toggleFiados(bool value) async {
    setState(() => _enableFiados = value);
    HapticFeedback.lightImpact();
    try {
      await _api.updateStoreConfig({'enable_fiados': value});
    } catch (_) {}
  }

  void _showMarginConfig() {
    final ctrl = TextEditingController(text: _defaultMargin.round().toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
              const Text('Margen de Ganancia Global',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 8),
              const Text(
                'Este porcentaje se aplica al sugerir precios de venta cuando ingresa mercancía.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 48, fontWeight: FontWeight.bold,
                          color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: '20',
                        hintStyle: TextStyle(
                            fontSize: 48, color: Colors.grey.shade300),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const Text('%',
                      style: TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final value = double.tryParse(ctrl.text) ?? 20;
                    Navigator.of(ctx).pop();
                    setState(() => _defaultMargin = value);
                    MarginService.saveMargin(value);
                    try {
                      await _api.updateStoreConfig({'default_margin': value});
                    } catch (_) {}
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Margen actualizado a ${value.round()}%',
                            style: const TextStyle(fontSize: 16)),
                        backgroundColor: AppTheme.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 24),
                  label: const Text('Guardar',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
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
        title: const Text('Mi Negocio',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // ── Sucursales y Ubicaciones ─────────────────────────────
            const _SectionHeader(
                title: 'Sucursales y Ubicaciones',
                icon: Icons.store_mall_directory_rounded),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.store_mall_directory_rounded,
              iconColor: const Color(0xFF5A67D8),
              title: 'Mis Sucursales',
              subtitle: 'Gestionar sedes, agregar o editar ubicaciones',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const BranchesListScreen()),
              ),
            ),

            // ── Perfil ──────────────────────────────────────────────
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Perfil', icon: Icons.storefront_rounded),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.person_rounded,
              iconColor: AppTheme.primary,
              title: 'Perfil del Negocio',
              subtitle: 'Nombre, NIT, logo y tipo de catálogo',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BusinessProfileScreen()),
              ),
            ),

            // ── Operación ───────────────────────────────────────────
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Operación', icon: Icons.settings_rounded),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.table_restaurant_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'Gestión de Mesas',
              subtitle: 'Distribuya las mesas de su local',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TableFloorPlanScreen()),
              ),
            ),
            _SettingsTile(
              icon: Icons.menu_book_rounded,
              iconColor: const Color(0xFF6D28D9),
              title: 'Configuración de Fiados',
              subtitle: _enableFiados ? 'Cuaderno habilitado' : 'Cuaderno deshabilitado',
              trailing: Switch.adaptive(
                value: _enableFiados,
                activeTrackColor: const Color(0xFF6D28D9),
                onChanged: _configLoaded ? _toggleFiados : null,
              ),
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.trending_up_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Margen de Ganancia',
              subtitle: 'Porcentaje aplicado a precios sugeridos',
              trailing: Text('${_defaultMargin.round()}%',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981))),
              onTap: _showMarginConfig,
            ),
            // "Cobro Digital" used to point to a single-account
            // shortcut (PaymentQuickSetupScreen) that crashed in
            // production — the DropdownButtonFormField raised
            // "exactly one item" whenever the stored provider wasn't
            // in the hard-coded preset list, leaving the screen
            // blank. The shortcut is kept behind an "express" entry
            // for backwards compat, but the primary entry now
            // drives the full multi-wallet hub which has robust
            // loading / empty / error states and supports QR + link
            // uploads (Nequi, Daviplata, Bancolombia, Breve, …).
            _SettingsTile(
              icon: Icons.bolt_rounded,
              iconColor: const Color(0xFF6D28D9),
              title: 'Cobro Digital',
              subtitle: 'Nequi, Daviplata, Bancolombia, Breve y QR',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const PaymentMethodsScreen()),
              ),
            ),
            _SettingsTile(
              icon: Icons.flash_on_rounded,
              iconColor: const Color(0xFFEA580C),
              title: 'Configuración rápida (Nequi)',
              subtitle: 'Atajo de 30 segundos para un solo método',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const PaymentQuickSetupScreen()),
              ),
            ),

            // ── Equipo ──────────────────────────────────────────────
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Equipo', icon: Icons.people_rounded),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.badge_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Empleados y Permisos',
              subtitle: 'Cajeros, meseros y PINs de acceso',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmployeesScreen()),
              ),
            ),

            // ── Dispositivos ────────────────────────────────────────
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Dispositivos', icon: Icons.devices_rounded),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.print_rounded,
              iconColor: const Color(0xFF6366F1),
              title: 'Impresora y Recibos',
              subtitle: 'Conectar Bluetooth, mensaje de factura',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrinterConfigScreen()),
              ),
            ),
            _SettingsTile(
              icon: Icons.wifi_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'Conexión y Sincronización',
              subtitle: 'Estado del servidor y datos pendientes',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              ),
            ),

            // ── Catalogo Virtual ─────────────────────────────────────
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Ventas Online', icon: Icons.public_rounded),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.storefront_rounded,
              iconColor: const Color(0xFF7C3AED),
              title: 'Catalogo Virtual',
              subtitle: 'Pedidos en linea y link de tienda',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CatalogVirtualScreen()),
              ),
            ),

            // ── Seguridad ───────────────────────────────────────────
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Seguridad', icon: Icons.shield_rounded),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.emergency_rounded,
              iconColor: AppTheme.error,
              title: 'Boton de Panico',
              subtitle: 'Contactos de emergencia y mensaje SOS',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PanicConfigScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.admin_panel_settings_rounded,
              iconColor: AppTheme.primary,
              title: 'PIN del propietario',
              subtitle: 'Para autorizar acciones del cajero',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OwnerPinSetupScreen()),
              ),
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
                        style: TextStyle(fontSize: 17)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar',
                            style: TextStyle(fontSize: 18)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Cerrar sesión',
                            style: TextStyle(fontSize: 18, color: AppTheme.error)),
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
                width: double.infinity, height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: AppTheme.error, size: 24),
                    SizedBox(width: 10),
                    Text('Cerrar Sesión',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                            color: AppTheme.error)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('VendIA v2.0',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary, letterSpacing: 0.5)),
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
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.onTap, this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
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
                    Text(title, style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                    Text(subtitle, style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
