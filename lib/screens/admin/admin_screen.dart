import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sync_status_banner.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _nequiCtrl = TextEditingController();
  final _daviplataCtrl = TextEditingController();
  String _chargeMode = 'pre_payment';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _nequiCtrl.dispose();
    _daviplataCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _nequiCtrl.text = prefs.getString('vendia_nequi_phone') ?? '';
    _daviplataCtrl.text = prefs.getString('vendia_daviplata_phone') ?? '';
    _chargeMode = prefs.getString('vendia_charge_mode') ?? 'pre_payment';
    setState(() => _loaded = true);
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vendia_nequi_phone', _nequiCtrl.text.trim());
    await prefs.setString('vendia_daviplata_phone', _daviplataCtrl.text.trim());
    await prefs.setString('vendia_charge_mode', _chargeMode);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Text('Configuración guardada', style: TextStyle(fontSize: 18)),
          ],
        ),
        backgroundColor: AppTheme.success,
        duration: Duration(seconds: 3),
      ),
    );
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
          'Administrar',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Pantalla de administración',
        child: Column(
          children: [
            const SyncStatusBanner(),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        // ── Payment Config ─────────────────────────────────────
                        const Text(
                          'Mis datos de pago',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Estos números se mostrarán en la pantalla QR para que tus clientes puedan pagarte.',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text('Número Nequi',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nequiCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          style:
                              const TextStyle(fontSize: 20, letterSpacing: 1.5),
                          decoration: InputDecoration(
                            hintText: 'Ej: 310 000 0000',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                            ),
                            prefixIcon: Icon(Icons.phone_android_rounded,
                                color: Color(0xFF311B92), size: 24),
                          ),
                        ),

                        const SizedBox(height: 20),

                        const Text('Número Daviplata',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _daviplataCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          style:
                              const TextStyle(fontSize: 20, letterSpacing: 1.5),
                          decoration: InputDecoration(
                            hintText: 'Ej: 310 000 0000',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                            ),
                            prefixIcon: Icon(Icons.phone_android_rounded,
                                color: AppTheme.error, size: 24),
                          ),
                        ),

                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 24),

                        // ── Charge Mode ────────────────────────────────────────
                        const Text(
                          '¿Cómo cobras?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        _ChargeModeOption(
                          label: 'Cobro al momento',
                          description:
                              'Tiendas, minimercados, fast food — el cliente paga al recibir.',
                          icon: Icons.shopping_cart_checkout_rounded,
                          value: 'pre_payment',
                          selected: _chargeMode,
                          onTap: () =>
                              setState(() => _chargeMode = 'pre_payment'),
                        ),
                        const SizedBox(height: 12),
                        _ChargeModeOption(
                          label: 'Cobro al final (Mesas)',
                          description:
                              'Bares, restaurantes, cafeterías — el cliente abre cuenta y paga al salir.',
                          icon: Icons.table_restaurant_rounded,
                          value: 'post_payment',
                          selected: _chargeMode,
                          onTap: () =>
                              setState(() => _chargeMode = 'post_payment'),
                        ),

                        const SizedBox(height: 32),

                        // Save button
                        ElevatedButton.icon(
                          onPressed: _saveConfig,
                          icon: const Icon(Icons.save_rounded, size: 24),
                          label: const Text('Guardar configuración'),
                        ),

                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 24),

                        const Text(
                          'Más opciones',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Próximamente: inventario, empleados y proveedores.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.textSecondary,
                            height: 1.5,
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
}

class _ChargeModeOption extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final String value;
  final String selected;
  final VoidCallback onTap;

  const _ChargeModeOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Semantics(
      button: true,
      label: '$label: $description',
      selected: isSelected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.08)
                : AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.borderColor,
              width: isSelected ? 2.5 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                          fontSize: 18, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.primary, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
