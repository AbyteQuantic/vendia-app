// Spec: specs/046-impresora-usb-lan-escpos/spec.md
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/services/hardware_service.dart';

/// Minimal fake used for every transport type (the service injects one fake
/// for all types via HardwareService.test).
class _FakeTransport implements BluetoothTransport {
  bool connectReturns = true;
  bool isConnectedValue = false;
  String? lastConnectAddress;
  List<int>? lastWriteBytes;

  @override
  Future<bool> connect(String address) async {
    lastConnectAddress = address;
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
  Future<List<PrinterDeviceInfo>> bondedDevices() async => const [
        (name: 'DIG-E200I', address: '1234:5678'),
      ];

  @override
  Future<void> write(List<int> bytes) async {
    lastWriteBytes = bytes;
  }
}

class _Testable extends HardwareService {
  _Testable(super.t) : super.test();
}

HardwareService _svc(_FakeTransport t) {
  final s = _Testable(t);
  HardwareService.debugOverrideInstance(s);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(HardwareService.debugResetInstance);

  test('selectNetworkPrinter stores a network config at ip:9100', () async {
    final svc = _svc(_FakeTransport());
    await svc.enable();
    await svc.selectNetworkPrinter('192.168.1.50', name: 'Caja');

    final cfg = svc.selectedConfig!;
    expect(cfg.type, PrinterConnectionType.network);
    expect(cfg.address, '192.168.1.50:9100');
    expect(cfg.name, 'Caja');
    expect(svc.selectedDeviceMac, '192.168.1.50:9100');
  });

  test('network config + connection round-trips through prefs', () async {
    final svc = _svc(_FakeTransport());
    await svc.enable();
    await svc.selectNetworkPrinter('10.0.0.7', port: 9100, name: 'Red');

    HardwareService.debugResetInstance();
    final svc2 = _svc(_FakeTransport());
    await svc2.loadFromPrefs();

    expect(svc2.isEnabled, isTrue);
    expect(svc2.selectedConfig?.type, PrinterConnectionType.network);
    expect(svc2.selectedConfig?.address, '10.0.0.7:9100');
  });

  test('tryReconnect connects using the network address', () async {
    final fake = _FakeTransport();
    final svc = _svc(fake);
    await svc.enable();
    await svc.selectNetworkPrinter('172.16.0.4', name: 'LAN');

    final ok = await svc.tryReconnect();
    expect(ok, isTrue);
    expect(svc.status, HardwareConnectionStatus.connected);
    expect(fake.lastConnectAddress, '172.16.0.4:9100');
  });

  test('selectUsbDevice stores a usb config', () async {
    final svc = _svc(_FakeTransport());
    await svc.enable();
    await svc.selectUsbDevice('1234:5678', 'DIG-E200I');
    expect(svc.selectedConfig?.type, PrinterConnectionType.usb);
    expect(svc.selectedConfig?.address, '1234:5678');
  });

  test('listUsbDevices delegates to the transport', () async {
    final svc = _svc(_FakeTransport());
    final devices = await svc.listUsbDevices();
    expect(devices, isNotEmpty);
    expect(devices.first.address, '1234:5678');
  });

  test('setPaperSize updates the selected config and persists', () async {
    final svc = _svc(_FakeTransport());
    await svc.enable();
    await svc.selectNetworkPrinter('10.0.0.9'); // defaults mm80
    expect(svc.selectedConfig?.paperSize, PaperSize.mm80);

    await svc.setPaperSize(PaperSize.mm58);
    expect(svc.selectedConfig?.paperSize, PaperSize.mm58);

    HardwareService.debugResetInstance();
    final svc2 = _svc(_FakeTransport());
    await svc2.loadFromPrefs();
    expect(svc2.selectedConfig?.paperSize, PaperSize.mm58);
  });
}
