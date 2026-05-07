import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vendia_pos/screens/admin/hardware_settings_screen.dart';
import 'package:vendia_pos/services/hardware_service.dart';
import 'package:vendia_pos/services/receipt_builder.dart';

/// Configurable fake transport. Identical to the one used by the
/// HardwareService unit tests — same shape, kept local so the two test
/// suites evolve independently.
class _FakeTransport implements BluetoothTransport {
  bool throwOnConnect = false;
  bool throwOnWrite = false;
  bool connectReturns = true;
  bool isConnectedValue = false;

  int connectCalls = 0;
  int writeCalls = 0;
  int bondedCalls = 0;
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
    isConnectedValue = false;
    return true;
  }

  @override
  Future<bool> isConnected() async => isConnectedValue;

  @override
  Future<List<({String name, String address})>> bondedDevices() async {
    bondedCalls++;
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

/// Public thin wrapper that lets us pass a transport into the otherwise
/// private constructor. Mirrors the wrapper from the service tests, with
/// a small instrumentation hook so the screen tests can assert that the
/// owner-facing "Imprimir prueba" button reached the service. We don't
/// reach into rootBundle here because `ReceiptBuilder.build()` loads an
/// asset via `CapabilityProfile.load()` which makes raw end-to-end
/// transport assertions flaky under `flutter test`. Spying at the service
/// boundary keeps the test focused on the screen contract.
class _TestableHardwareService extends HardwareService {
  _TestableHardwareService(super.t) : super.test();

  int printSaleReceiptCalls = 0;
  int openCashDrawerCalls = 0;

  @override
  Future<bool> printSaleReceipt(
    ReceiptTenantInfo tenant,
    List<ReceiptLine> lines,
    double total,
    String paymentMethod, {
    bool openDrawer = true,
  }) async {
    printSaleReceiptCalls++;
    return true;
  }

  @override
  Future<bool> openCashDrawer() async {
    openCashDrawerCalls++;
    return true;
  }
}

/// Build a HardwareService fixture and install it as the singleton via
/// the SP2-exposed `debugOverrideInstance` hook. The widget reads
/// `HardwareService.instance`, so this is enough to drive the screen.
_TestableHardwareService _installFakeService(_FakeTransport t) {
  final svc = _TestableHardwareService(t);
  HardwareService.debugOverrideInstance(svc);
  return svc;
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HardwareService.debugResetInstance();
  });

  testWidgets(
      'when isEnabled=false: shows master switch + description, hides device picker and tests',
      (tester) async {
    _installFakeService(_FakeTransport());

    await tester.pumpWidget(_wrap(const HardwareSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hardware_master_switch')), findsOneWidget);
    expect(find.text('Activar impresión y cajón'), findsOneWidget);

    // Off-state hint copy:
    expect(
      find.text(
          'Cuando lo active le pediremos permiso de Bluetooth.'),
      findsOneWidget,
    );

    // No device picker, no test buttons, no status indicator:
    expect(find.byKey(const Key('hardware_change_device_button')), findsNothing);
    expect(find.byKey(const Key('hardware_test_print_button')), findsNothing);
    expect(find.byKey(const Key('hardware_test_drawer_button')), findsNothing);
    expect(find.byKey(const Key('hardware_reconnect_button')), findsNothing);
  });

  testWidgets(
      'when status=connected: green dot, device name, test buttons enabled',
      (tester) async {
    final t = _FakeTransport()..connectReturns = true;
    final svc = _installFakeService(t);

    // Drive the service into `connected` via its public API.
    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');
    await svc.tryReconnect();
    expect(svc.status, HardwareConnectionStatus.connected);

    await tester.pumpWidget(_wrap(const HardwareSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hardware_status_dot_connected')),
        findsOneWidget);
    expect(find.textContaining('Conectado a Printer A'), findsOneWidget);
    expect(find.byKey(const Key('hardware_test_print_button')), findsOneWidget);
    expect(find.byKey(const Key('hardware_test_drawer_button')), findsOneWidget);
    expect(find.byKey(const Key('hardware_reconnect_button')), findsNothing);

    // Test buttons should be enabled (onPressed != null).
    final printBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('hardware_test_print_button')));
    final drawerBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('hardware_test_drawer_button')));
    expect(printBtn.onPressed, isNotNull);
    expect(drawerBtn.onPressed, isNotNull);
  });

  testWidgets(
      'when status=error: red dot, error message, reconnect button enabled',
      (tester) async {
    final t = _FakeTransport()..throwOnConnect = true;
    final svc = _installFakeService(t);

    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');
    await svc.tryReconnect(); // triggers throw → status=error
    expect(svc.status, HardwareConnectionStatus.error);

    await tester.pumpWidget(_wrap(const HardwareSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hardware_status_dot_error')), findsOneWidget);
    expect(find.textContaining('Error:'), findsOneWidget);

    final reconnect = find.byKey(const Key('hardware_reconnect_button'));
    expect(reconnect, findsOneWidget);
    final btn = tester.widget<TextButton>(reconnect);
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('tap "Imprimir prueba" calls HardwareService.printSaleReceipt',
      (tester) async {
    final t = _FakeTransport()
      ..connectReturns = true
      ..isConnectedValue = true; // skip auto-reconnect path
    final svc = _installFakeService(t);

    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');
    await svc.tryReconnect();
    expect(svc.status, HardwareConnectionStatus.connected);

    await tester.pumpWidget(_wrap(const HardwareSettingsScreen()));
    await tester.pumpAndSettle();

    expect(svc.printSaleReceiptCalls, 0);
    await tester.tap(find.byKey(const Key('hardware_test_print_button')));
    await tester.pumpAndSettle();

    // The screen invoked HardwareService.printSaleReceipt — exactly the
    // contract this test asserts. The byte-level wire assertions belong
    // to the HardwareService unit suite.
    expect(svc.printSaleReceiptCalls, 1);
  });

  testWidgets(
      'toggling master switch off calls disable() (state flips to disabled)',
      (tester) async {
    final t = _FakeTransport()..connectReturns = true;
    final svc = _installFakeService(t);

    // Start enabled+connected so the switch is ON.
    await svc.enable();
    await svc.selectDevice('00:11:22:33:44:55', 'Printer A');
    await svc.tryReconnect();
    expect(svc.isEnabled, isTrue);

    await tester.pumpWidget(_wrap(const HardwareSettingsScreen()));
    await tester.pumpAndSettle();

    // Tap the master switch → SwitchListTile passes false to onChanged
    // → screen calls service.disable().
    await tester.tap(find.byKey(const Key('hardware_master_switch')));
    await tester.pumpAndSettle();

    expect(svc.isEnabled, isFalse);
    expect(svc.status, HardwareConnectionStatus.disabled);
  });
}
