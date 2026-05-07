import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/services/hardware_service.dart';
import 'package:vendia_pos/services/receipt_builder.dart';

/// Configurable fake transport. Each method can be programmed to either
/// succeed (the default) or throw a specific error so we can assert the
/// HardwareService catches it cleanly.
class FakeTransport implements BluetoothTransport {
  bool throwOnConnect = false;
  bool throwOnDisconnect = false;
  bool throwOnIsConnected = false;
  bool throwOnBondedDevices = false;
  bool throwOnWrite = false;
  bool connectReturns = true;
  bool isConnectedValue = false;

  // Spy counters / call recorders so tests can assert behavior.
  int connectCalls = 0;
  int disconnectCalls = 0;
  int writeCalls = 0;
  String? lastConnectAddress;
  List<int>? lastWriteBytes;

  @override
  Future<bool> connect(String address) async {
    connectCalls++;
    lastConnectAddress = address;
    if (throwOnConnect) throw Exception('connect blew up');
    isConnectedValue = connectReturns;
    return connectReturns;
  }

  @override
  Future<bool> disconnect() async {
    disconnectCalls++;
    if (throwOnDisconnect) throw Exception('disconnect blew up');
    isConnectedValue = false;
    return true;
  }

  @override
  Future<bool> isConnected() async {
    if (throwOnIsConnected) throw Exception('isConnected blew up');
    return isConnectedValue;
  }

  @override
  Future<List<({String name, String address})>> bondedDevices() async {
    if (throwOnBondedDevices) throw Exception('bondedDevices blew up');
    return const [
      (name: 'Printer A', address: '00:11:22:33:44:55'),
    ];
  }

  @override
  Future<void> write(List<int> bytes) async {
    writeCalls++;
    lastWriteBytes = bytes;
    if (throwOnWrite) throw Exception('write blew up');
  }
}

/// Build a HardwareService instance backed by a fake transport. The
/// service has a private constructor, so we go through the testing
/// override seam (debugOverrideInstance) and read it back.
HardwareService _serviceWith(FakeTransport t) {
  // The factory constructor we expose here is intentionally minimal —
  // tests inject the transport via a small test-only subclass.
  final service = _TestableHardwareService(t);
  HardwareService.debugOverrideInstance(service);
  return service;
}

/// Public thin wrapper that lets us pass a transport into the otherwise
/// private constructor. The production code path goes through
/// HardwareService.instance, never through this class.
class _TestableHardwareService extends HardwareService {
  _TestableHardwareService(super.t) : super.test();
}

void main() {
  // Every plugin call (SharedPreferences, asset bundle for capability
  // profile) needs the test binding initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HardwareService.debugResetInstance();
  });

  const tenant = ReceiptTenantInfo(businessName: 'BURRITOS BRYAN');
  const lines = [
    ReceiptLine(name: 'Empanada', quantity: 1, unitPrice: 500),
  ];

  test('printSaleReceipt is a silent no-op when isEnabled=false', () async {
    final fake = FakeTransport();
    final svc = _serviceWith(fake);
    // Default state: isEnabled is false (we never called enable()).

    final ok = await svc.printSaleReceipt(tenant, lines, 500, 'efectivo');

    expect(ok, isTrue, reason: 'no-op must be reported as success to caller');
    expect(fake.connectCalls, 0,
        reason: 'transport must not be touched when master switch is OFF');
    expect(fake.writeCalls, 0);
    expect(svc.status, HardwareConnectionStatus.disabled);
  });

  test('printSaleReceipt → false + status=error when connect throws', () async {
    final fake = FakeTransport()..throwOnConnect = true;
    final svc = _serviceWith(fake);
    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');

    // enable() may have kicked an auto-reconnect; await microtasks.
    await Future<void>.delayed(Duration.zero);

    bool didThrow = false;
    bool? result;
    try {
      result = await svc.printSaleReceipt(tenant, lines, 500, 'efectivo');
    } catch (_) {
      didThrow = true;
    }

    expect(didThrow, isFalse,
        reason: 'printSaleReceipt MUST NOT propagate exceptions');
    expect(result, isFalse);
    expect(svc.status, HardwareConnectionStatus.error);
    expect(svc.lastErrorMessage, isNotNull);
  });

  test('openCashDrawer → false when write throws, no rethrow', () async {
    final fake = FakeTransport()..isConnectedValue = true;
    final svc = _serviceWith(fake);
    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');
    fake.throwOnWrite = true;

    bool didThrow = false;
    bool? result;
    try {
      result = await svc.openCashDrawer();
    } catch (_) {
      didThrow = true;
    }

    expect(didThrow, isFalse,
        reason: 'openCashDrawer MUST NOT propagate exceptions');
    expect(result, isFalse);
    expect(svc.status, HardwareConnectionStatus.error);
    expect(svc.lastErrorMessage, isNotNull);
  });

  test('persistence: enable + selectDevice round-trips through prefs',
      () async {
    final fake1 = FakeTransport();
    final svc1 = _serviceWith(fake1);
    await svc1.enable();
    await svc1.selectDevice('00:AA:BB:CC:DD:EE', 'My Star Printer');

    expect(svc1.isEnabled, isTrue);
    expect(svc1.selectedDeviceMac, '00:AA:BB:CC:DD:EE');

    // Simulate restart: drop override, build a fresh service with a
    // new transport, hydrate from the SAME mock prefs store.
    HardwareService.debugResetInstance();
    final fake2 = FakeTransport();
    final svc2 = _serviceWith(fake2);
    await svc2.loadFromPrefs();

    expect(svc2.isEnabled, isTrue,
        reason: 'master switch must survive restart');
    expect(svc2.selectedDeviceMac, '00:AA:BB:CC:DD:EE',
        reason: 'selected device MAC must survive restart');
    expect(svc2.selectedDeviceName, 'My Star Printer');
    expect(svc2.status, HardwareConnectionStatus.disconnected,
        reason: 'after a fresh load with the switch ON we are disconnected '
            'until tryReconnect succeeds');
  });

  test('tryReconnect after disconnect re-establishes connected state',
      () async {
    final fake = FakeTransport();
    final svc = _serviceWith(fake);
    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');

    // First connect: succeeds.
    final ok1 = await svc.tryReconnect();
    expect(ok1, isTrue);
    expect(svc.status, HardwareConnectionStatus.connected);

    // Simulate the printer being unplugged.
    await fake.disconnect();
    expect(await fake.isConnected(), isFalse);

    // Reconnect: we expect the service to try again and succeed.
    fake.connectReturns = true;
    final ok2 = await svc.tryReconnect();
    expect(ok2, isTrue,
        reason: 'tryReconnect must re-open the socket after a drop');
    expect(svc.status, HardwareConnectionStatus.connected);
    expect(fake.connectCalls, greaterThanOrEqualTo(2));
  });

  test('listPairedDevices → [] when transport throws (never propagates)',
      () async {
    final fake = FakeTransport()..throwOnBondedDevices = true;
    final svc = _serviceWith(fake);
    await svc.enable();

    bool didThrow = false;
    List<({String name, String address})>? result;
    try {
      result = await svc.listPairedDevices();
    } catch (_) {
      didThrow = true;
    }

    expect(didThrow, isFalse,
        reason: 'listPairedDevices MUST NOT propagate exceptions');
    expect(result, isEmpty);
    expect(svc.status, HardwareConnectionStatus.error);
  });

  test('disable() tears down the socket and persists the OFF state',
      () async {
    final fake = FakeTransport();
    final svc = _serviceWith(fake);
    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');
    await svc.tryReconnect();
    expect(svc.status, HardwareConnectionStatus.connected);

    await svc.disable();
    expect(svc.isEnabled, isFalse);
    expect(svc.status, HardwareConnectionStatus.disabled);
    expect(fake.disconnectCalls, greaterThanOrEqualTo(1));

    // Round-trip the prefs to confirm OFF is sticky.
    HardwareService.debugResetInstance();
    final fake2 = FakeTransport();
    final svc2 = _serviceWith(fake2);
    await svc2.loadFromPrefs();
    expect(svc2.isEnabled, isFalse);
  });
}
