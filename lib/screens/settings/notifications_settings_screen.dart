// Spec: specs/038-push-notifications-web-android/spec.md
//
// Pantalla de configuración de notificaciones. Muestra:
//   - Estado actual ("activas" / "desactivadas").
//   - Lista de dispositivos registrados (con su `device_label` +
//     `last_seen_at`), cada uno con botón "Revocar" → DELETE
//     `/api/v1/devices/me/:id` (AC-12).
//   - Botón "Activar en este dispositivo" si aún no hay token o el
//     usuario lo había rechazado y quiere reactivar (AC-03).
//   - Input del umbral de stock crítico — el dueño lo edita, la
//     pantalla persiste con `PATCH /tenants/me` (AC-18).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/push_service.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  List<Map<String, dynamic>>? _devices;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    // NO bloqueamos por `isAvailable` — el init de Firebase puede no
    // haber terminado y dispararíamos el warning innecesariamente.
    // Si la API falla por sesión / red, mostramos lista vacía sin
    // texto rojo: el botón "Activar" sigue disponible y guía al
    // tendero.
    setState(() => _busy = true);
    try {
      final list = await PushService().listMyDevices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _devices = const [];
        _error = null; // sin texto rojo — la acción es activar
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _activate() async {
    HapticFeedback.lightImpact();
    // Feedback inmediato — sin esto el tendero no sabe si el tap
    // registró (sobre todo en iPhone donde el prompt puede tardar
    // varios segundos o no aparecer del todo si Safari ya recordaba
    // un "Denegado" previo).
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Solicitando permiso…',
          style: TextStyle(fontSize: 16)),
      duration: Duration(seconds: 2),
    ));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await PushService().requestOptInAndRegister();
      if (!mounted) return;
      if (!ok) {
        // Mostramos el error REAL del PushService (init failed,
        // permiso denegado, getToken vacío) en vez de un mensaje
        // genérico — sin esto no se puede diagnosticar en iPhone.
        final reason = PushService().lastOptInError ??
            'No se pudo activar (causa desconocida).';
        setState(() => _error = reason);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Notificaciones activadas',
              style: TextStyle(fontSize: 16)),
          backgroundColor: Color(0xFF059669),
        ));
      }
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    HapticFeedback.lightImpact();
    final id = device['id'] as String?;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Desactivar notificaciones?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(
          'Dejará de recibir avisos en ${device['device_label'] ?? 'este dispositivo'}.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desactivar', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await PushService().revokeFromBackend(id);
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo desactivar. Vuelva a intentar.',
              style: TextStyle(fontSize: 16)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),

            // ── Panel de diagnóstico — siempre visible para que el
            //    tendero (y nosotros) sepamos qué pasó sin abrir
            //    devtools del browser. Muestra el estado en tiempo
            //    real del PushService.
            _DiagnosticPanel(),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            const Text(
              'Dispositivos con notificaciones activas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty && !_busy && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Aún no tiene ningún dispositivo registrado.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ...devices.map((d) => _deviceTile(d)),
            const SizedBox(height: 24),
            // El botón "Activar" se muestra SIEMPRE — incluso si el
            // PushService no reporta available todavía. Razón: el
            // init de Firebase puede tardar, y queremos que el
            // tendero pueda intentar manualmente sin tener que
            // esperar/refrescar. requestOptInAndRegister maneja el
            // caso "Firebase no listo" devolviendo false con mensaje.
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _activate,
                icon: const Icon(Icons.notifications_active),
                label: const Text(
                  'Activar en este dispositivo',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (devices.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _sendTest,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text(
                    'Enviar push de prueba',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6D28D9),
                    side: const BorderSide(
                        color: Color(0xFF6D28D9), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Le mandamos una notificación de prueba a este '
                'dispositivo. Si no llega, revise los permisos del '
                'sitio en su navegador.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendTest() async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final sent = await PushService().sendTestPush();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          sent > 0
              ? 'Push enviada a $sent dispositivo(s). Revise la barra de notificaciones.'
              : 'No hay dispositivos registrados que reciban la prueba.',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: sent > 0
            ? const Color(0xFF059669)
            : const Color(0xFFDC2626),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'No pudimos enviar la prueba: $e',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFFDC2626),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _deviceTile(Map<String, dynamic> d) {
    final label = (d['device_label'] as String?) ?? 'Dispositivo';
    final platform = (d['platform'] as String?) ?? '';
    final lastSeen = (d['last_seen_at'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF3E8FF),
          child: Icon(
            platform == 'android' ? Icons.android : Icons.public,
            color: const Color(0xFF6D28D9),
          ),
        ),
        title: Text(label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Última actividad: ${_formatLastSeen(lastSeen)}',
          style: const TextStyle(fontSize: 14),
        ),
        trailing: TextButton(
          onPressed: _busy ? null : () => _revoke(d),
          child: const Text('Desactivar',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDC2626),
              )),
        ),
      ),
    );
  }

  String _formatLastSeen(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

/// Panel de diagnóstico siempre visible. Cuando algo falla en
/// iPhone Safari PWA no podemos abrir devtools, así que exponemos
/// el estado del PushService directamente en la UI.
class _DiagnosticPanel extends StatefulWidget {
  @override
  State<_DiagnosticPanel> createState() => _DiagnosticPanelState();
}

class _DiagnosticPanelState extends State<_DiagnosticPanel> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // Refresca el panel cada 1s mientras la pantalla está abierta
    // — así si el init de Firebase termina después de montar, lo
    // vemos sin recargar.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = PushService();
    final ready = service.isAvailable;
    final initErr = service.lastInitError;
    final optInErr = service.lastOptInError;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Diagnóstico',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          _row('Firebase listo', ready ? 'Sí ✓' : 'No ✗',
              ready ? const Color(0xFF059669) : const Color(0xFFDC2626)),
          if (initErr != null)
            _row('Error de init', initErr, const Color(0xFFDC2626)),
          if (optInErr != null)
            _row('Último intento', optInErr, const Color(0xFFDC2626)),
          if (initErr == null && optInErr == null && ready)
            const Text('Sin errores registrados.',
                style:
                    TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          Text(value,
              style: TextStyle(
                  fontSize: 13, color: valueColor, height: 1.3)),
        ],
      ),
    );
  }
}
