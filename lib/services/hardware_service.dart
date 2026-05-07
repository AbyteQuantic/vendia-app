import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'receipt_builder.dart';

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

/// Thin abstraction over the Bluetooth radio so the service is unit-testable
/// without the platform plugin. The real implementation just delegates to
/// flutter_bluetooth_serial; tests inject a fake that records calls and can
/// be configured to throw or succeed.
abstract class BluetoothTransport {
  /// Open a socket to the device with the given MAC. Returns true on
  /// success. Implementations MUST swallow any plugin error and return
  /// false — the caller decides how to surface failure.
  Future<bool> connect(String address);

  /// Close the live socket. Returns true if the close succeeded OR if
  /// there was nothing to close.
  Future<bool> disconnect();

  /// Cheap probe of "do we have an open output sink?". No round-trip
  /// to the radio.
  Future<bool> isConnected();

  /// Enumerate paired/bonded devices the user has already trusted in
  /// the system Bluetooth settings. We never trigger discovery here —
  /// pairing happens in the OS settings, not in our app.
  Future<List<({String name, String address})>> bondedDevices();

  /// Push raw bytes down the open socket. Throws if the socket is not
  /// open; the service catches and translates to a bool.
  Future<void> write(List<int> bytes);
}

/// Production transport — wraps flutter_bluetooth_serial. Holds a single
/// BluetoothConnection at a time. The library itself is happy to leak
/// stale sockets if you forget to close them, so we are strict about
/// nulling _connection on every disconnect/error path.
class FlutterBluetoothSerialTransport implements BluetoothTransport {
  BluetoothConnection? _connection;

  @override
  Future<bool> connect(String address) async {
    // If we already have a live socket to *this* device, reuse it.
    if (_connection?.isConnected == true) {
      return true;
    }
    // If we have a stale (closed) connection object, drop it before
    // opening a new one.
    if (_connection != null) {
      try {
        await _connection!.close();
      } catch (_) {
        // already closed — ignore
      }
      _connection = null;
    }
    _connection = await BluetoothConnection.toAddress(address);
    return _connection?.isConnected == true;
  }

  @override
  Future<bool> disconnect() async {
    final c = _connection;
    _connection = null;
    if (c == null) return true;
    try {
      await c.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isConnected() async {
    return _connection?.isConnected == true;
  }

  @override
  Future<List<({String name, String address})>> bondedDevices() async {
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    return devices
        .map((d) => (
              name: (d.name ?? '').isEmpty ? d.address : d.name!,
              address: d.address,
            ))
        .toList(growable: false);
  }

  @override
  Future<void> write(List<int> bytes) async {
    final c = _connection;
    if (c == null || !c.isConnected) {
      throw StateError('Bluetooth socket is not open');
    }
    c.output.add(Uint8List.fromList(bytes));
    await c.output.allSent;
  }
}

/// Singleton in charge of:
///   - persisting the user's "use printer" master switch + selected device,
///   - opening/closing the Bluetooth socket on demand,
///   - building ESC/POS bytes via [ReceiptBuilder] and writing them out,
///   - kicking the cash drawer.
///
/// **Invariant — sale flow safety**: every public method catches its own
/// exceptions and returns a bool. The caller (POS checkout) MUST be able
/// to fire-and-forget; printing failure must NEVER block or roll back a
/// sale. If anything throws, [lastErrorMessage] is populated, status is
/// flipped to [HardwareConnectionStatus.error], listeners are notified,
/// and the method returns false.
class HardwareService extends ChangeNotifier {
  HardwareService._({BluetoothTransport? transport})
      : _transport = transport ?? FlutterBluetoothSerialTransport();

  /// Test-only constructor — accepts an injected transport so unit
  /// tests can drive the service without spinning up the real
  /// flutter_bluetooth_serial plugin (which is not available under
  /// `flutter test`).
  @visibleForTesting
  HardwareService.test(BluetoothTransport transport) : _transport = transport;

  // Singleton with a test override seam. Tests call
  // `HardwareService.debugOverrideInstance(...)` from setUp() to inject
  // a fake transport + clean state, then `debugResetInstance()` from
  // tearDown() to drop their override.
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

  // SharedPreferences keys — kept private + namespaced so we can grep
  // for them when we add the Hardware Settings screen later.
  static const String _kEnabled = 'hardware_enabled';
  static const String _kDeviceMac = 'hardware_device_mac';
  static const String _kDeviceName = 'hardware_device_name';

  final BluetoothTransport _transport;

  bool _isEnabled = false;
  HardwareConnectionStatus _status = HardwareConnectionStatus.disabled;
  String? _selectedDeviceMac;
  String? _selectedDeviceName;
  String? _lastErrorMessage;
  bool _prefsLoaded = false;

  bool get isEnabled => _isEnabled;
  HardwareConnectionStatus get status => _status;
  String? get selectedDeviceMac => _selectedDeviceMac;
  String? get selectedDeviceName => _selectedDeviceName;
  String? get lastErrorMessage => _lastErrorMessage;

  @visibleForTesting
  BluetoothTransport get debugTransport => _transport;

  /// Hydrate from SharedPreferences. Idempotent — calling twice is cheap
  /// and yields the same state. Always succeeds (returns void) — a prefs
  /// failure leaves us with the default-disabled state.
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_kEnabled) ?? false;
      _selectedDeviceMac = prefs.getString(_kDeviceMac);
      _selectedDeviceName = prefs.getString(_kDeviceName);
      _status = _isEnabled
          ? HardwareConnectionStatus.disconnected
          : HardwareConnectionStatus.disabled;
    } catch (e) {
      // Prefs not available — keep defaults, don't crash the app.
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
      if (_selectedDeviceMac != null) {
        await prefs.setString(_kDeviceMac, _selectedDeviceMac!);
      } else {
        await prefs.remove(_kDeviceMac);
      }
      if (_selectedDeviceName != null) {
        await prefs.setString(_kDeviceName, _selectedDeviceName!);
      } else {
        await prefs.remove(_kDeviceName);
      }
    } catch (e) {
      // Prefs write failed — log via lastErrorMessage but never throw.
      _lastErrorMessage = 'No se pudo guardar la configuración: $e';
    }
  }

  /// Flip the master switch ON. If a device is already remembered, try
  /// to (re)connect — but a connect failure is fine, we just sit in
  /// `disconnected`/`error` until the user retries from the Settings UI.
  Future<void> enable() async {
    _isEnabled = true;
    _status = HardwareConnectionStatus.disconnected;
    _lastErrorMessage = null;
    await _persistPrefs();
    notifyListeners();
    if ((_selectedDeviceMac ?? '').isNotEmpty) {
      // Don't await — auto-connect is best-effort.
      unawaited(tryReconnect());
    }
  }

  /// Flip the master switch OFF. Tear down any live socket — we don't
  /// want a forgotten connection chewing battery.
  Future<void> disable() async {
    _isEnabled = false;
    try {
      await _transport.disconnect();
    } catch (_) {
      // Disconnect best-effort; we're tearing down anyway.
    }
    _status = HardwareConnectionStatus.disabled;
    _lastErrorMessage = null;
    await _persistPrefs();
    notifyListeners();
  }

  /// List devices the user has already paired in the OS settings.
  /// Returns [] on any failure — never throws.
  Future<List<({String name, String address})>> listPairedDevices() async {
    try {
      return await _transport.bondedDevices();
    } catch (e) {
      _lastErrorMessage = 'No se pudieron listar los dispositivos: $e';
      _status = HardwareConnectionStatus.error;
      notifyListeners();
      return const [];
    }
  }

  /// Remember the chosen printer. Does NOT auto-connect — call
  /// [tryReconnect] explicitly so the UI can show a spinner.
  Future<void> selectDevice(String address, String name) async {
    _selectedDeviceMac = address;
    _selectedDeviceName = name;
    await _persistPrefs();
    notifyListeners();
  }

  /// Attempt to (re)open the socket to the saved device. Returns false
  /// if no device is selected, the master switch is off, or the radio
  /// throws. NEVER throws.
  Future<bool> tryReconnect() async {
    if (!_isEnabled) return false;
    final mac = _selectedDeviceMac;
    if (mac == null || mac.isEmpty) {
      _lastErrorMessage = 'No hay impresora seleccionada.';
      _status = HardwareConnectionStatus.error;
      notifyListeners();
      return false;
    }
    _status = HardwareConnectionStatus.connecting;
    _lastErrorMessage = null;
    notifyListeners();
    try {
      final ok = await _transport.connect(mac);
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
      _lastErrorMessage = 'Error de conexión Bluetooth: $e';
      notifyListeners();
      return false;
    }
  }

  /// Build + send a sale receipt. Wraps every step in try/catch:
  ///   - master switch off  → return true (silent no-op).
  ///   - connect failure    → return false, status=error.
  ///   - build failure      → return false, status=error (very rare —
  ///                          ReceiptBuilder catches its own logo
  ///                          decode errors).
  ///   - write failure      → return false, status=error.
  ///
  /// `openDrawer` is wired to the receipt itself (the drawer kick is
  /// part of the same byte stream the printer eats). If the cashier
  /// wants the drawer without the receipt — e.g. for change — call
  /// [openCashDrawer] instead.
  Future<bool> printSaleReceipt(
    ReceiptTenantInfo tenant,
    List<ReceiptLine> lines,
    double total,
    String paymentMethod, {
    bool openDrawer = true,
  }) async {
    // Silent no-op when the master switch is off. We return TRUE on
    // purpose: from the caller's perspective there's nothing to handle.
    if (!_isEnabled) return true;

    try {
      // Make sure we have an open socket. If the radio dropped between
      // sales (very common — the printer turns off when idle), reconnect
      // transparently before writing.
      if (!await _transport.isConnected()) {
        final reconnected = await tryReconnect();
        if (!reconnected) return false;
      }

      final bytes = await ReceiptBuilder(
        tenant: tenant,
        lines: lines,
        total: total,
        paymentMethod: paymentMethod,
        openDrawer: openDrawer,
      ).build();

      await _transport.write(bytes);
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

  /// Send ONLY the drawer-kick command, no receipt. Useful when the
  /// cashier needs to open the drawer for change without printing.
  /// Pin 2, 25ms on, 250ms off — same RJ11 wiring as the receipt path.
  Future<bool> openCashDrawer() async {
    if (!_isEnabled) return true; // silent no-op, see printSaleReceipt
    try {
      if (!await _transport.isConnected()) {
        final reconnected = await tryReconnect();
        if (!reconnected) return false;
      }
      await _transport.write(const [27, 112, 0, 25, 250]);
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

  @visibleForTesting
  bool get debugPrefsLoaded => _prefsLoaded;
}
