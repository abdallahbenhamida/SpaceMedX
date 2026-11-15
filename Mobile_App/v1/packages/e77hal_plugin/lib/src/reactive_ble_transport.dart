import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_transport.dart';
import 'native_helper.dart';

/// `BleTransport` on top of `flutter_reactive_ble` (BSD-3) plus the small
/// native helper for the things that library does not provide (OS bonding,
/// permissions, enabling Bluetooth).
class ReactiveBleTransport implements BleTransport {
  ReactiveBleTransport({FlutterReactiveBle? ble, E77halNative? native})
      : _ble = ble ?? FlutterReactiveBle(),
        _native = native ?? const E77halNative();

  final FlutterReactiveBle _ble;
  final E77halNative _native;

  static const String _baseTail = '-0000-1000-8000-00805F9B34FB';

  static Uuid _uuid(String shortOrLong) {
    final s = shortOrLong.trim();
    return Uuid.parse(s.length == 4 ? '0000$s$_baseTail' : s);
  }

  static String _short(Uuid u) {
    final hex = u.data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    if (u.data.length == 2) return hex;
    if (u.data.length == 16 &&
        hex.startsWith('0000') &&
        hex.endsWith('00001000800000805F9B34FB')) {
      return hex.substring(4, 8);
    }
    return u.toString().toUpperCase();
  }

  QualifiedCharacteristic _qc(String address, String service, String char) =>
      QualifiedCharacteristic(
        deviceId: address,
        serviceId: _uuid(service),
        characteristicId: _uuid(char),
      );

  @override
  Future<String?> prepare() async {
    if (Platform.isAndroid) {
      if (!await _native.hasPermissions() &&
          !await _native.requestPermissions()) {
        return 'Bluetooth permissions were not granted. Please allow '
            '"Nearby devices" (Android 12+) or "Location" (Android 11 and '
            'below) for the app in the system settings.';
      }
      if (!await _native.isBluetoothEnabled() &&
          !await _native.requestEnableBluetooth()) {
        return 'Bluetooth is turned off. Please turn it on and try again.';
      }
      if (await _native.needsLocationServices() &&
          !await _native.isLocationEnabled()) {
        await _native.openLocationSettings();
        return 'Location services are turned off. Android needs them to '
            'find Bluetooth devices; turn them on and try again.';
      }
    }
    // Wait for the adapter to report "ready" (it needs a moment after being
    // switched on or after permissions were granted).
    var status = BleStatus.unknown;
    try {
      status = await _ble.statusStream
          .firstWhere((s) => s == BleStatus.ready)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      status = await _ble.statusStream.first
          .timeout(const Duration(seconds: 2), onTimeout: () => status);
    }
    switch (status) {
      case BleStatus.ready:
        return null;
      case BleStatus.unsupported:
        return 'Bluetooth Low Energy is not supported on this device.';
      case BleStatus.unauthorized:
        return 'Bluetooth permission is missing for this app.';
      case BleStatus.poweredOff:
        return 'Bluetooth is turned off. Please turn it on and try again.';
      case BleStatus.locationServicesDisabled:
        return 'Location services are turned off. Turn them on and try '
            'again.';
      case BleStatus.unknown:
        return 'Bluetooth is not ready yet. Please try again.';
    }
  }

  @override
  Stream<BleScanResult> scan({List<String> withServices = const []}) {
    return _ble
        .scanForDevices(
          withServices: withServices.map(_uuid).toList(),
          // The Cordova plugin used SCAN_MODE_LOW_LATENCY by default.
          scanMode: ScanMode.lowLatency,
        )
        .map((d) => BleScanResult(
              name: d.name,
              address: d.id,
              rssi: d.rssi,
              serviceUuids: d.serviceUuids.map(_short).toList(),
            ));
  }

  @override
  Stream<BleLinkEvent> connect(String address, {bool autoConnect = false}) {
    // flutter_reactive_ble sets Android's `autoConnect` flag when no timeout
    // is given, and clears it otherwise (the Cordova plugin used
    // autoConnect only for the Savvy ECG).
    final updates = _ble.connectToDevice(
      id: address,
      connectionTimeout: autoConnect ? null : const Duration(seconds: 25),
    );
    return updates
        .where((u) =>
            u.connectionState == DeviceConnectionState.connected ||
            u.connectionState == DeviceConnectionState.disconnected)
        .map((u) => BleLinkEvent(
              u.connectionState == DeviceConnectionState.connected
                  ? BleLinkState.connected
                  : BleLinkState.disconnected,
              error: u.failure?.message,
            ));
  }

  @override
  Future<List<String>> discoverServices(String address) async {
    await _ble.discoverAllServices(address);
    final services = await _ble.getDiscoveredServices(address);
    return services.map((s) => _short(s.id)).toList();
  }

  @override
  Future<List<int>> read(String address, String service, String characteristic) =>
      _ble.readCharacteristic(_qc(address, service, characteristic));

  @override
  Future<void> write(String address, String service, String characteristic,
          List<int> value) =>
      _ble.writeCharacteristicWithResponse(
        _qc(address, service, characteristic),
        value: value,
      );

  @override
  Future<void> writeNoResponse(String address, String service,
          String characteristic, List<int> value) =>
      _ble.writeCharacteristicWithoutResponse(
        _qc(address, service, characteristic),
        value: value,
      );

  @override
  Stream<List<int>> subscribe(
          String address, String service, String characteristic) =>
      _ble.subscribeToCharacteristic(_qc(address, service, characteristic));

  @override
  Future<int> requestMtu(String address, int mtu) =>
      _ble.requestMtu(deviceId: address, mtu: mtu);

  @override
  Future<BondState> bondState(String address) => _native.bondState(address);

  @override
  Stream<BondState> watchBond(String address) => _native
      .bondEvents()
      .where((e) =>
          e.address.toUpperCase() == address.toUpperCase() &&
          e.state != BondState.unknown)
      .map((e) => e.state);

  @override
  Future<bool> createBond(String address) => _native.createBond(address);
}
