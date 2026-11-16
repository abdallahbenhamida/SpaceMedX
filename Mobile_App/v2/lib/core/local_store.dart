import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'analysis.dart';

/// A batch the server has not accepted yet (kept on the phone).
class PendingBatch {
  const PendingBatch(this.id, this.url, this.body, this.records, this.label);
  final int id;
  final String url;
  final String body;
  final int records;
  final String label;
}

/// Everything kept on the phone: the measurements (for the charts and the
/// analysis, also with no network) and the batches waiting for the server.
abstract class LocalStore {
  Future<void> addObservation(String param, DateTime time, double value, String source);

  /// Points of [param] between [from] and [to]. Series with more than
  /// [maxPoints] values are averaged into [maxPoints] buckets.
  Future<List<Point>> series(String param, DateTime from, DateTime to, {int maxPoints = 240});

  /// Names of data types a source registered (so charts have titles after a restart).
  Future<void> saveParamDef(String id, String name, String unit, int decimals);
  Future<List<({String id, String name, String unit, int decimals})>> paramDefs();

  /// The data types that have at least one value between [from] and [to].
  Future<Set<String>> paramsWithData(DateTime from, DateTime to);

  Future<int> observationCount();
  Future<void> purgeOlderThan(DateTime time);
  Future<void> clearObservations();

  // upload queue
  Future<int> enqueue(String url, String body, int records, String label);
  Future<List<PendingBatch>> queue();
  Future<void> dequeue(int id);
}

// ---------------------------------------------------------------------------

class _Obs {
  _Obs(this.param, this.ms, this.value);
  final String param;
  final int ms;
  final double value;
}

/// In-memory store (tests, and the fallback if the database cannot be opened).
class MemoryStore implements LocalStore {
  final List<_Obs> _obs = [];
  final List<PendingBatch> _queue = [];
  int _nextId = 1;

  @override
  Future<void> addObservation(String param, DateTime time, double value, String source) async {
    _obs.add(_Obs(param, time.millisecondsSinceEpoch, value));
  }

  @override
  Future<List<Point>> series(String param, DateTime from, DateTime to, {int maxPoints = 240}) async {
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;
    final rows = _obs.where((o) => o.param == param && o.ms >= f && o.ms <= t).toList()
      ..sort((a, b) => a.ms.compareTo(b.ms));
    if (rows.length <= maxPoints) {
      return [for (final r in rows) Point(DateTime.fromMillisecondsSinceEpoch(r.ms), r.value)];
    }
    final bucket = ((t - f) / maxPoints).ceil().clamp(1, 1 << 40);
    final groups = <int, List<_Obs>>{};
    for (final r in rows) {
      groups.putIfAbsent((r.ms - f) ~/ bucket, () => []).add(r);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final k in keys)
        () {
          final g = groups[k]!;
          final avg = g.fold<double>(0, (a, b) => a + b.value) / g.length;
          final ms = g.fold<int>(0, (a, b) => a + b.ms) ~/ g.length;
          return Point(
            DateTime.fromMillisecondsSinceEpoch(ms),
            avg,
            min: g.map((e) => e.value).reduce((a, b) => a < b ? a : b),
            max: g.map((e) => e.value).reduce((a, b) => a > b ? a : b),
          );
        }(),
    ];
  }

  final Map<String, ({String id, String name, String unit, int decimals})> _defs = {};

  @override
  Future<void> saveParamDef(String id, String name, String unit, int decimals) async {
    _defs[id] = (id: id, name: name, unit: unit, decimals: decimals);
  }

  @override
  Future<List<({String id, String name, String unit, int decimals})>> paramDefs() async => _defs.values.toList();

  @override
  Future<Set<String>> paramsWithData(DateTime from, DateTime to) async => {
        for (final o in _obs)
          if (o.ms >= from.millisecondsSinceEpoch && o.ms <= to.millisecondsSinceEpoch) o.param,
      };

  @override
  Future<int> observationCount() async => _obs.length;

  @override
  Future<void> purgeOlderThan(DateTime time) async =>
      _obs.removeWhere((o) => o.ms < time.millisecondsSinceEpoch);

  @override
  Future<void> clearObservations() async => _obs.clear();

  @override
  Future<int> enqueue(String url, String body, int records, String label) async {
    final id = _nextId++;
    _queue.add(PendingBatch(id, url, body, records, label));
    return id;
  }

  @override
  Future<List<PendingBatch>> queue() async => List.of(_queue);

  @override
  Future<void> dequeue(int id) async => _queue.removeWhere((q) => q.id == id);
}

// ---------------------------------------------------------------------------

/// SQLite store (`spacemedx.db` in the app's private storage).
class SqliteStore implements LocalStore {
  SqliteStore._(this._db);
  final Database _db;

  static Future<SqliteStore> open({String? path}) async {
    final file = path ?? p.join(await getDatabasesPath(), 'spacemedx.db');
    final db = await openDatabase(
      file,
      version: 2,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createMeta(db);
      },
      onCreate: (db, _) async {
        await _createMeta(db);
        await db.execute('CREATE TABLE obs('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'param TEXT NOT NULL,'
            'ts INTEGER NOT NULL,'
            'v REAL NOT NULL,'
            'source TEXT NOT NULL)');
        await db.execute('CREATE INDEX obs_param_ts ON obs(param, ts)');
        await db.execute('CREATE TABLE queue('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'url TEXT NOT NULL,'
            'body TEXT NOT NULL,'
            'records INTEGER NOT NULL,'
            'label TEXT NOT NULL)');
      },
    );
    return SqliteStore._(db);
  }

  @override
  Future<void> addObservation(String param, DateTime time, double value, String source) async {
    await _db.insert('obs', {
      'param': param,
      'ts': time.millisecondsSinceEpoch,
      'v': value,
      'source': source,
    });
  }

  @override
  Future<List<Point>> series(String param, DateTime from, DateTime to, {int maxPoints = 240}) async {
    final f = from.millisecondsSinceEpoch;
    final t = to.millisecondsSinceEpoch;
    final n = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COUNT(*) FROM obs WHERE param = ? AND ts >= ? AND ts <= ?', [param, f, t])) ??
        0;
    if (n <= maxPoints) {
      final rows = await _db.rawQuery(
          'SELECT ts, v FROM obs WHERE param = ? AND ts >= ? AND ts <= ? ORDER BY ts', [param, f, t]);
      return [
        for (final r in rows) Point(DateTime.fromMillisecondsSinceEpoch(r['ts'] as int), (r['v'] as num).toDouble())
      ];
    }
    final bucket = ((t - f) / maxPoints).ceil().clamp(1, 1 << 40);
    final rows = await _db.rawQuery(
        'SELECT (ts - ?) / ? AS b, AVG(ts) AS ats, AVG(v) AS av, MIN(v) AS lo, MAX(v) AS hi '
        'FROM obs WHERE param = ? AND ts >= ? AND ts <= ? GROUP BY b ORDER BY b',
        [f, bucket, param, f, t]);
    return [
      for (final r in rows)
        Point(
          DateTime.fromMillisecondsSinceEpoch((r['ats'] as num).round()),
          (r['av'] as num).toDouble(),
          min: (r['lo'] as num).toDouble(),
          max: (r['hi'] as num).toDouble(),
        )
    ];
  }

  static Future<void> _createMeta(Database db) => db.execute('CREATE TABLE IF NOT EXISTS param_meta('
      'param TEXT PRIMARY KEY,'
      'name TEXT NOT NULL,'
      'unit TEXT NOT NULL,'
      'decimals INTEGER NOT NULL)');

  @override
  Future<void> saveParamDef(String id, String name, String unit, int decimals) async {
    await _db.insert(
      'param_meta',
      {'param': id, 'name': name, 'unit': unit, 'decimals': decimals},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<({String id, String name, String unit, int decimals})>> paramDefs() async {
    final rows = await _db.query('param_meta');
    return [
      for (final r in rows)
        (
          id: r['param'] as String,
          name: r['name'] as String,
          unit: r['unit'] as String,
          decimals: r['decimals'] as int,
        )
    ];
  }

  @override
  Future<Set<String>> paramsWithData(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
        'SELECT DISTINCT param FROM obs WHERE ts >= ? AND ts <= ?',
        [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
    return {for (final r in rows) r['param'] as String};
  }

  @override
  Future<int> observationCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM obs')) ?? 0;

  @override
  Future<void> purgeOlderThan(DateTime time) async {
    await _db.delete('obs', where: 'ts < ?', whereArgs: [time.millisecondsSinceEpoch]);
  }

  @override
  Future<void> clearObservations() async {
    await _db.delete('obs');
  }

  @override
  Future<int> enqueue(String url, String body, int records, String label) =>
      _db.insert('queue', {'url': url, 'body': body, 'records': records, 'label': label});

  @override
  Future<List<PendingBatch>> queue() async {
    final rows = await _db.query('queue', orderBy: 'id');
    return [
      for (final r in rows)
        PendingBatch(r['id'] as int, r['url'] as String, r['body'] as String, r['records'] as int, r['label'] as String)
    ];
  }

  @override
  Future<void> dequeue(int id) async {
    await _db.delete('queue', where: 'id = ?', whereArgs: [id]);
  }
}
