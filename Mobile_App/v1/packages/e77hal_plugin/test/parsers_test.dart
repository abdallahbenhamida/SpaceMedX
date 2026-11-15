import 'package:e77hal_plugin/e77hal_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

/// Packs 10-bit samples little-endian like the Savvy ECG does.
List<int> packSamples(List<int> samples) {
  final bytes = List<int>.filled(19, 0);
  for (var i = 0; i < samples.length; i++) {
    for (var bit = 0; bit < 10; bit++) {
      if ((samples[i] >> bit) & 1 == 1) {
        final pos = i * 10 + bit;
        bytes[pos >> 3] |= 1 << (pos & 7);
      }
    }
  }
  return bytes;
}

void main() {
  group('Savvy ECG', () {
    test('PIN command equals the value documented in e77hal.js (BwQ5NTQ1)', () {
      expect(savvyPinCommand('9545'), [7, 4, 0x39, 0x35, 0x34, 0x35]);
    });

    test('19 byte packet unpacks to 14 ten-bit samples', () {
      final samples = [1, 2, 3, 511, 512, 1023, 0, 100, 200, 300, 400, 500, 600, 700];
      expect(savvyEcgString(packSamples(samples)), samples.join(','));
    });

    test('other packet sizes give an empty string', () {
      expect(savvyEcgString(List<int>.filled(18, 1)), '');
      expect(savvyEcgString(const []), '');
    });

    test('getBit only sees bit 0 of whole bytes (original quirk)', () {
      final v = List<int>.filled(14, 0)..[12] = 1..[13] = 3;
      expect(getBit(v, 96), isTrue);
      expect(getBit(v, 104), isTrue);
      expect(getBit(v, 97), isFalse); // fractional index in the original
      expect(getBit(v, 105), isFalse);
      final stats = SavvyStats(v);
      expect(stats.ecgSamplingEnabled, isTrue);
      expect(stats.stackOverflow, isTrue);
      expect(stats.batteryLow, isFalse);
    });
  });

  group('Beurer BM85', () {
    List<int> packet(int flags, {int status = 0}) => [
          flags,
          120, 0, // systolic
          80, 0, // diastolic
          93, 0, // mean arterial
          0xE9, 0x07, 11, 4, 9, 5, 3, // 2025/11/4 9:5:3
          0, 72, // pulse (original reads high byte first)
          1, // user id
          status & 0xff, status >> 8,
        ];

    test('parses values and date like processBeurerData', () {
      final r = parseBeurer(packet(0x1E),
          timeStamp: 111, recordNumber: 7, deviceMeasurementNum: 2)!;
      expect(r['DeviceID'], 'EID_102');
      expect(r['bPMCVSystolic'], 120);
      expect(r['bPMCVDiastolic'], 80);
      expect(r['bPMCVMeanArterialPressure'], 93);
      expect(r['MeasurementDateTime'], '2025/11/4 9:5:3');
      expect(r['PulseRate'], 72);
      expect(r['UserID'], 1);
      expect(r['MeasurementEnvironment'], '');
      expect(r['DAQTimestamp'], 111);
      expect(r['RecordNumber'], 7);
      expect(r['DeviceMeasurementNum'], 2);
      // flags byte 30 -> "11110": first char '1' -> kPa (original quirk)
      expect(r['MeasurementUnit'], 'kPa');
    });

    test('measurement status text', () {
      final r = parseBeurer(packet(0x1F, status: 1),
          timeStamp: 1, recordNumber: 1, deviceMeasurementNum: 1)!;
      expect(r['MeasurementEnvironment'], 'Body movement during measurement');
    });

    test('too short packets are ignored', () {
      expect(parseBeurer([30, 1, 2],
          timeStamp: 1, recordNumber: 1, deviceMeasurementNum: 1), isNull);
    });
  });

  group('Dcont Nemere', () {
    List<int> packet(int flags) =>
        [flags, 5, 0, 0xE9, 0x07, 11, 4, 9, 5, 0, 108, 0, 0, 0];

    test('parses glucose, date and sequence number', () {
      final r = parseNemere(packet(0),
          timeStamp: 5, recordNumber: 1, deviceMeasurementNum: 1)!;
      expect(r['DeviceID'], 'EID_101');
      expect(r['DeviceSeqNum'], 5);
      expect(r['MeasurementDateTime'], '2025.11.4. 9:5');
      expect(r['glValue'], '6.0');
      expect(r['MeasurementUnit'], 'mol/L');
    });

    test('unit placeholder when flag 0x20 is set', () {
      final r = parseNemere(packet(0x20),
          timeStamp: 5, recordNumber: 1, deviceMeasurementNum: 1)!;
      expect(r['MeasurementUnit'], 'x');
    });
  });

  group('Polar H7', () {
    test('pulse is byte 1', () {
      expect(parseHeartRate([0x16, 72, 0x80, 0x03])!.bpm, 72);
    });
    test('rr interval of the first byte', () {
      expect(parseHeartRate([0x16, 72, 0x80, 0x03])!.rr, '125');
    });
  });

  test('parseSlashDate', () {
    final ms = parseSlashDate('2025/11/4 9:5:3')!;
    expect(DateTime.fromMillisecondsSinceEpoch(ms), DateTime(2025, 11, 4, 9, 5, 3));
    expect(parseSlashDate('nope'), isNull);
    expect(parseSlashDate(null), isNull);
  });

  group('DataRingBuffer', () {
    test('push / prev / pointer', () {
      final b = DataRingBuffer(5);
      expect(b.prev(), isNull); // does not wrap below 0
      final e1 = b.push(RingEntry({'a': 1}, true));
      b.push(RingEntry({'a': 2}, true));
      expect(b.getptr(), 2);
      expect(b.prev()!.record['a'], 2);
      expect(b.getptr(), 1);
      expect(b.prev(), same(e1));
      expect(b.prev(), isNull);
    });
  });
}
