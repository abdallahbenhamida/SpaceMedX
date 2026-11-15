import 'dart:convert';

/// Wire protocol between this app and the watch companion app (see
/// the watch protocol document). Messages are UTF-8 JSON objects.
class WatchProtocol {
  WatchProtocol._();

  static const int version = 2;
  static const String service = '6a8d0001-4f1b-4c6e-9d4a-7d1f5b0c2e11';
  static const String control = '6a8d0002-4f1b-4c6e-9d4a-7d1f5b0c2e11';
  static const String events = '6a8d0003-4f1b-4c6e-9d4a-7d1f5b0c2e11';
  static const String data = '6a8d0004-4f1b-4c6e-9d4a-7d1f5b0c2e11';
  static const String ota = '6a8d0005-4f1b-4c6e-9d4a-7d1f5b0c2e11';

  /// Smallest MTU that fits the biggest message of the watch (frames of at
  /// most 170 characters + 3 bytes of ATT overhead, with margin).
  static const int minMtu = 185;
  static const int wantedMtu = 247;

  static List<int> encode(Map<String, Object?> message) =>
      utf8.encode(jsonEncode(message));

  static Map<String, dynamic>? decode(List<int> bytes) {
    try {
      final v = jsonDecode(utf8.decode(bytes));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> hello(String id, String name) =>
      {'m': 'hello', 'v': version, 'id': id, 'name': name};

  static Map<String, Object?> pair(String id, String name) =>
      {'m': 'pair', 'v': version, 'id': id, 'name': name};

  static Map<String, Object?> listParams() => {'m': 'params'};

  static Map<String, Object?> setActive(Iterable<String> ids,
          [Iterable<String> uploading = const []]) =>
      {'m': 'set', 'p': ids.toList(), 'u': uploading.toList()};

  /// The phone's answer to the sensor list: the record names it will use.
  static Map<String, Object?> deal(List<Map<String, Object?>> items) =>
      {'m': 'deal', 'items': items};

  static Map<String, Object?> otaBegin(int size, String sha256, int versionCode) =>
      {'m': 'ota_begin', 'size': size, 'sha': sha256, 'ver': versionCode};

  static Map<String, Object?> otaAbort() => {'m': 'ota_abort'};

  static Map<String, Object?> unpair() => {'m': 'unpair'};

  static Map<String, Object?> ping() => {'m': 'ping'};
}

/// One data type the watch offers.
class WatchParam {
  const WatchParam({
    required this.id,
    required this.name,
    required this.unit,
    required this.group,
    required this.available,
    required this.why,
    required this.fields,
    required this.rateHz,
    this.srv = "",
    this.onDemand = false,
    this.hint = "",
  });

  final String id;
  final String name;
  final String unit;
  final String group;
  final bool available;
  final String why;
  final List<String> fields;
  final double rateHz;

  /// Record type the watch suggests for the server.
  final String srv;

  /// Measured only when the wearer acts (ECG, SpO2, body composition).
  final bool onDemand;
  final String hint;

  factory WatchParam.fromMessage(Map<String, dynamic> m) => WatchParam(
        id: '${m['id']}',
        name: '${m['name'] ?? m['id']}',
        unit: '${m['unit'] ?? ''}',
        group: '${m['grp'] ?? ''}',
        available: m['ok'] == true,
        why: '${m['why'] ?? ''}',
        fields: ((m['f'] ?? const []) as List).map((e) => '$e').toList(),
        rateHz: (m['hz'] is num) ? (m['hz'] as num).toDouble() : 1,
        srv: '${m['srv'] ?? ''}',
        onDemand: m['od'] == true,
        hint: '${m['hint'] ?? ''}',
      );
}

/// One sample of one parameter with its time.
class WatchSample {
  const WatchSample(this.timeMs, this.values);
  final int timeMs;
  final List<double?> values;
}

/// A DATA frame: `{"p":id,"t":firstMs,"i":intervalMs,"v":[flat values]}`.
class WatchFrame {
  const WatchFrame(this.paramId, this.samples);
  final String paramId;
  final List<WatchSample> samples;

  /// [fieldCount] = number of values per sample (from the parameter list).
  static WatchFrame? parse(Map<String, dynamic> m, int Function(String id) fieldCount) {
    final id = m['p'];
    final v = m['v'];
    final t = m['t'];
    if (id is! String || v is! List || t is! num) return null;
    final n = fieldCount(id);
    if (n <= 0) return null;
    final interval = (m['i'] is num) ? (m['i'] as num).toInt() : 0;
    final out = <WatchSample>[];
    for (var k = 0; (k + 1) * n <= v.length; k++) {
      out.add(WatchSample(t.toInt() + k * interval, [
        for (var j = 0; j < n; j++) (v[k * n + j] as num?)?.toDouble(),
      ]));
    }
    return WatchFrame(id, out);
  }
}
