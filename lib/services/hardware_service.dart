// Spec: specs/046-impresora-usb-lan-escpos/spec.md
import 'dart:async';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';
import 'printer_transport.dart';
import 'printer_transports.dart';
import 'receipt_builder.dart';

// Re-export so call sites (and existing tests) can keep importing the
// transport seam + config model straight from hardware_service.dart.
export 'printer_transport.dart';
export 'printer_config.dart';

/// State machine for the printer connection. The UI reads this enum to
/// render the right indicator (badge color, retry button, etc.).
enum HardwareConnectionStatus {
  /// Master switch is OFF. We never touch the radio in this state.
  disabled,

  /// Switch is ON but no live socket. Initial state after enable() until
  /// the first connect succeeds, and the post-disconnect state.
  disconnected,

  /// connect() is in flight. Used to debounce the connect button.
  connecting,

  /// Live socket open, ready for write().
  connected,

  /// Last operation threw. lastErrorMessage is populated. The next
  /// successful operation flips us back to connected/disconnected.
  error,
}

/// Singleton in charge of:
///   - persisting the user's "use printer" master switch + selected printer
///     ([PrinterConfig]: transport + address + paper size),
///   - opening/closing the connection on demand over **Bluetooth, USB, or
///     TCP/LAN (port 9100)** — whichever the chosen [PrinterConfig.type] is,
///   - building ESC/POS bytes via [ReceiptBuilder] and writing them out,
///   - kicking the cash drawer (ESC p — RJ11/RJ12 wired through the printer).
///
/// **Invariant — sale flow safety**: every public method catches its own
/// exceptions and returns a bool. The caller (POS checkout) MUST be able to
/// fire-and-forget; printing failure must NEVER block or roll back a sale. If
/// anything throws, [lastErrorMessage] is populated, status is flipped to
/// [HardwareConnectionStatus.error], listeners are notified, and the method
/// returns false.
class HardwareService extends ChangeNotifier {
  HardwareService._() : _buildTransport = buildTransport;

  /// Test-only constructor — injects a single transport used for ALL
  /// connection types so unit tests can drive the service without the real
  /// dart:io sockets / native plugins (unavailable under `flutter test`).
  @visibleForTesting
  HardwareService.test(PrinterTransport transport)
      : _buildTransport = ((_) => transport);

  // Singleton with a test override seam.
  static HardwareService _instance = HardwareService._();
  static HardwareService get instance => _instance;

  @visibleForTesting
  static void debugOverrideInstance(HardwareService override) {
    _instance = override;
  }

  @visibleForTesting
  static void debugResetInstance() {
    _instance = HardwareService._();
  }

  // SharedPreferences keys.
  static const String _kEnabled = 'hardware_enabled';
  static const String _kConfig = 'hardware_printer_config';
  // Legacy keys (BT-only era) — read for migration, written for back-compat.
  static const String _kDeviceMac = 'hardware_device_mac';
  static const String _kDeviceName = 'hardware_device_name';

  /// Builds a transport for a given config. Production → real BT/USB/TCP
  /// (web → no-op stubs). Tests → a fixed injected fake.
  final PrinterTransport Function(PrinterConfig) _buildTransport;

  // Active transport, lazily built from [_config] and rebuilt when the
  // selected printer's transport type changes.
  PrinterTransport? _activeTransport;
  PrinterConfig? _activeFor;

  bool _isEnabled = false;
  HardwareConnectionStatus _status = HardwareConnectionStatus.disabled;
  PrinterConfig? _config;
  String? _lastErrorMessage;
  bool _prefsLoaded = false;

  bool get isEnabled => _isEnabled;
  HardwareConnectionStatus get status => _status;
  PrinterConfig? get selectedConfig => _config;
  String? get lastErrorMessage => _lastErrorMessage;

  /// Back-compat getters (BT-only era). [selectedDeviceMac] now returns the
  /// generic transport address (MAC for BT, "ip:port" for network, "vid:pid"
  /// for USB).
  String? get selectedDeviceMac => _config?.address;
  String? get selectedDeviceName => _config?.name;

  @visibleForTesting
  bool get debugPrefsLoaded => _prefsLoaded;

  /// Resolve (and cache) the active transport for the current config.
  PrinterTransport? _transport() {
    final cfg = _config;
    if (cfg == null) return null;
    if (_activeTransport == null || _activeFor != cfg) {
      _activeTransport = _buildTransport(cfg);
      _activeFor = cfg;
    }
    return _activeTransport;
  }

  /// Hydrate from SharedPreferences. Idempotent. Always succeeds (void) — a
  /// prefs failure leaves us with the default-disabled state.
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_kEnabled) ?? false;
      _config = PrinterConfig.decode(prefs.getString(_kConfig));
      // Migrate the legacy BT-only selection if no new config exists.
      if (_config == null) {
        final mac = prefs.getString(_kDeviceMac);
        if (mac != null && mac.isNotEmpty) {
          _config = PrinterConfig(
            type: PrinterConnectionType.bluetooth,
            address: mac,
            name: prefs.getString(_kDeviceName) ?? mac,
            paperSize: PaperSize.mm58, // pocket BT printers are usually 58mm
          );
        }
      }
      _status = _isEnabled
          ? HardwareConnectionStatus.disconnected
          : HardwareConnectionStatus.disabled;
    } catch (e) {
      _lastErrorMessage = 'No se pudo leer la configuración local: $e';
    } finally {
      _prefsLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _persistPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, _isEnabled);
      final cfg = _config;
      if (cfg != null) {
        await prefs.setString(_kConfig, cfg.encode());
        await prefs.setString(_kDeviceName, cfg.name);
        if (cfg.isBluetooth) {
          await prefs.setString(_kDeviceMac, cfg.address);
        } else {
          await prefs.remove(_kDeviceMac);
        }
      } else {
        await prefs.remove(_kConfig);
        await prefs.remove(_kDeviceMac);
        await prefs.remove(_kDeviceName);
      }
    } catch (e) {
      _lastErrorMessage = 'No se pudo guardar la configuración: $e';
    }
  }

  /// Flip the master switch ON. If a printer is already remembered, try to
  /// (re)connect — best-effort; a failure just sits in disconnected/error.
  Future<void> enable() async {
    _isEnabled = true;
    _status = HardwareConnectionStatus.disconnected;
    _lastErrorMessage = null;
    await _persistPrefs();
    notifyListeners();
    if ((_config?.address ?? '').isNotEmpty) {
      unawaited(tryReconnect());
    }
  }

  /// Flip the master switch OFF. Tear down any live connection.
  Future<void> disable() async {
    _isEnabled = false;
    try {
      await _activeTransport?.disconnect();
    } catch (_) {
      // best-effort; tearing down anyway
    }
    _status = HardwareConnectionStatus.disabled;
    _lastErrorMessage = null;
    await _persistPrefs();
    notifyListeners();
  }

  /// List paired Bluetooth devices (trusted in OS settings).
  Future<List<PrinterDeviceInfo>> listPairedDevices() =>
      _listDevices(PrinterConnectionType.bluetooth);

  /// List currently attached USB devices.
  Future<List<PrinterDeviceInfo>> listUsbDevices() =>
      _listDevices(PrinterConnectionType.usb);

  Future<List<PrinterDeviceInfo>> _listDevices(
      PrinterConnectionType type) async {
    try {
      final probe = _buildTransport(
        PrinterConfig(type: type, address: '_probe', name: ''),
      );
      return await probe.bondedDevices();
    } catch (e) {
      _lastErrorMessage = 'No se pudieron listar los dispositivos: $e';
      _status = HardwareConnectionStatus.error;
      notifyListeners();
      return const [];
    }
  }

  /// Remember the chosen printer (full config). Does NOT auto-connect — call
  /// [tryReconnect] explicitly so the UI can show a spinner.
  Future<void> selectPrinter(PrinterConfig config) async {
    // If the transport type changed, drop the old live connection.
    if (_activeFor != null && _activeFor!.type != config.type) {
      try {
        await _activeTransport?.disconnect();
      } catch (_) {}
      _activeTransport = null;
      _activeFor = null;
    }
    _config = config;
    await _persistPrefs();
    notifyListeners();
  }

  /// Back-compat: remember a Bluetooth printer by MAC.
  Future<void> selectDevice(String address, String name) => selectPrinter(
        PrinterConfig(
          type: PrinterConnectionType.bluetooth,
          address: address,
          name: name,
          paperSize: _config?.paperSize ?? PaperSize.mm58,
        ),
      );

  /// Remember a USB printer by "vid:pid".
  Future<void> selectUsbDevice(String address, String name) => selectPrinter(
        PrinterConfig(
          type: PrinterConnectionType.usb,
          address: address,
          name: name,
          paperSize: _config?.paperSize ?? PaperSize.mm80,
        ),
      );

  /// Remember a network printer (raw TCP, default port 9100).
  Future<void> selectNetworkPrinter(String host,
      {int port = kDefaultPrinterPort, String? name}) {
    final h = host.trim();
    return selectPrinter(
      PrinterConfig(
        type: PrinterConnectionType.network,
        address: '$h:$port',
        name: (name ?? '').trim().isNotEmpty ? name!.trim() : 'Impresora $h',
        paperSize: _config?.paperSize ?? PaperSize.mm80,
      ),
    );
  }

  /// Change the receipt paper width for the selected printer.
  Future<void> setPaperSize(PaperSize size) async {
    final cfg = _config;
    if (cfg == null || cfg.paperSize == size) return;
    _config = cfg.copyWith(paperSize: size);
    await _persistPrefs();
    notifyListeners();
  }

  /// Attempt to (re)open the connection to the saved printer. Returns false
  /// if nothing is selected, the master switch is off, or the transport
  /// fails. NEVER throws.
  Future<bool> tryReconnect() async {
    if (!_isEnabled) return false;
    final cfg = _config;
    if (cfg == null || cfg.address.isEmpty) {
      _lastErrorMessage = 'No hay impresora seleccionada.';
      _status = HardwareConnectionStatus.error;
      notifyListeners();
      return false;
    }
    final t = _transport();
    if (t == null) {
      _lastErrorMessage = 'No hay impresora seleccionada.';
      _status = HardwareConnectionStatus.error;
      notifyListeners();
      return false;
    }
    _status = HardwareConnectionStatus.connecting;
    _lastErrorMessage = null;
    notifyListeners();
    try {
      final ok = await t.connect(cfg.address);
      _status = ok
          ? HardwareConnectionStatus.connected
          : HardwareConnectionStatus.error;
      if (!ok) {
        _lastErrorMessage = 'No se pudo conectar a la impresora.';
      }
      notifyListeners();
      return ok;
    } catch (e) {
      _status = HardwareConnectionStatus.error;
      _lastErrorMessage = 'Error de conexión: $e';
      notifyListeners();
      return false;
    }
  }

  /// Build + send a sale receipt. See class doc for the error contract.
  /// `openDrawer` is wired into the same byte stream the printer eats.
  Future<bool> printSaleReceipt(
    ReceiptTenantInfo tenant,
    List<ReceiptLine> lines,
    double total,
    String paymentMethod, {
    bool openDrawer = true,
  }) async {
    if (!_isEnabled) return true; // silent no-op (see class doc)

    try {
      final t = _transport();
      if (t == null) {
        _lastErrorMessage = 'No hay impresora seleccionada.';
        _status = HardwareConnectionStatus.error;
        notifyListeners();
        return false;
      }
      if (!await t.isConnected()) {
        final reconnected = await tryReconnect();
        if (!reconnected) return false;
      }

      final bytes = await ReceiptBuilder(
        tenant: tenant,
        lines: lines,
        total: total,
        paymentMethod: paymentMethod,
        paperSize: _config?.paperSize ?? PaperSize.mm80,
        openDrawer: openDrawer,
      ).build();

      await t.write(bytes);
      _status = HardwareConnectionStatus.connected;
      _lastErrorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _status = HardwareConnectionStatus.error;
      _lastErrorMessage = 'No se pudo imprimir el recibo: $e';
      notifyListeners();
      return false;
    }
  }

  /// Send ONLY the drawer-kick command, no receipt. ESC p m=0 t1=25 t2=250
  /// (0x1B 0x70 0x00 0x19 0xFA) — the standard RJ11/RJ12 pulse the DIG-KR410
  /// answers to. If a printer needs the alternate pin, swap m=0 → m=1.
  Future<bool> openCashDrawer() async {
    if (!_isEnabled) return true; // silent no-op
    try {
      final t = _transport();
      if (t == null) {
        _lastErrorMessage = 'No hay impresora seleccionada.';
        _status = HardwareConnectionStatus.error;
        notifyListeners();
        return false;
      }
      if (!await t.isConnected()) {
        final reconnected = await tryReconnect();
        if (!reconnected) return false;
      }
      await t.write(const [27, 112, 0, 25, 250]);
      _status = HardwareConnectionStatus.connected;
      _lastErrorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _status = HardwareConnectionStatus.error;
      _lastErrorMessage = 'No se pudo abrir el cajón: $e';
      notifyListeners();
      return false;
    }
  }
}
