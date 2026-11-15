# e77hal-plugin

Flutter port of **cordova-plugin-e77hal** v4.5.3 (E77 HAL): Bluetooth Low Energy
access to the measurement devices.

| Device id | Device | What the plugin does |
|---|---|---|
| `EID_103` | Savvy ECG | scan name `Savvy`, `autoConnect`, writes the PIN command `[7, len, ...ascii(pin)]` to `180D/2A39`, reads battery `180F/2A19` and state `180D/2A38`, subscribes `180D/2A37` (14 ten-bit samples per 19-byte packet) |
| `EID_102` | Beurer BM85 | scan name `Beurer BM85`, plain connect, subscribes (indications) `1810/2A35`; the device sends its stored history and disconnects |
| `EID_101` | Dcont Nemere | scan name `Dcont66`, **OS pairing first** (`createBond`), connect, subscribes `1808/2A18` |
| `EID_107` | Polar H7 | scans for the heart rate service `180D`, subscribes `180D/2A37` |

## API (same functions as `window.e77hal` of the Cordova plugin)

```dart
final hal = E77hal();
hal.onReportData  = (record) { ... };   // e77hal_caller.reportData
hal.onReportEvent = (event)  { ... };   // {key: EV_1003|EV_1005, message, deviceID}
hal.onStatus      = (text)   { ... };   // progress / diagnostics (new)
hal.onError       = (text)   { ... };   // measurement ended by a problem (new)

await hal.startMeasurement({'deviceID': 'EID_102', 'pinNumber': '0000'});
await hal.startMeasurementx({...});     // collect only; report with readLastMeasurements
hal.readLastMeasurements({'deviceID': 'EID_102', 'amount': 1});
await hal.stopMeasurement({'deviceID': 'EID_102'});
// readAllMeasurements, deleteLastMeasurements, deleteAllMeasurements,
// checkDeviceStatus, checkHalStatus, set/getDeviceParameter,
// getNumberOfMeasurements, set/getHalParameter
```

Records have the same keys as before (`DAQTimestamp`, `RecordNumber`, `DeviceID`,
`DeviceMeasurementNum`, `ECGdata` / `bPMCVSystolic` … / `glValue` …).

## Structure

* `lib/src/e77hal.dart` – port of the `e77hal` object (state machine, ring buffers, API)
* `lib/src/parsers.dart` – characteristic parsers, ported line by line (quirks included)
* `lib/src/ble_transport.dart` – the Bluetooth operations the state machine needs
* `lib/src/reactive_ble_transport.dart` – transport on `flutter_reactive_ble` (BSD-3)
* `lib/src/native_helper.dart` + `android/` – small Android helper (Java): runtime
  permissions, "turn Bluetooth on", **OS bonding** (`createBond`) and bond events
* `test/` – parser vectors and the complete device flows against a fake transport
  (`flutter test`)

## Why not flutter_blue_plus

flutter_blue_plus 2.x requires a paid commercial licence for for-profit use and
sends a licence ping at build time; `flutter_reactive_ble` is BSD-3-Clause.
