import 'package:flutter/material.dart';

import '../services/bank_notification_service.dart';

/// Switch tile that opts the cashier into the (informative) bank
/// notification listener. The tile's job is to:
///
///   1. Surface the current Android permission state as a switch
///      ("Auto-detectar pagos…") — never lie about whether the
///      OS-level toggle is on.
///   2. When the cashier flips the switch ON without the OS
///      permission, run an educational [AlertDialog] and route
///      them straight into Settings → Acceso a notificaciones via
///      [BankNotificationService.openListenerSettings].
///   3. Re-evaluate the OS state on `AppLifecycleState.resumed` so
///      the switch reflects reality the moment the cashier returns
///      from Settings — no manual refresh required.
///
/// CRITICAL invariant: this tile is the ONLY UX entry point for
/// the listener permission. It never claims to "auto-confirm
/// payments" — the [SnackBar] in the checkout flow is still purely
/// informative; the cashier still has to attach the receipt photo.
class BankAutoDetectTile extends StatefulWidget {
  const BankAutoDetectTile({super.key});

  @override
  State<BankAutoDetectTile> createState() => _BankAutoDetectTileState();
}

class _BankAutoDetectTileState extends State<BankAutoDetectTile>
    with WidgetsBindingObserver {
  /// Mirrors the OS-level "Acceso a notificaciones" toggle. Default
  /// `false` so the cashier sees the off-state until we confirm.
  bool _enabled = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshFromOs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The cashier may have just flipped the toggle in Settings.
    // Refresh on resume so the switch animates to its new value
    // without forcing them to leave-and-return-to the screen.
    if (state == AppLifecycleState.resumed) {
      _refreshFromOs();
    }
  }

  Future<void> _refreshFromOs() async {
    final ok = await BankNotificationService.instance.isListenerEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = ok;
      _checking = false;
    });
  }

  Future<void> _onToggle(bool requested) async {
    // OFF → ON without the OS permission: run the educational flow.
    if (requested && !_enabled) {
      final alreadyOn =
          await BankNotificationService.instance.isListenerEnabled();
      if (!mounted) return;
      if (alreadyOn) {
        // The OS already says YES — no dialog needed; just sync.
        setState(() => _enabled = true);
        return;
      }
      final goToSettings = await _showEducationalDialog();
      if (goToSettings == true) {
        await BankNotificationService.instance.openListenerSettings();
        // didChangeAppLifecycleState will re-evaluate on resume —
        // we do NOT optimistically flip the switch here because
        // the cashier might dismiss the system screen without
        // granting the permission.
      }
      return;
    }

    // ON → OFF: there is no OS API to revoke the permission from
    // inside the app. Best we can do is route the cashier back to
    // Settings so they can flip it off, with the same dialog so
    // they understand why we can't toggle it ourselves.
    if (!requested && _enabled) {
      final goToSettings = await _showRevokeDialog();
      if (goToSettings == true) {
        await BankNotificationService.instance.openListenerSettings();
      }
      return;
    }
  }

  Future<bool?> _showEducationalDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Permiso Requerido',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Para detectar los pagos automáticamente, VendIA necesita '
          'permiso para leer las notificaciones de su celular. Solo '
          'escucharemos a las apps de bancos. Su privacidad está '
          '100% garantizada.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Ahora no',
                style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ir a Configuración',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showRevokeDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Apagar desde el sistema',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Para apagar la auto-detección de pagos hay que '
          'desactivar el permiso desde la pantalla del sistema. '
          'Te llevamos directo.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ir a Configuración',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: SwitchListTile.adaptive(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        title: const Text('Auto-detectar pagos de Nequi/Bancolombia',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        subtitle: Text(
          _checking
              ? 'Comprobando permiso…'
              : 'Lee las notificaciones del banco para agilizar el cobro',
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        value: _enabled,
        onChanged: _checking ? null : _onToggle,
      ),
    );
  }
}
