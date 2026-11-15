import 'package:flutter_test/flutter_test.dart';
import 'package:spacemedx/core/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('SQLite store: observations, buckets, purge, queue', () async {
    final st = await SqliteStore.open(path: inMemoryDatabasePath);
    final t0 = DateTime(2026, 1, 1);
    for (var i = 0; i < 1000; i++) {
      await st.addObservation('hr', t0.add(Duration(seconds: i)), 60.0 + (i % 10), 'x');
    }
    await st.addObservation('sys', t0, 120, 'x');

    final many = await st.series('hr', t0, t0.add(const Duration(seconds: 1000)), maxPoints: 100);
    expect(many.length, inInclusiveRange(90, 101));
    expect(many.first.min, isNotNull);
    expect(many.first.max! >= many.first.min!, isTrue);

    final few = await st.series('hr', t0, t0.add(const Duration(seconds: 3)), maxPoints: 100);
    expect(few.length, 4);
    expect((await st.series('sys', t0, t0)).single.value, 120);

    await st.purgeOlderThan(t0.add(const Duration(seconds: 500)));
    expect(await st.observationCount(), 500); // the older sys value is purged too
  });

  test('SQLite store: upload queue keeps order', () async {
    final st = await SqliteStore.open(path: inMemoryDatabasePath);
    final a = await st.enqueue('u1', 'b1', 2, 'x');
    await st.enqueue('u2', 'b2', 3, 'y');
    var q = await st.queue();
    expect(q.map((e) => e.url), ['u1', 'u2']);
    await st.dequeue(a);
    q = await st.queue();
    expect(q.single.url, 'u2');
    expect(q.single.records, 3);
  });

  test('SQLite store: data types present and their names', () async {
    final st = await SqliteStore.open(path: inMemoryDatabasePath);
    final t = DateTime(2031, 1, 1);
    await st.addObservation('w_steps', t, 5, 'watch');
    await st.addObservation('hr', t.add(const Duration(days: 9)), 70, 'x');
    expect(await st.paramsWithData(t, t.add(const Duration(hours: 1))), {'w_steps'});
    await st.saveParamDef('w_steps', 'Steps', 'steps', 0);
    await st.saveParamDef('w_steps', 'Steps taken', 'steps', 0); // replaces
    final d = await st.paramDefs();
    expect(d.single.name, 'Steps taken');
  });
}
