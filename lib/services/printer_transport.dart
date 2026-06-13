// Spec: specs/046-impresora-usb-lan-escpos/spec.md

/// A device the user can pick in the printer picker: a friendly [name] and
/// the transport-specific [address] (BT MAC, USB id, or "ip:port").
typedef PrinterDeviceInfo = ({String name, String address});

/// Transport-agnostic seam over a thermal printer connection. The same
/// ESC/POS byte stream ([ReceiptBuilder] output) flows through any
/// implementation — Bluetooth, USB, or raw TCP (port 9100).
///
/// Implementations MUST swallow plugin/socket errors where the contract
/// says so (connect/disconnect/isConnected/bondedDevices return bools or
/// empty lists); [write] is the only method allowed to throw, and
/// [HardwareService] catches it so a printing failure never blocks a sale.
abstract class PrinterTransport {
  /// Open a connection to [address]. Returns true on success, false (never
  /// throws) on failure.
  Future<bool> connect(String address);

  /// Close the live connection. Returns true if closed OR nothing to close.
  Future<bool> disconnect();

  /// Cheap probe: do we have an open sink? No round-trip to the device.
  Future<bool> isConnected();

  /// Enumerate devices available for this transport:
  ///   - bluetooth → bonded/paired devices (pairing happens in OS settings)
  ///   - usb       → currently attached USB devices
  ///   - network   → [] (no discovery; the user types the IP)
  /// Returns [] on any failure — never throws.
  Future<List<PrinterDeviceInfo>> bondedDevices();

  /// Push raw bytes. Throws if the connection is not open; the caller
  /// translates the throw into a bool + error status.
  Future<void> write(List<int> bytes);
}

/// Back-compat alias. The codebase (and existing tests) referred to the
/// printer seam as `BluetoothTransport` when Bluetooth was the only
/// transport. Kept so `implements BluetoothTransport` keeps compiling.
typedef BluetoothTransport = PrinterTransport;
