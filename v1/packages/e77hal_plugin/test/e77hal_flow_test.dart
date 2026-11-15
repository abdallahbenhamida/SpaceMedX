import 'dart:async';

import 'package:e77hal_plugin/e77hal_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable Bluetooth transport for testing the state machine.
class FakeTransport implements BleTransport {
  String? prepareProblem;
  BondState bond = BondState.bonded;
  bool createBondResult = true;

  final scanController = StreamController<BleScanResult>.broadcast();
  StreamController<BleLinkEvent>? link;
  final Map<String, StreamController<List<int>>> notifications = {};
  final Map<String, List<int>> readValues = {};
  final List<String> calls = [];
  List<String>? lastScanFilter;
  bool linkCancelled = false;
  final bondController = StreamController<BondState>.broadcast();

  @override
  Future<int> requestMtu(String address, int mtu) async => mtu;

  @override
  Future<String?> prepare() async => prepareProblem;

  @override
  Stream<BleScanResult> scan({List<String> withServices = const []}) {
    lastScanFilter = withServices;
    calls.add('scan');
    return scanController.stream;
  }

  @override
  Stream<BleLinkEvent> connect(String address, {bool autoConnect = false}) {
    calls.add('connect:$address:auto=$autoConnect');
    linkCancelled = false;
    link = StreamController<BleLinkEvent>(onCancel: () => linkCancelled = true);
    return link!.stream;
  }

  @override
  Future<List<String>> discoverServices(String address) async {
    calls.add('discover');
    return ['1800', '180D', '180F', '1810', '1808'];
  }

  @override
  Future<List<int>> read(String address, String service, String characteristic) async {
    calls.add('read:$service/$characteristic');
    return readValues['$service/$characteristic'] ?? [0];
  }

  @override
  Future<void> write(String address, String service, String characteristic,
      List<int> value) async {
    calls.add('write:$service/$characteristic:${value.join(',')}');
  }

  @override
  Future<void> writeNoResponse(String address, String service, String characteristic,
          List<int> value) =>
      write(address, service, characteristic, value);

  @override
  Stream<List<int>> subscribe(String address, String service, String characteristic) {
    calls.add('subscribe:$service/$characteristic');
    return notifications
        .putIfAbsent('$service/$characteristic', () => StreamController<List<int>>.broadcast())
        .stream;
  }

  @override
  Future<BondState> bondState(String address) async => bond;

  @override
  Stream<BondState> watchBond(String address) => bondController.stream;

  @override
  Future<bool> createBond(String address) async {
    calls.add('createBond');
    return createBondResult;
  }

  void push(String key, List<int> value) => notifications[key]!.add(value);
}

List<int> beurerPacket({int pulse = 72}) => [
      0x1E, 120, 0, 80, 0, 93, 0, 0xE9, 0x07, 11, 4, 9, 5, 3, 0, pulse, 1,
    ];

void main() {
  late FakeTransport t;
  late E77hal hal;
  late List<Json> data;
  late List<Json> events;
  late List<String> errors;

  setUp(() {
    t = FakeTransport();
    hal = E77hal(transport: t);
    data = [];
    events = [];
    errors = [];
    hal.onReportData = data.add;
    hal.onReportEvent = events.add;
    hal.onError = errors.add;
  });

  tearDown(() => hal.dispose());

  test('Beurer BM85 (startx): collects, reports on readLast, remote disconnect', () async {
    await hal.startMeasurementx({'deviceID': 'EID_102', 'pinNumber': '0000'});
    expect(t.lastScanFilter, isEmpty);
    // an unrelated device is ignored
    t.scanController.add(const BleScanResult(name: 'Some TV', address: 'AA', rssi: -50));
    await pumpEventQueue();
    expect(t.calls.where((c) => c.startsWith('connect')), isEmpty);

    t.scanController.add(const BleScanResult(name: 'Beurer BM85', address: 'D0:5F', rssi: -60));
    await pumpEventQueue();
    // Beurer: no bonding, plain connect (no autoConnect)
    expect(t.calls, contains('connect:D0:5F:auto=false'));
    expect(t.calls, isNot(contains('createBond')));

    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();
    expect(events.single['key'], 'EV_1003');
    expect(events.single['message'], 'Beurer BM85 is connected successfully.');
    expect(t.calls, contains('discover'));
    expect(t.calls, contains('subscribe:1810/2A35'));
    expect(hal.checkDeviceStatus('EID_102')['status'], E77halStatus.connected);

    t.push('1810/2A35', beurerPacket());
    await pumpEventQueue();
    expect(data, isEmpty); // startx: collected only

    hal.readLastMeasurements({'deviceID': 'EID_102', 'amount': 1});
    expect(data, hasLength(1));
    expect(data.single['bPMCVSystolic'], 120);
    expect(data.single['MeasurementDateTime'], '2025/11/4 9:5:3');

    t.link!.add(const BleLinkEvent(BleLinkState.disconnected));
    await pumpEventQueue();
    expect(events.last['key'], 'EV_1005');
    expect(events.last['message'], 'Beurer BM85 is disconnected.');
    expect(events.last['deviceID'], 'EID_102');

    await hal.stopMeasurement({'deviceID': 'EID_102'});
    expect(hal.isRunning, isFalse);
    expect(hal.checkDeviceStatus('EID_102')['status'], E77halStatus.nullState);
  });

  test('Beurer BM85 (start): every measurement is reported immediately', () async {
    await hal.startMeasurement({'deviceID': 'EID_102', 'pinNumber': '0000'});
    t.scanController.add(const BleScanResult(name: 'Beurer BM85', address: 'X', rssi: -60));
    await pumpEventQueue();
    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();
    t.push('1810/2A35', beurerPacket(pulse: 70));
    t.push('1810/2A35', beurerPacket(pulse: 71));
    await pumpEventQueue();
    expect(data.map((r) => r['PulseRate']), [70, 71]);
  });

  test('Generic blood pressure monitor: found by the 1810 service, any name', () async {
    await hal.startMeasurement({'deviceID': 'EID_108', 'pinNumber': ''});
    await pumpEventQueue();
    expect(t.lastScanFilter, ['1810']);
    t.scanController.add(const BleScanResult(name: 'BP-Monitor', address: 'Z', rssi: -55));
    await pumpEventQueue();
    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();
    expect(t.calls, contains('subscribe:1810/2A35'));
    t.push('1810/2A35', beurerPacket(pulse: 66));
    await pumpEventQueue();
    expect(data.single['PulseRate'], 66);
  });

  test('Savvy ECG: autoConnect, PIN write, battery + state read, ECG stream', () async {
    t.readValues['180F/2A19'] = [87];
    await hal.startMeasurement({'deviceID': 'EID_103', 'pinNumber': '9545'});
    t.scanController.add(const BleScanResult(name: 'Savvy ECG 123', address: 'S1', rssi: -40));
    await pumpEventQueue();
    expect(t.calls, contains('connect:S1:auto=true'));
    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();

    final i = (String c) => t.calls.indexOf(c);
    expect(i('write:180D/2A39:7,4,57,53,52,53'), greaterThan(i('discover')));
    expect(i('read:180F/2A19'), greaterThan(i('write:180D/2A39:7,4,57,53,52,53')));
    expect(i('subscribe:180D/2A37'), greaterThan(i('read:180D/2A38')));

    // the battery record is reported twice (as in the original)
    expect(data.where((r) => r.containsKey('BatteryLevel')), hasLength(2));
    expect(data.first['BatteryLevel'], 87);

    final samples = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];
    final packet = List<int>.filled(19, 0);
    for (var s = 0; s < samples.length; s++) {
      for (var bit = 0; bit < 10; bit++) {
        if ((samples[s] >> bit) & 1 == 1) {
          final pos = s * 10 + bit;
          packet[pos >> 3] |= 1 << (pos & 7);
        }
      }
    }
    t.push('180D/2A37', packet);
    await pumpEventQueue();
    expect(data.last['ECGdata'], samples.join(','));
    expect(data.last['DeviceID'], 'EID_103');
  });

  test('Savvy ECG: reconnects with autoConnect after the device disconnects', () async {
    await hal.startMeasurement({'deviceID': 'EID_103', 'pinNumber': '1234'});
    t.scanController.add(const BleScanResult(name: 'Savvy', address: 'S1', rssi: -40));
    await pumpEventQueue();
    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();
    t.link!.add(const BleLinkEvent(BleLinkState.disconnected));
    await pumpEventQueue();
    expect(events.last['key'], 'EV_1005');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(t.calls.where((c) => c == 'connect:S1:auto=true'), hasLength(2));
  });

  test('Dcont Nemere: pairs first, then connects and reports glucose', () async {
    t.bond = BondState.none;
    await hal.startMeasurement({'deviceID': 'EID_101', 'pinNumber': '0000'});
    t.scanController.add(const BleScanResult(name: 'Dcont66', address: 'N1', rssi: -55));
    await pumpEventQueue();
    expect(t.calls, contains('createBond'));
    expect(t.calls.where((c) => c.startsWith('connect')), isEmpty);
    t.bondController.add(BondState.bonding);
    await pumpEventQueue();
    expect(t.calls.where((c) => c.startsWith('connect')), isEmpty);
    t.bondController.add(BondState.bonded);
    await pumpEventQueue();
    expect(t.calls, contains('connect:N1:auto=false'));
    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();
    expect(t.calls, contains('subscribe:1808/2A18'));
    t.push('1808/2A18', [0, 5, 0, 0xE9, 0x07, 11, 4, 9, 5, 0, 108, 0, 0, 0]);
    await pumpEventQueue();
    expect(data.single['glValue'], '6.0');
    expect(data.single['DeviceID'], 'EID_101');
  });

  test('Dcont Nemere: already bonded skips pairing', () async {
    await hal.startMeasurement({'deviceID': 'EID_101', 'pinNumber': '0000'});
    t.scanController.add(const BleScanResult(name: 'Dcont66', address: 'N1', rssi: -55));
    await pumpEventQueue();
    expect(t.calls, isNot(contains('createBond')));
    expect(t.calls, contains('connect:N1:auto=false'));
  });

  test('Dcont Nemere: failed pairing aborts with a message', () async {
    t.bond = BondState.none;
    await hal.startMeasurement({'deviceID': 'EID_101', 'pinNumber': '0000'});
    t.scanController.add(const BleScanResult(name: 'Dcont66', address: 'N1', rssi: -55));
    await pumpEventQueue();
    t.bondController.add(BondState.none);
    await pumpEventQueue();
    expect(errors.single, contains('Pairing'));
    expect(hal.isRunning, isFalse);
  });

  test('Polar H7: scans by heart rate service and reports pulse', () async {
    await hal.startMeasurement({'deviceID': 'EID_107'});
    expect(t.lastScanFilter, ['180D']);
    t.scanController.add(const BleScanResult(name: '', address: 'P1', rssi: -45));
    await pumpEventQueue();
    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();
    t.push('180D/2A37', [0x16, 66]);
    await pumpEventQueue();
    expect(data.single['DeviceID'], 'EID_107');
    expect(data.single['PulseRate'], 66);
  });

  test('Bluetooth problems end the measurement with a message', () async {
    t.prepareProblem = 'Bluetooth is turned off.';
    await hal.startMeasurement({'deviceID': 'EID_102', 'pinNumber': ''});
    expect(errors, ['Bluetooth is turned off.']);
    expect(hal.isRunning, isFalse);
  });

  test('connection failure aborts with a message', () async {
    await hal.startMeasurement({'deviceID': 'EID_102', 'pinNumber': ''});
    t.scanController.add(const BleScanResult(name: 'Beurer BM85', address: 'B', rssi: -50));
    await pumpEventQueue();
    t.link!.add(const BleLinkEvent(BleLinkState.disconnected, error: 'status 133'));
    await pumpEventQueue();
    expect(errors.single, contains('Could not connect'));
  });

  test('stop does not emit a disconnect event and cancels the link', () async {
    await hal.startMeasurement({'deviceID': 'EID_102', 'pinNumber': ''});
    t.scanController.add(const BleScanResult(name: 'Beurer BM85', address: 'B', rssi: -50));
    await pumpEventQueue();
    t.link!.add(const BleLinkEvent(BleLinkState.connected));
    await pumpEventQueue();
    events.clear();
    await hal.stopMeasurement({'deviceID': 'EID_102'});
    await pumpEventQueue();
    expect(events, isEmpty);
    expect(t.linkCancelled, isTrue);
  });

  test('HAL parameters', () {
    expect(hal.getHalParameter({'pName': 'halName'}), {'response': '77e_HAL'});
    expect(hal.getHalParameter({'pName': 'x'}), {'response': 'NULL'});
    expect(hal.checkHalStatus()['halSWVersion'], '1.0.5bx');
    expect(hal.setDeviceParameter({'deviceID': 'EID_103', 'rawECG': true}), {'status': 'OK'});
    expect(hal.rawECG, isTrue);
  });
}
