import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacemedx/core/analysis.dart';
import 'package:spacemedx/l10n/keys.dart';
import 'package:spacemedx/l10n/l10n.dart';

Set<String> _placeholders(String s) => RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  tearDown(() => L10n.apply('en', 'en'));

  test('the key list has no duplicates', () {
    expect(kKeys.toSet().length, kKeys.length);
  });

  test('every language has exactly one text per key, none empty', () {
    for (final e in translations.entries) {
      expect(e.value.length, kKeys.length, reason: '${e.key} has ${e.value.length} texts, needs ${kKeys.length}');
      for (var i = 0; i < kKeys.length; i++) {
        expect(e.value[i].trim(), isNotEmpty, reason: '${e.key} #$i (${kKeys[i]})');
      }
    }
  });

  test('every language is offered in the list, and the list only has languages that exist', () {
    expect(supportedLangs.first.code, 'en');
    for (final l in supportedLangs.skip(1)) {
      expect(translations.containsKey(l.code), isTrue, reason: l.code);
    }
    expect(translations.keys.toSet(), supportedLangs.skip(1).map((l) => l.code).toSet());
  });

  test('{placeholders} are kept in every translation (this also catches texts in the wrong place)', () {
    for (final e in translations.entries) {
      for (var i = 0; i < kKeys.length; i++) {
        expect(_placeholders(e.value[i]), _placeholders(kKeys[i]), reason: '${e.key} #$i: ${kKeys[i]}');
      }
    }
  });

  test('numbers stay with their text (a shifted list would break this)', () {
    for (final e in translations.entries) {
      for (final key in ['15 min', '24 hours', '7 days']) {
        final digits = RegExp(r'\d+').firstMatch(key)!.group(0)!;
        expect(e.value[kKeys.indexOf(key)], contains(digits), reason: '${e.key}: $key');
      }
      for (final key in ['Grade 1 hypertension', 'Grade 2 hypertension', 'Grade 3 hypertension']) {
        final digit = RegExp(r'\d').firstMatch(key)!.group(0)!;
        expect(e.value[kKeys.indexOf(key)], contains(digit), reason: '${e.key}: $key');
      }
    }
  });

  test('every text the code asks for with tr(...) has a translation slot', () {
    final re = RegExp(r"""tr\(\s*'((?:[^'\\]|\\.)*)'""");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('l10n')) continue;
      for (final m in re.allMatches(f.readAsStringSync())) {
        final key = m.group(1)!.replaceAll(r"\'", "'");
        if (!kKeys.contains(key)) missing.add(key);
      }
    }
    expect(missing, isEmpty, reason: 'add these to lib/l10n/keys.dart and every language file');
  });

  test('texts that reach tr() by variable are covered: ranges, levels', () {
    final need = <String>{};
    for (final p in Ranges.all) {
      need.add(p.name);
      need.add(p.source);
      if (p.note.isNotEmpty) need.add(p.note);
      for (final b in p.bands) {
        need.add(b.label);
      }
    }
    L10n.apply('en', 'en');
    for (final l in Level.values) {
      need.add(l.text);
    }
    final missing = need.where((k) => !kKeys.contains(k)).toList();
    expect(missing, isEmpty);
  });

  test('switching the language changes the texts, and unknown texts stay English', () {
    L10n.apply('hu', 'en');
    expect(tr('Heart rate'), 'Pulzusszám');
    expect(Level.normal.text, 'Normál');
    expect(tr('Some text nobody translated'), 'Some text nobody translated');
    expect(tr('{n} days', {'n': 7}), '7 nap');
    L10n.apply('ko', 'en');
    expect(tr('Settings'), '설정');
    L10n.apply('ar', 'en');
    expect(L10n.isRtl, isTrue);
    L10n.apply('fr', 'en');
    expect(tr('START'), 'DÉMARRER');
    L10n.apply('de', 'en');
    expect(tr('Settings'), 'Einstellungen');
    L10n.apply('en', 'en');
    expect(tr('Settings'), 'Settings');
  });

  test('"system" follows the phone language, an unsupported one falls back to English', () {
    L10n.apply('system', 'fr');
    expect(L10n.code, 'fr');
    L10n.apply('system', 'xx');
    expect(L10n.code, 'en');
    L10n.apply('system', 'hu');
    expect(L10n.code, 'hu');
  });
}
