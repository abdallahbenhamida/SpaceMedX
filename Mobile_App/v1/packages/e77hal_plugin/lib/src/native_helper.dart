import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'ble_transport.dart';

/// Dart side of the small Android helper (android/.../E77halPlugin.java):
/// runtime permissions, enabling Bluetooth, location settings and OS bonding.
/// On other platforms every call is a harmless no-op.
class E77halNative {
  const E77halNative();

  static const MethodChannel _channel = MethodChannel('e77hal_plugin');
  static const EventChannel _bondEvents =
      EventChannel('e77hal_plugin/bond_events');

  static bool get _android => Platform.isAndroid;

  Future<bool> hasPermissions() async {
    if (!_android) return true;
    return await _channel.invokeMethod<bool>('hasPermissions') ?? false;
  }

  Future<bool> requestPermissions() async {
    if (!_android) return true;
    return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
  }

  Future<bool> isBluetoothEnabled() async {
    if (!_android) return true;
    return await _channel.invokeMethod<bool>('isBluetoothEnabled') ?? false;
  }

  /// Shows the system "turn on Bluetooth" dialog; true when it was enabled.
  Future<bool> requestEnableBluetooth() async {
    if (!_android) return true;
    return await _channel.invokeMethod<bool>('requestEnableBluetooth') ??
        false;
  }

  Future<bool> isLocationEnabled() async {
    if (!_android) return true;
    return await _channel.invokeMethod<bool>('isLocationEnabled') ?? true;
  }

  /// True when scanning needs system location services (Android 11 and
  /// below).
  Future<bool> needsLocationServices() async {
    if (!_android) return false;
    return await _channel.invokeMethod<bool>('needsLocationServices') ?? false;
  }

  Future<void> openLocationSettings() async {
    if (!_android) return;
    await _channel.invokeMethod<void>('openLocationSettings');
  }

  Future<BondState> bondState(String address) async {
    if (!_android) return BondState.unknown;
    final v = await _channel.invokeMethod<int>('bondState', address);
    return _state(v);
  }

  /// `BluetoothDevice.createBond()`; false when the OS refused to start.
  Future<bool> createBond(String address) async {
    if (!_android) return true;
    return await _channel.invokeMethod<bool>('createBond', address) ?? false;
  }

  /// Bond state changes of every device ({address, state, previousState}).
  Stream<({String address, BondState state})> bondEvents() {
    if (!_android) return const Stream.empty();
    return _bondEvents.receiveBroadcastStream().map((e) {
      final m = Map<Object?, Object?>.from(e as Map);
      return (address: '${m['address']}', state: _state(m['state'] as int?));
    });
  }

  static BondState _state(int? v) {
    switch (v) {
      case 10:
        return BondState.none;
      case 11:
        return BondState.bonding;
      case 12:
        return BondState.bonded;
    }
    return BondState.unknown;
  }
}
