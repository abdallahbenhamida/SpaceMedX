# SpaceMedX HUB v2

Version 2.0.0. It is v1 without any real sensor: **no Bluetooth plugin, no Bluetooth permissions, no Galaxy Watch link, no ECG recorder.** The only data source is the **demo sensor** (simulated heart rate and skin temperature). Everything else is as in v1: the one-button Home screen, the Data tab with range colours, the first setup in steps, the optional server, 11 languages, the ISS strip with NASA recordings, and the small heart rate / temperature change monitor.

## What was removed compared with v1
- `packages/e77hal_plugin/` (the Bluetooth device layer) and the `flutter_reactive_ble` dependency it brought.
- `BleSource` and `WatchSource` (`lib/core/sources.dart`), `lib/watch/`, the watch screen, the sensor chooser with its PIN pop-up, the live ECG chart and card, the ECG model (`lib/ml/ecg_anomaly_model.dart`).
- The settings `sensor`, `savvyPin`, `ecgChannel` and `useWatch`.
- The setup steps Sensor and Galaxy Watch (the first setup is now 3 steps).
- The Bluetooth permissions and the `connectedDevice` foreground service type in `AndroidManifest.xml`.
- The record builders for blood pressure, glucose and ECG (`lib/core/device_records.dart` keeps only the batch uploader).

The translation lists in `lib/l10n/` still hold the old sensor texts. They are unused and harmless.

## Add a real sensor later
Write a class that extends `DataSource` (see `DemoSource` in `lib/core/sources.dart`), call `Recorder.instance.record('hr', value)` for each reading, and return it from `MonitorSession.defaultSources`.

## Build and test
```bash
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm64
```
