import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/hardware_service.dart';
import '../../services/receipt_builder.dart';
import '../../theme/app_theme.dart';

/// Hardware y Facturación — Owner-facing screen to:
///   1. flip the master switch for receipt printing + cash drawer
///   2. pick which paired Bluetooth printer the app should talk to
///   3. test the connection (print a sample ticket / kick the drawer)
///   4. recover from connection errors
///
/// The screen is a *thin* view over [HardwareService] (a ChangeNotifier).
/// We never own UI state that duplicates the service's state — the service
/// is the single source of truth, the widget just renders it. This keeps
/// the screen safe for hot-reload and decouples it from the radio.
class HardwareSettingsScreen extends StatefulWidget {
  const HardwareSettingsScreen({super.key});

  @override
  State<HardwareSettingsScreen> createState() => _HardwareSettingsScreenState();
}

class _HardwareSettingsScreenState extends State<HardwareSettingsScreen> {
  // We track only widget-local concerns here (a busy flag for buttons that
  // run async work). Connection/device/error state lives in HardwareService.
  bool _busy = false;

  HardwareService get _service => HardwareService.instance;

  // ─────────────────────────── Permission flow ─────────────────────────

  /// Returns true if the user granted both BLUETOOTH_CONNECT and
  /// BLUETOOTH_SCAN. Shows an explanatory dialog if not.
  Future<bool> _ensurePermissions() async {
    // The same Permission objects are no-ops on iOS/older Android — the
    // plugin reports `granted` automatically there, so we don't need a
    // platform check.
    final results = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    final allGranted =
        results.values.every((s) => s.isGranted || s.isLimited);
    if (allGranted) return true;

    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Necesitamos Bluetooth',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Para conectarse con la impresora térmica y el cajón de '
          'monedas, VendIA necesita permiso de Bluetooth. Active el '
          'permiso desde los ajustes del sistema y vuelva a intentar.',
          style: TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Abrir ajustes',
                style: TextStyle(fontSize: 18, color: AppTheme.primary)),
          ),
        ],
      ),
    );
    return false;
  }

  // ─────────────────────────── Switch handling ─────────────────────────

  Future<void> _onMasterSwitch(bool wantOn) async {
    HapticFeedback.lightImpact();
    if (wantOn) {
      final ok = await _ensurePermissions();
      if (!ok) return; // leave service disabled — switch snaps back to off
      await _service.enable();
    } else {
      await _service.disable();
    }
  }

  // ─────────────────────────── Device picker ───────────────────────────

  Future<void> _showDevicePicker() async {
    HapticFeedback.lightImpact();
    final devices = await _service.listPairedDevices();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Dispositivos pareados',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Solo aparecen los equipos pareados desde los ajustes '
              'de Bluetooth del sistema.',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No se encontraron dispositivos pareados.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17, color: AppTheme.textSecondary),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = devices[i];
                    final selected = d.address == _service.selectedDeviceMac;
                    return ListTile(
                      leading: Icon(
                        selected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_rounded,
                        color: selected ? AppTheme.success : AppTheme.primary,
                        size: 28,
                      ),
                      title: Text(d.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      subtitle: Text(d.address,
                          style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary)),
                      trailing: selected
                          ? const Icon(Icons.check_rounded,
                              color: AppTheme.success)
                          : null,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await _service.selectDevice(d.address, d.name);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        // Auto-attempt a connection so the user sees
                        // the result (success/error) right away.
                        unawaited(_service.tryReconnect());
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

  // ─────────────────────────── Test actions ────────────────────────────

  Future<void> _runWithBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testPrint() async {
    HapticFeedback.mediumImpact();
    await _runWithBusy(() async {
      const tenant = ReceiptTenantInfo(
        businessName: 'VendIA — Prueba',
        address: 'Recibo de prueba',
      );
      const lines = [
        ReceiptLine(name: 'Prueba de impresion', quantity: 1, unitPrice: 0),
      ];
      final ok = await _service.printSaleReceipt(
        tenant,
        lines,
        0,
        'PRUEBA',
        openDrawer: false,
      );
      if (!mounted) return;
      _showSnack(
          ok ? 'Recibo de prueba enviado.' : 'No se pudo imprimir el recibo.',
          ok ? AppTheme.success : AppTheme.error);
    });
  }

  Future<void> _testDrawer() async {
    HapticFeedback.mediumImpact();
    await _runWithBusy(() async {
      final ok = await _service.openCashDrawer();
      if (!mounted) return;
      _showSnack(
          ok ? 'Cajón abierto.' : 'No se pudo abrir el cajón.',
          ok ? AppTheme.success : AppTheme.error);
    });
  }

  Future<void> _reconnect() async {
    HapticFeedback.lightImpact();
    await _runWithBusy(() async {
      await _service.tryReconnect();
    });
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _openSystemBluetoothSettings() async {
    HapticFeedback.lightImpact();
    try {
      await FlutterBluetoothSerial.instance.openSettings();
    } catch (_) {
      // Fall back to app-level settings if the system call is not
      // supported on this OS version.
      await openAppSettings();
    }
  }

  // ─────────────────────────── Build ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Hardware y Facturación',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) {
            final isOn = _service.isEnabled;
            return ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              children: [
                _PrinterMasterCard(
                  isEnabled: isOn,
                  onChanged: _onMasterSwitch,
                ),
                if (isOn) ...[
                  const SizedBox(height: 16),
                  _StatusCard(
                    status: _service.status,
                    deviceName: _service.selectedDeviceName,
                    errorMessage: _service.lastErrorMessage,
                    onReconnect: _reconnect,
                    busy: _busy,
                  ),
                  const SizedBox(height: 16),
                  _DeviceCard(
                    selectedName: _service.selectedDeviceName,
                    selectedMac: _service.selectedDeviceMac,
                    onPick: _showDevicePicker,
                  ),
                  const SizedBox(height: 16),
                  _TestActionsCard(
                    enabled: !_busy,
                    onPrintTest: _testPrint,
                    onOpenDrawer: _testDrawer,
                  ),
                ],
                const SizedBox(height: 20),
                _PairingHelpCard(
                  onOpenSettings: _openSystemBluetoothSettings,
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ────────────────────────────── Cards ──────────────────────────────────

class _PrinterMasterCard extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onChanged;
  const _PrinterMasterCard({required this.isEnabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            key: const Key('hardware_master_switch'),
            value: isEnabled,
            onChanged: onChanged,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Activar impresión y cajón',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
            subtitle: const Text(
              'Imprime recibos y abre el cajón de monedas al cobrar.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
          if (!isEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Cuando lo active le pediremos permiso de Bluetooth.',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final HardwareConnectionStatus status;
  final String? deviceName;
  final String? errorMessage;
  final VoidCallback onReconnect;
  final bool busy;

  const _StatusCard({
    required this.status,
    required this.deviceName,
    required this.errorMessage,
    required this.onReconnect,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final ui = _statusUi(status, deviceName, errorMessage);
    final showReconnect = status == HardwareConnectionStatus.disconnected ||
        status == HardwareConnectionStatus.error;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (status == HardwareConnectionStatus.connecting)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(ui.color),
                  ),
                )
              else
                Container(
                  key: Key('hardware_status_dot_${ui.statusKey}'),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: ui.color,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ui.label,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ui.color),
                ),
              ),
            ],
          ),
          if (showReconnect) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('hardware_reconnect_button'),
                onPressed: busy ? null : onReconnect,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reconectar',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final String? selectedName;
  final String? selectedMac;
  final VoidCallback onPick;
  const _DeviceCard(
      {required this.selectedName,
      required this.selectedMac,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    final hasDevice = (selectedMac ?? '').isNotEmpty;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dispositivo',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            hasDevice
                ? (selectedName ?? selectedMac ?? '')
                : 'Aún no ha seleccionado una impresora.',
            style: const TextStyle(
                fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('hardware_change_device_button'),
              onPressed: onPick,
              icon: const Icon(Icons.bluetooth_searching_rounded),
              label: Text(
                hasDevice ? 'Cambiar dispositivo' : 'Seleccionar dispositivo',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestActionsCard extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPrintTest;
  final VoidCallback onOpenDrawer;
  const _TestActionsCard({
    required this.enabled,
    required this.onPrintTest,
    required this.onOpenDrawer,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Probar conexión',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Verifique que la impresora y el cajón responden correctamente.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('hardware_test_print_button'),
                  onPressed: enabled ? onPrintTest : null,
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Imprimir prueba',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(
                        color: AppTheme.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('hardware_test_drawer_button'),
                  onPressed: enabled ? onOpenDrawer : null,
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('Probar cajón',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(
                        color: AppTheme.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PairingHelpCard extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _PairingHelpCard({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppTheme.primary, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '¿No tiene impresora pareada?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Primero debe parearla desde los ajustes de Bluetooth del '
            'sistema. Después regrese a esta pantalla y selecciónela en '
            'la lista.',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('hardware_open_bt_settings_button'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_bluetooth_rounded),
              label: const Text(
                'Abrir ajustes de Bluetooth',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: child,
    );
  }
}

// ───────────────────────── Status → UI mapping ─────────────────────────

class _StatusUi {
  final Color color;
  final String label;
  final String statusKey;
  const _StatusUi({
    required this.color,
    required this.label,
    required this.statusKey,
  });
}

_StatusUi _statusUi(
  HardwareConnectionStatus status,
  String? deviceName,
  String? errorMessage,
) {
  switch (status) {
    case HardwareConnectionStatus.disabled:
      return const _StatusUi(
          color: Color(0xFF9E9E9E), label: 'Apagado', statusKey: 'disabled');
    case HardwareConnectionStatus.disconnected:
      return const _StatusUi(
          color: Color(0xFF9E9E9E),
          label: 'Sin conexión',
          statusKey: 'disconnected');
    case HardwareConnectionStatus.connecting:
      return const _StatusUi(
          color: AppTheme.warning,
          label: 'Conectando...',
          statusKey: 'connecting');
    case HardwareConnectionStatus.connected:
      final name = (deviceName ?? '').isEmpty ? 'la impresora' : deviceName!;
      return _StatusUi(
          color: AppTheme.success,
          label: 'Conectado a $name',
          statusKey: 'connected');
    case HardwareConnectionStatus.error:
      final msg = (errorMessage ?? '').isEmpty
          ? 'Error desconocido'
          : errorMessage!;
      return _StatusUi(
          color: AppTheme.error,
          label: 'Error: $msg',
          statusKey: 'error');
  }
}
