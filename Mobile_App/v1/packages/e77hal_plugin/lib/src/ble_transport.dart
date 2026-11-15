import 'dart:async';

/// A device found while scanning (`statusScanResult` of the Cordova plugin).
class BleScanResult {
  const BleScanResult({
    required this.name,
    required this.address,
    required this.rssi,
    this.serviceUuids = const [],
  });

  /// Advertised (scan record) device name, '' when none.
  final String name;

  /// MAC address (Android) or peripheral UUID (iOS).
  final String address;
  final int rssi;

  /// Advertised service UUIDs, upper-case short form where possible ("180D").
  final List<String> serviceUuids;
}

/// Android bond states (`BluetoothDevice.BOND_*`).
enum BondState { none, bonding, bonded, unknown }

/// A link-layer event of an established or failed connection.
enum BleLinkState { connected, disconnected }

class BleLinkEvent {
  const BleLinkEvent(this.state, {this.error});
  final BleLinkState state;
  final String? error;
}

/// Generic Bluetooth LE operations needed by [E77hal]. This is the part that
/// the Cordova plugin implemented natively (E77halPlugin.java / .m); here a
/// transport can be plugged in (the default one uses `flutter_reactive_ble`).
abstract class BleTransport {
  /// Makes sure permissions are granted and Bluetooth is on. Returns null
  /// when ready, otherwise a human readable reason.
  Future<String?> prepare();

  /// Scans without service filter (Cordova `startScan({})`) unless
  /// [withServices] is given. Cancel the subscription to stop scanning.
  Stream<BleScanResult> scan({List<String> withServices = const []});

  /// Connects; cancel the subscription to disconnect. With [autoConnect]
  /// (Android) the OS keeps trying until the device is in range.
  Stream<BleLinkEvent> connect(String address, {bool autoConnect = false});

  /// GATT service discovery. Returns the discovered service UUIDs.
  Future<List<String>> discoverServices(String address);

  Future<List<int>> read(String address, String service, String characteristic);

  /// Write with response (the Cordova plugin's default write type).
  Future<void> write(
      String address, String service, String characteristic, List<int> value);

  /// Write without response (fast, for bulk data). Defaults to a normal write.
  Future<void> writeNoResponse(
          String address, String service, String characteristic, List<int> value) =>
      write(address, service, characteristic, value);

  /// Enables notifications (or indications when the characteristic only
  /// supports those) and streams the received values.
  Stream<List<int>> subscribe(
      String address, String service, String characteristic);

  /// Asks for a larger ATT MTU (Android); returns the negotiated value.
  /// Transports without support return the default 23.
  Future<int> requestMtu(String address, int mtu) async => 23;

  Future<BondState> bondState(String address);

  /// Bond state changes of [address] (broadcast stream).
  Stream<BondState> watchBond(String address);

  /// Starts OS bonding (`BluetoothDevice.createBond()`); false when the
  /// system refused to start it.
  Future<bool> createBond(String address);
}
