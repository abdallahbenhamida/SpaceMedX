/// Bluetooth characteristic parsers, ported 1:1 from `www/e77hal.js`
/// (including its quirks, which determine what the server receives).
library;

typedef Json = Map<String, Object?>;

const String pcardSavvyEcg = 'EID_103';
const String beurerBm85Bp = 'EID_102';
const String dcontNemereGl = 'EID_101';
const String polarH7 = 'EID_107';

/// Any Bluetooth blood pressure monitor that uses the standard Blood Pressure
/// profile (service 1810, characteristic 2A35). Same flow as the Beurer BM85,
/// but found by its service instead of its name.
const String genericBp = 'EID_108';

/// `e77hal.byteToInt`
int byteToInt(int b) => b & 0xff;

/// `e77hal.getInt(data, offset, bits)`: little-endian bit-field reader used
/// for the Savvy ECG samples (10 bits each).
int getInt(List<int> data, int offset, int bits) {
  int at(int i) => i >= 0 && i < data.length ? data[i] & 255 : 0;
  var byteOffset = offset >> 3;
  var bitOffset = offset & 7;
  var countBits = 0;
  var ret = 0;
  while (countBits < bits) {
    var readyBits = 8 - bitOffset;
    if (bits - countBits >= readyBits) {
      ret += (at(byteOffset) >>> bitOffset) << countBits;
      countBits += readyBits;
      byteOffset++;
      bitOffset = 0;
    } else {
      readyBits = bits - countBits;
      ret += ((at(byteOffset) >>> bitOffset) & ((1 << readyBits) - 1)) <<
          countBits;
      countBits += readyBits;
      return ret;
    }
  }
  return ret;
}

/// `e77hal.getBit(data, pos)`.
///
/// The original indexes `data[pos / 8]` with a *fractional* index unless
/// `pos` is a multiple of 8; JavaScript then reads `undefined`, i.e. 0. So
/// only bits 0 of whole bytes can ever be true (e.g. positions 96 and 104).
bool getBit(List<int> data, int pos) {
  if (pos % 8 != 0) return false;
  final i = pos ~/ 8;
  if (i >= data.length) return false;
  return (data[i] & 1) == 1;
}

/// Savvy ECG packet -> the comma separated string of 14 ten-bit samples
/// (`unpack()`), or an empty string when the packet is not 19 bytes long.
String savvyEcgString(List<int> data) {
  if (data.length != 19) return '';
  final samples = <String>[];
  for (var i = 0; i < 14; i++) {
    samples.add(getInt(data, i * 10, 10).toString());
  }
  final s = samples.join(',');
  return s.length > 6999 ? '' : s;
}

/// Savvy device-state flags (`readSuccess`, statChar). See [getBit].
class SavvyStats {
  SavvyStats(List<int> v)
      : ecgSamplingEnabled = getBit(v, 96),
        accelerometerExists = getBit(v, 97),
        accelerometerEnabled = getBit(v, 98),
        thermometerExists = getBit(v, 99),
        thermometerEnabled = getBit(v, 100),
        ledExists = getBit(v, 101),
        isOnCharger = getBit(v, 102),
        watchdogState = getBit(v, 103),
        stackOverflow = getBit(v, 104),
        batteryLow = getBit(v, 105);

  final bool ecgSamplingEnabled;
  final bool accelerometerExists;
  final bool accelerometerEnabled;
  final bool thermometerExists;
  final bool thermometerEnabled;
  final bool ledExists;
  final bool isOnCharger;
  final bool watchdogState;
  final bool stackOverflow;
  final bool batteryLow;
}

/// PIN command written to the heart-rate control point to authenticate with
/// the Savvy ECG: `[7, pin.length, ...ascii(pin)]` (`formatpinCode`).
List<int> savvyPinCommand(String pin) =>
    [7, pin.length, ...pin.codeUnits.map((c) => c & 0xff)];

/// "The command to reset the Savvy after a stack overflow" (resetCommand).
const List<int> savvyResetCommand = [0, 0, 0, 0, 0];

String? _bit(String s, int i) => i >= 0 && i < s.length ? s[i] : null;

/// Beurer BM85 blood pressure measurement (characteristic 2A35).
///
/// The original reads the flags from `byte.toString(2)` *without* leading
/// zeros and indexes that string from its first character, which is not the
/// Bluetooth flag layout; the same is done here so the produced values (and
/// therefore the uploaded data) are identical.
Json? parseBeurer(
  List<int> b, {
  required int timeStamp,
  required int recordNumber,
  required int deviceMeasurementNum,
}) {
  if (b.length < 14) return null;
  int at(int i) => i >= 0 && i < b.length ? b[i] : 0;
  final firstBits = at(0).toRadixString(2);
  var meaUnit = ' ';
  if (_bit(firstBits, 0) == '0') {
    meaUnit = 'mmHg';
  } else if (_bit(firstBits, 0) == '1') {
    meaUnit = 'kPa';
  }
  var stepper = 6;
  final systolic = at(2) * 256 + at(1);
  final diastolic = at(4) * 256 + at(3);
  final meanArterial = at(6) * 256 + at(5);
  final year = at(8) * 256 + at(7);
  final timestamp =
      '$year/${at(9)}/${at(10)} ${at(11)}:${at(12)}:${at(13)}';
  if (_bit(firstBits, 1) == '1') stepper = 13;
  var pulseRate = 0;
  if (_bit(firstBits, 2) == '1') {
    pulseRate = at(14) * 256 + at(15);
    stepper += 2;
  }
  var userId = at(16);
  if (_bit(firstBits, 3) == '1') {
    userId = at(16);
    stepper += 1;
  }
  var text = '';
  if (_bit(firstBits, 4) == '1') {
    final statusByte = at(stepper + 2) * 256 + at(stepper + 1);
    final s = statusByte.toRadixString(2);
    if (_bit(s, 0) == '1') text = 'Body movement during measurement';
    if (_bit(s, 1) == '1') text = 'Cuff too loose';
    if (_bit(s, 2) == '1') text = 'Irregular pulse detected';
    if (_bit(s, 3) == '0' && _bit(s, 4) == '0') {
      text = 'Pulse rate is within the range';
    }
    if (_bit(s, 3) == '0' && _bit(s, 4) == '1') {
      text = 'Pulse rate exceeds upper limit';
    }
    if (_bit(s, 3) == '1' && _bit(s, 4) == '0') {
      text = 'Pulse rate is less than lower limit';
    }
    if (_bit(s, 5) == '1') text = 'Improper measurement position';
  }
  return {
    'DAQTimestamp': timeStamp,
    'RecordNumber': recordNumber,
    'DeviceID': beurerBm85Bp,
    'DeviceMeasurementNum': deviceMeasurementNum,
    'bPMCVSystolic': systolic,
    'bPMCVDiastolic': diastolic,
    'bPMCVMeanArterialPressure': meanArterial,
    'MeasurementUnit': meaUnit,
    'MeasurementDateTime': timestamp,
    'PulseRate': pulseRate,
    'UserID': userId,
    'MeasurementEnvironment': text,
  };
}

/// Dcont Nemere glucose measurement (characteristic 2A18).
Json? parseNemere(
  List<int> b, {
  required int timeStamp,
  required int recordNumber,
  required int deviceMeasurementNum,
}) {
  if (b.length < 12) return null;
  int at(int i) => i >= 0 && i < b.length ? b[i] : 0;
  final sequenceNumber = at(2) * 256 + at(1);
  final year = at(4) * 256 + at(3);
  final month = at(5);
  final day = at(6);
  final hour = at(7);
  final minute = at(8);
  final u16 = at(11) * 256 + at(10);
  final mantissa = u16 & 0x0FFF;
  final glValue = (mantissa / 18.018018).toStringAsFixed(1);
  // The original masks the flags with 32 and then compares the result with 1
  // (never true), so the unit is "mol/L" when the flag is clear and the
  // placeholder "x" when it is set.
  final meaUnit = (at(0) & 32) == 0 ? 'mol/L' : 'x';
  return {
    'DAQTimestamp': timeStamp,
    'RecordNumber': recordNumber,
    'DeviceID': dcontNemereGl,
    'DeviceMeasurementNum': deviceMeasurementNum,
    'DeviceSeqNum': sequenceNumber,
    'MeasurementDateTime': '$year.$month.$day. $hour:$minute',
    'glValue': glValue,
    'MeasurementUnit': meaUnit,
  };
}

/// Standard heart rate measurement (Polar H7, characteristic 2A37), as read
/// by `ble_central_caller.onReadBPData` of the old app. Returns the BPM and
/// the mean RR interval (ms, as string, '' when absent).
({int bpm, String rr})? parseHeartRate(List<int> b) {
  if (b.length < 2) return null;
  // The original uses the *padded binary string* of the flags byte indexed
  // from its first character (i.e. the most significant bit).
  final flags = ('0000000000${b[0].toRadixString(2)}');
  final f = flags.substring(flags.length - 8);
  var offset = 1;
  final bpm = b[1];
  offset += 1; // both branches of the original end up reading one byte
  if (f[0] != '0') offset = 3;
  if (f[2] == '1') offset += 2;
  var rr = '';
  if (f[3] != '0') {
    final count = (b.length - offset) / 2;
    var total = 0.0;
    var counter = 0;
    var o = offset;
    for (var i = 0; i < count; i++) {
      final v = (o < b.length ? b[o] : 0) & 0xFFFF;
      total += (v / 1024.0) * 1000.0;
      o += 2;
      counter++;
    }
    rr = counter == 0 ? 'NaN' : _jsNumber(total / counter);
  }
  return (bpm: bpm, rr: rr);
}

/// `Date.parse("2025/11/4 9:5:3")` (local time) -> milliseconds, or null.
int? parseSlashDate(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^\s*(\d+)/(\d+)/(\d+)[ T](\d+):(\d+)(?::(\d+))?\s*$')
      .firstMatch(value);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    m.group(6) == null ? 0 : int.parse(m.group(6)!),
  ).millisecondsSinceEpoch;
}

/// JavaScript `Number.prototype.toString()` for the values used here.
String _jsNumber(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
