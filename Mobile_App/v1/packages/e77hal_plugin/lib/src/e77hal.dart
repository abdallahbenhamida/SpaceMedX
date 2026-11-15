import 'dart:async';

import 'ble_transport.dart';
import 'parsers.dart';
import 'reactive_ble_transport.dart';
import 'ring_buffer.dart';

typedef ReportDataCallback = void Function(Json record);
typedef ReportEventCallback = void Function(Json event);

/// Device status values (`STATUS_*` in e77hal.js).
class E77halStatus {
  static const int nullState = 0;
  static const int inited = 1;
  static const int scanned = 2;
  static const int connected = 3;
  static const int discovered = 4;
  static const int error = 6;
  static const int ok = 7;
}

class _Device {
  _Device(this.id, this.advName);

  final String id;

  /// Text the advertised name has to contain (`*SensorAdvName`).
  final String advName;

  String pin = '';
  String mac = '';
  String name = '';
  int status = E77halStatus.nullState;
  int recordNumber = 1;
  bool linkUp = false;
  final DataRingBuffer ring = DataRingBuffer(E77hal.ringBufferSize);
}

class _Item {
  _Item(this.record);
  final Json record;
  bool processed = false;
}

/// Flutter port of `cordova-plugin-e77hal` (v4.5.3, `www/e77hal.js`).
///
/// It scans for, connects to and reads measurements from the supported
/// Bluetooth LE devices and hands every measurement to [onReportData], and
/// connection events to [onReportEvent] – exactly the two callbacks the old
/// app received through `e77hal_caller.reportData / reportEvent`.
///
/// Supported devices (same ids as the original):
///  * `EID_103` Savvy ECG (PIN authenticated, ECG stream)
///  * `EID_102` Beurer BM85 blood pressure monitor (indications)
///  * `EID_101` Dcont Nemere glucose meter (bonded, notifications)
///  * `EID_107` Polar H7 heart rate belt (standard heart rate service)
class E77hal {
  E77hal({BleTransport? transport})
      : transport = transport ?? ReactiveBleTransport() {
    _devices = {
      pcardSavvyEcg: _Device(pcardSavvyEcg, 'Savvy'),
      beurerBm85Bp: _Device(beurerBm85Bp, 'Beurer BM85'),
      dcontNemereGl: _Device(dcontNemereGl, 'Dcont66'),
      polarH7: _Device(polarH7, 'Polar'),
      genericBp: _Device(genericBp, 'Blood pressure monitor'),
    };
  }

  final BleTransport transport;

  /// A measurement was received (`e77hal_caller.reportData`).
  ReportDataCallback? onReportData;

  /// A connection event: `{key: EV_1003|EV_1005, message, deviceID}`
  /// (`e77hal_caller.reportEvent`).
  ReportEventCallback? onReportEvent;

  /// Human readable progress / diagnostics (new, for the debug panel).
  void Function(String message)? onStatus;

  /// A problem that ends the current measurement (Bluetooth off, permission
  /// denied, pairing / connection / authentication failed). New: the old
  /// plugin failed silently.
  void Function(String message)? onError;

  void Function(String message)? onLog;

  // --- constants of the original -------------------------------------------
  static const int ringBufferSize = 500;
  static const String halName = '77e_HAL';
  static const String halSWVersion = '1.0.5bx';
  static const String halReleaseDate = '2019.09.19';
  static const String halStatus = 'STATUS_OK';

  // GATT services / characteristics (short UUIDs).
  static const String battService = '180F';
  static const String battChar = '2A19';
  static const String hrService = '180D';
  static const String hrControlPoint = '2A39';
  static const String hrMeasurement = '2A37';
  static const String statChar = '2A38';
  static const String bpService = '1810';
  static const String bpMeasurement = '2A35';
  static const String glService = '1808';
  static const String glMeasurement = '2A18';

  late final Map<String, _Device> _devices;

  /// `rawECG`: report the raw Savvy packet instead of the sample string.
  bool rawECG = false;

  /// `report_var`: false for `startMeasurementx` (collect only, report with
  /// readLastMeasurements).
  bool _reportVar = true;

  /// `devnum`
  String devnum = '';

  /// `mea_record_number`
  int meaRecordNumber = 1;

  // --- runtime state ---------------------------------------------------------
  int _session = 0;
  bool _active = false;
  bool _targetFound = false;
  bool _connectedOnce = false;
  StreamSubscription<BleScanResult>? _scanSub;
  StreamSubscription<BleLinkEvent>? _linkSub;
  StreamSubscription<BondState>? _bondSub;
  final List<StreamSubscription<List<int>>> _dataSubs = [];
  Timer? _reconnectTimer;

  _Device? get _cur => _devices[devnum];

  /// Beurer BM85 or any standard blood pressure monitor.
  static bool _isBp(String id) => id == beurerBm85Bp || id == genericBp;

  /// True while a measurement is scanning / connected.
  bool get isRunning => _active;

  void _log(String m) => onLog?.call(m);
  void _status(String m) {
    _log(m);
    onStatus?.call(m);
  }

  void _emitData(Json record) => onReportData?.call(record);

  void _emitEvent(String key, String message) =>
      onReportEvent?.call({'key': key, 'message': message, 'deviceID': devnum});

  // ===========================================================================
  // External API (e77hal.js "external API")
  // ===========================================================================

  /// `startMeasurement`: collect and report every measurement.
  Future<Json> startMeasurement(Json params) {
    _reportVar = true;
    return _start(params);
  }

  /// `startMeasurementx`: collect but do not report; use
  /// [readLastMeasurements] to report (Beurer BM85 history download).
  Future<Json> startMeasurementx(Json params) {
    _reportVar = false;
    return _start(params);
  }

  /// `stopMeasurement`: disconnects the current device (like the original it
  /// acts on the current `devnum`, not on `params.deviceID`).
  Future<void> stopMeasurement(Json params) => _disconnecty();

  /// `readLastMeasurements`: reports the last [amount] stored measurements
  /// through [onReportData].
  Json readLastMeasurements(Json params) {
    final id = '${params['deviceID']}';
    final feedback = <String, Object?>{'deviceID': id, 'status': 'OK'};
    var amount = _int(params['amount']);
    if (id == pcardSavvyEcg) {
      final d = _devices[id]!;
      if (d.status != E77halStatus.nullState) {
        stopMeasurement({'deviceID': id}); // the savvy has to stop reading
      }
      int? pointerX;
      while (amount > 0) {
        pointerX = d.ring.getptr();
        final entry = d.ring.prev();
        if (entry == null) break; // the original throws a TypeError here
        _emitData(entry.record);
        amount--;
      }
      if (pointerX != null) d.ring.setptr(pointerX);
    } else if (_isBp(id)) {
      final d = _devices[id]!;
      final pointerX = d.ring.getptr();
      final measurements = _readLastBeurerMeasurements(amount);
      for (final m in measurements) {
        _log('last value lastDate: ${m['MeasurementDateTime']}');
        _emitData(m);
      }
      d.ring.setptr(pointerX);
    } else if (id == dcontNemereGl) {
      final d = _devices[id]!;
      final pointerX = d.ring.getptr();
      while (amount > 0) {
        final entry = d.ring.prev();
        if (entry == null) break;
        _emitData(entry.record);
        amount--;
      }
      d.ring.setptr(pointerX);
    }
    return feedback;
  }

  /// `readAllMeasurements`
  Json readAllMeasurements(Json params) {
    final feedback = <String, Object?>{
      'deviceID': params['deviceID'],
      'status': 'OK',
    };
    readLastMeasurements(
        {'deviceID': params['deviceID'], 'amount': ringBufferSize});
    return feedback;
  }

  /// `deleteLastMeasurements`
  Json deleteLastMeasurements(Json params) {
    final id = '${params['deviceID']}';
    final feedback = <String, Object?>{'deviceID': id, 'status': 'OK'};
    final d = _devices[id];
    if (d == null) return feedback;
    if (id == pcardSavvyEcg && d.status != E77halStatus.nullState) {
      stopMeasurement({'deviceID': id});
    }
    _clearRing(d, _int(params['amount']));
    return feedback;
  }

  /// `deleteAllMeasurements`
  Json deleteAllMeasurements(Json params) =>
      deleteLastMeasurements({
        'deviceID': params['deviceID'],
        'amount': ringBufferSize,
      });

  /// `checkDeviceStatus`
  Json checkDeviceStatus(String deviceID) {
    final d = _devices[deviceID];
    if (d == null) return {};
    return {'status': d.status, 'name': devnum, 'address': d.mac};
  }

  /// `checkHalStatus`
  Json checkHalStatus() => {
        'halName': halName,
        'halSWVersion': halSWVersion,
        'halReleaseDate': halReleaseDate,
        'halStatus': halStatus,
      };

  /// `setDeviceParameter`
  Json setDeviceParameter(Json params) {
    final id = '${params['deviceID']}';
    if (id == pcardSavvyEcg) {
      rawECG = params['rawECG'] == true;
      return {'status': 'OK'};
    }
    final d = _devices[id];
    if (d != null) {
      d.mac = '${params['address'] ?? ''}';
      return {'status': 'OK'};
    }
    return {};
  }

  /// `getDeviceParameter`
  Json getDeviceParameter(Json params) {
    final id = '${params['deviceID']}';
    final d = _devices[id];
    if (d == null) return {};
    if (id == pcardSavvyEcg) {
      return {
        'deviceID': id,
        'rawECG': rawECG,
        'MACAddress': d.mac,
        'status': d.status,
      };
    }
    return {'deviceID': id, 'MACAddress': d.mac, 'status': d.status};
  }

  /// `getNumberOfMeasurements`
  Json getNumberOfMeasurements(Json params) {
    final id = '${params['deviceID']}';
    final d = _devices[id];
    if (id == pcardSavvyEcg && d != null) {
      return {
        'deviceID': id,
        'savvyMeasurementRecordNumber': d.recordNumber,
        'measurementRecordNumber': meaRecordNumber,
      };
    } else if (_isBp(id) && d != null) {
      return {
        'deviceID': id,
        'beurerMeasurementRecordNumber': d.recordNumber,
        'measurementRecordNumber': meaRecordNumber,
      };
    } else if (id == dcontNemereGl && d != null) {
      return {
        'deviceID': id,
        'nemereMeasurementRecordNumber': d.recordNumber,
        'measurementRecordNumber': meaRecordNumber,
      };
    }
    return {'halName': halName, 'measurementRecordNumber': meaRecordNumber};
  }

  /// `setHalParameter` (a dummy in the original)
  Json setHalParameter(Json params) => {'halName': halName, 'status': 'OK'};

  /// `getHalParameter`
  Json getHalParameter(Json params) {
    switch (params['pName']) {
      case 'halName':
        return {'response': halName};
      case 'halStatus':
        return {'response': halStatus};
      case 'halSWVersion':
        return {'response': halSWVersion};
      case 'halReleaseDate':
        return {'response': halReleaseDate};
    }
    return {'response': 'NULL'};
  }

  /// Stops everything and releases the Bluetooth resources.
  Future<void> dispose() => _teardown();

  // ===========================================================================
  // Internals
  // ===========================================================================

  static int _int(Object? v) =>
      v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  /// `sensorSetup`
  void _sensorSetup(Json params) {
    final d = _devices[devnum]!;
    d.pin = '${params['pinNumber'] ?? ''}';
    d.mac = '';
    d.name = '';
    d.recordNumber = 1;
    d.status = E77halStatus.inited;
    d.linkUp = false;
    _clearRing(d, ringBufferSize); // initBuffer
    if (devnum == pcardSavvyEcg) {
      // In the original, the buffer reset called stopMeasurement() for the
      // Savvy (status != NULL), which left the status at "scanned".
      d.status = E77halStatus.scanned;
    }
  }

  /// The loop of `deleteLastMeasurements`.
  void _clearRing(_Device d, int amount) {
    var pointer = 0;
    while (amount > 0) {
      pointer = d.ring.getptr();
      d.ring.push(RingEntry(<String, Object?>{}, false));
      amount--;
      pointer = pointer == 0 ? ringBufferSize - 1 : pointer - 1;
      d.ring.setptr(pointer);
    }
  }

  Future<Json> _start(Json params) async {
    final id = '${params['deviceID']}';
    if (!_devices.containsKey(id)) {
      _status('Unknown device $id');
      return params;
    }
    if (_active) {
      if (devnum == id) {
        _status('${_devices[id]!.advName} is already running');
        return params;
      }
      await _teardown();
    }
    final session = ++_session;
    _active = true;
    _targetFound = false;
    _connectedOnce = false;
    devnum = id;
    _sensorSetup(params);

    _status('Checking Bluetooth …');
    String? problem;
    try {
      problem = await transport.prepare();
    } catch (e) {
      problem = 'Bluetooth is not available: $e';
    }
    if (session != _session) return params;
    if (problem != null) {
      await _abort(session, problem);
      return params;
    }
    _beginScan(session);
    return params;
  }

  /// Ends the current measurement because of a problem and tells the app.
  Future<void> _abort(int session, String message) async {
    if (session != _session) return;
    _status(message);
    await _teardown();
    onError?.call(message);
  }

  // --- scanning ---------------------------------------------------------------

  void _beginScan(int session) {
    final d = _cur!;
    _status('Scanning for ${d.advName} …');
    _scanSub?.cancel();
    _scanSub = transport
        .scan(
            withServices: devnum == polarH7
                ? const [hrService]
                : (devnum == genericBp ? const [bpService] : const []))
        .listen(
          (r) => _onScanResult(session, r),
          onError: (Object e) =>
              _abort(session, 'Bluetooth scan failed: $e'),
        );
  }

  /// `successScanCall_back`
  void _onScanResult(int session, BleScanResult r) {
    if (session != _session || _targetFound) return;
    final d = _cur!;
    var found = false;
    if (devnum == polarH7 || devnum == genericBp) {
      // any device offering the service we scan for (HR or blood pressure)
      found = true;
    } else if (r.name.isNotEmpty && r.name.contains(d.advName)) {
      found = true;
    }
    if (!found) return;
    _targetFound = true;
    d.mac = r.address;
    d.name = r.name.isEmpty ? d.advName : r.name;
    _status('Found ${d.name} (${r.address}), signal ${r.rssi} dBm');
    _scanSub?.cancel();
    _scanSub = null;
    switch (devnum) {
      case pcardSavvyEcg:
        _connect(session, autoConnect: true);
      case dcontNemereGl:
        _bondy(session);
      default: // Beurer BM85 (bonding is commented out in the original), H7
        _connect(session);
    }
  }

  // --- bonding (Dcont Nemere) -------------------------------------------------

  /// `bondy` / `bondSuccess` / `bondError`
  Future<void> _bondy(int session) async {
    final d = _cur!;
    var state = BondState.unknown;
    try {
      state = await transport.bondState(d.mac);
    } catch (e) {
      _log('bondState failed: $e');
    }
    if (session != _session) return;
    // "Device already bonded" -> connect (bondError); platforms without a
    // bonding API (iOS pairs on demand) connect directly as well.
    if (state == BondState.bonded || state == BondState.unknown) {
      _connect(session);
      return;
    }
    final result = Completer<BondState>();
    await _bondSub?.cancel();
    _bondSub = transport.watchBond(d.mac).listen((s) {
      if ((s == BondState.bonded || s == BondState.none) &&
          !result.isCompleted) {
        result.complete(s);
      }
    });
    if (state == BondState.none) {
      _status('Pairing with ${d.name} …');
      var started = false;
      try {
        started = await transport.createBond(d.mac);
      } catch (e) {
        _log('createBond failed: $e');
      }
      if (session != _session) return;
      if (!started) {
        await _abort(session, 'Pairing with ${d.name} could not be started.');
        return;
      }
    } else {
      _status('Waiting for the pairing with ${d.name} …');
    }
    final bond = await result.future
        .timeout(const Duration(minutes: 2), onTimeout: () => BondState.none);
    await _bondSub?.cancel();
    _bondSub = null;
    if (session != _session) return;
    if (bond == BondState.bonded) {
      _log('bonded successfully, so lets connect!');
      _connect(session);
    } else {
      await _abort(session,
          'Pairing with ${d.name} failed. Put the device in pairing mode and try again.');
    }
  }

  // --- connection -------------------------------------------------------------

  /// `connecty`
  void _connect(int session, {bool autoConnect = false}) {
    final d = _cur!;
    _status('Connecting to ${d.name} …');
    _connectedOnce = false;
    _linkSub?.cancel();
    _linkSub = transport.connect(d.mac, autoConnect: autoConnect).listen(
          (e) => _onLink(session, e),
          onError: (Object err) => _onConnectError(session, err.toString()),
        );
  }

  void _onLink(int session, BleLinkEvent e) {
    if (session != _session) return;
    final d = _cur!;
    if (e.state == BleLinkState.connected) {
      // connectSuccess: "connected"
      _connectedOnce = true;
      d.linkUp = true;
      _status('Connected to ${d.name}');
      _emitEvent('EV_1003', '${d.name} is connected successfully.');
      _discovery(session);
      return;
    }
    // disconnected
    if (!_connectedOnce) {
      _onConnectError(session, e.error ?? 'connection failed');
      return;
    }
    // connectSuccess: "disconnected" (the device ended the connection)
    d.linkUp = false;
    _connectedOnce = false;
    _cancelData();
    _status('${d.name} disconnected');
    _emitEvent('EV_1005', '${d.name} is disconnected.');
    if (devnum == pcardSavvyEcg) {
      // autoConnect: the OS reconnects when the Savvy is back in range.
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 1), () {
        if (session == _session && _active) {
          _connect(session, autoConnect: true);
        }
      });
    } else if (devnum == polarH7) {
      // onDisconnect -> onTimeout -> scan again
      _targetFound = false;
      _beginScan(session);
    }
  }

  /// `connectError`: the original disconnects; the app is told as well.
  void _onConnectError(int session, String error) {
    if (session != _session) return;
    final d = _cur!;
    _abort(session, 'Could not connect to ${d.name}: $error');
  }

  // --- discovery / authentication ---------------------------------------------

  /// `discovery`
  Future<void> _discovery(int session) async {
    final d = _cur!;
    try {
      final services = await transport.discoverServices(d.mac);
      if (session != _session) return;
      _log('services: ${services.join(', ')}');
    } catch (e) {
      if (session != _session) return;
      _log('discoveryError: $e');
      if (!d.linkUp) {
        await _disconnecty();
      } else {
        await _abort(session, 'Could not read the services of ${d.name}: $e');
      }
      return;
    }
    await _authy(session);
  }

  /// `authy`
  Future<void> _authy(int session) async {
    final d = _cur!;
    if (devnum == pcardSavvyEcg) {
      try {
        await transport.write(
            d.mac, hrService, hrControlPoint, savvyPinCommand(d.pin));
      } catch (e) {
        if (session != _session) return;
        await _abort(session,
            'Authentication with the Savvy ECG failed (check the PIN code): $e');
        return;
      }
      if (session != _session) return;
    }
    await _genericDataReading(session);
  }

  /// `genericDataReading`
  Future<void> _genericDataReading(int session) async {
    final d = _cur!;
    switch (devnum) {
      case pcardSavvyEcg:
        d.status = E77halStatus.connected;
        await _read(session, battService, battChar); // readBatty
        await _read(session, hrService, statChar); // readDeviceState
        _subscribe(session, hrService, hrMeasurement); // readECGy
      case beurerBm85Bp:
      case genericBp:
        d.status = E77halStatus.connected;
        _subscribe(session, bpService, bpMeasurement);
      case dcontNemereGl:
        d.status = E77halStatus.connected;
        _subscribe(session, glService, glMeasurement);
      case polarH7:
        d.status = E77halStatus.connected;
        _subscribe(session, hrService, hrMeasurement);
    }
    if (session == _session) _status('Waiting for measurements from ${d.name} …');
  }

  Future<void> _read(int session, String service, String characteristic) async {
    final d = _cur!;
    try {
      final v = await transport.read(d.mac, service, characteristic);
      if (session != _session) return;
      _readSuccess(service, characteristic, v);
    } catch (e) {
      _log('read error ($service/$characteristic): $e');
    }
  }

  void _subscribe(int session, String service, String characteristic) {
    final d = _cur!;
    final sub = transport.subscribe(d.mac, service, characteristic).listen(
      (v) {
        if (session != _session) return;
        _readSuccess(service, characteristic, v);
      },
      onError: (Object e) {
        _log('subscribe error ($service/$characteristic): $e');
        if (session == _session) {
          _status('Could not subscribe to ${d.name}: $e');
        }
      },
    );
    _dataSubs.add(sub);
    // the original also received a value-less "subscribed" result
    meaRecordNumber++;
  }

  void _cancelData() {
    for (final s in _dataSubs) {
      s.cancel();
    }
    _dataSubs.clear();
  }

  // --- data ----------------------------------------------------------------------

  /// `readSuccess`
  void _readSuccess(String service, String characteristic, List<int> value) {
    final d = _cur;
    if (d == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (devnum == pcardSavvyEcg) {
      if (service == battService && characteristic == battChar) {
        final battLevel = value.isEmpty ? 0 : byteToInt(value[0]);
        final record = <String, Object?>{
          'DAQTimestamp': now,
          'RecordNumber': meaRecordNumber,
          'DeviceID': pcardSavvyEcg,
          'DeviceMeasurementNum': d.recordNumber,
          'BatteryLevel': battLevel,
        };
        _emitData(record);
        d.ring.push(RingEntry(record, true));
        _emitData(record);
        d.recordNumber++;
      }
      if (service == hrService && characteristic == hrMeasurement) {
        if (value.isNotEmpty) _unpack(d, value, now);
      }
      if (service == hrService && characteristic == statChar) {
        final stats = SavvyStats(value);
        if (stats.stackOverflow) {
          _log('ALERT! stackOverflow!');
          // (the original's resetCommand() never reached the device)
        }
        if (stats.isOnCharger) {
          _log('ALERT! savvyCharging');
          _disconnecty();
        }
        if (stats.batteryLow) {
          _log('ALERT! lowBattery');
          _disconnecty();
        }
      }
    } else if (devnum == dcontNemereGl) {
      if (service == glService && characteristic == glMeasurement) {
        _processNemereData(d, value);
      }
    } else if (_isBp(devnum)) {
      if (service == bpService && characteristic == bpMeasurement) {
        _processBeurerData(d, value);
      }
    } else if (devnum == polarH7) {
      if (service == hrService && characteristic == hrMeasurement) {
        _processPolarData(d, value, now);
      }
    }
    meaRecordNumber++;
  }

  /// `unpack`
  void _unpack(_Device d, List<int> data, int timeStamp) {
    final record = <String, Object?>{
      'DAQTimestamp': timeStamp,
      'RecordNumber': meaRecordNumber,
      'DeviceID': pcardSavvyEcg,
      'DeviceMeasurementNum': d.recordNumber,
      'ECGdata': rawECG ? List<int>.from(data) : savvyEcgString(data),
    };
    _emitData(record);
    d.ring.push(RingEntry(record, true));
    d.recordNumber++;
  }

  /// `processBeurerData`
  void _processBeurerData(_Device d, List<int> data) {
    final record = parseBeurer(
      data,
      timeStamp: DateTime.now().millisecondsSinceEpoch,
      recordNumber: meaRecordNumber,
      deviceMeasurementNum: d.recordNumber,
    );
    if (record == null) return;
    _log('receivedData: $record');
    if (_reportVar) _emitData(record);
    d.ring.push(RingEntry(record, true));
    d.recordNumber++;
  }

  /// `processNemereData`
  void _processNemereData(_Device d, List<int> data) {
    final record = parseNemere(
      data,
      timeStamp: DateTime.now().millisecondsSinceEpoch,
      recordNumber: meaRecordNumber,
      deviceMeasurementNum: d.recordNumber,
    );
    if (record == null) return;
    d.ring.push(RingEntry(record, true));
    if (_reportVar) _emitData(record);
    d.recordNumber++;
  }

  /// `ble_central_caller.onReadBPData` (Polar H7): always reported.
  void _processPolarData(_Device d, List<int> data, int timeStamp) {
    final hr = parseHeartRate(data);
    if (hr == null) return;
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final dateTime = '${t.year}/${two(t.month)}/${two(t.day)} '
        '${t.hour}:${t.minute}:${t.second}';
    _emitData({
      'DAQTimestamp': timeStamp,
      'RecordNumber': meaRecordNumber,
      'DeviceID': polarH7,
      'DeviceMeasurementNum': d.recordNumber,
      'MeasurementDateTime': dateTime,
      'PulseRate': hr.bpm,
      'rr': hr.rr,
    });
    d.recordNumber++;
  }

  /// `readLastBeurerMeasurements`: the [amount] stored measurements closest
  /// to now (in the past), in ascending time order.
  List<Json> _readLastBeurerMeasurements(int amount) {
    final d = _devices[_isBp(devnum) ? devnum : beurerBm85Bp]!;
    final pointerX = d.ring.getptr();
    final items = <_Item?>[
      for (var i = 0; i < ringBufferSize; i++)
        d.ring.get(i) == null ? null : _Item(d.ring.get(i)!.record),
    ];
    final found = <Json>[];
    while (amount > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      int? smallest;
      int best = -1;
      for (var i = 0; i < ringBufferSize; i++) {
        final item = items[i];
        if (item == null || item.processed) continue;
        final t = parseSlashDate(item.record['MeasurementDateTime']);
        if (t == null) continue;
        final difference = now - t;
        if (difference >= 0 && (smallest == null || difference < smallest)) {
          smallest = difference;
          best = i;
        }
      }
      if (best == -1) break;
      found.add(items[best]!.record);
      items[best]!.processed = true;
      amount--;
    }
    found.sort((a, b) =>
        (parseSlashDate(a['MeasurementDateTime']) ?? 0) -
        (parseSlashDate(b['MeasurementDateTime']) ?? 0));
    d.ring.setptr(pointerX);
    return found;
  }

  // --- stopping -------------------------------------------------------------------

  /// `disconnecty` + `disconnectSuccess` + `close`: also ends scanning (the
  /// original left a running scan active).
  Future<void> _disconnecty() => _teardown();

  Future<void> _teardown() async {
    _session++; // pending async work and callbacks become stale
    _active = false;
    _targetFound = false;
    _connectedOnce = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final scan = _scanSub;
    final bond = _bondSub;
    final link = _linkSub;
    _scanSub = null;
    _bondSub = null;
    _linkSub = null;
    _cancelData();
    await scan?.cancel();
    await bond?.cancel();
    // cancelling the connection stream disconnects and closes the GATT
    await link?.cancel();
    final d = _cur;
    if (d != null) {
      d.status = E77halStatus.nullState;
      d.linkUp = false;
    }
  }
}
