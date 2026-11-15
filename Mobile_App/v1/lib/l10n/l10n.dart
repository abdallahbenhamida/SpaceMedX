import 'dart:ui' show Locale;

import 'keys.dart';
import 'lang_ar.dart';
import 'lang_de.dart';
import 'lang_es.dart';
import 'lang_fr.dart';
import 'lang_hu.dart';
import 'lang_it.dart';
import 'lang_ko.dart';
import 'lang_nl.dart';
import 'lang_pl.dart';
import 'lang_pt.dart';

/// A language the app can show. [name] is written in that language itself.
class Lang {
  const Lang(this.code, this.name);
  final String code;
  final String name;
}

const List<Lang> supportedLangs = [
  Lang('en', 'English'),
  Lang('fr', 'Français'),
  Lang('de', 'Deutsch'),
  Lang('hu', 'Magyar'),
  Lang('es', 'Español'),
  Lang('it', 'Italiano'),
  Lang('pt', 'Português'),
  Lang('nl', 'Nederlands'),
  Lang('pl', 'Polski'),
  Lang('ar', 'العربية'),
  Lang('ko', '한국어'),
];

/// The translations, in the order of [kKeys]. The English text of the app is
/// the key itself, so a missing translation simply shows English.
const Map<String, List<String>> translations = {
  'fr': langFr,
  'de': langDe,
  'hu': langHu,
  'es': langEs,
  'it': langIt,
  'pt': langPt,
  'nl': langNl,
  'pl': langPl,
  'ar': langAr,
  'ko': langKo,
};

/// The language in use. Set from the settings (see AppSettings).
class L10n {
  L10n._();

  static String _code = 'en';
  static Map<String, String> _table = const {};

  static String get code => _code;
  static Locale get locale => Locale(_code);
  static bool get isRtl => _code == 'ar';

  static Map<String, String> _build(String code) {
    final values = translations[code];
    if (values == null) return const {};
    return {for (var i = 0; i < kKeys.length && i < values.length; i++) kKeys[i]: values[i]};
  }

  /// [setting] is 'system' or a language code; [device] is the phone's language.
  static void apply(String setting, String device) {
    var c = setting == 'system' ? device : setting;
    if (!supportedLangs.any((l) => l.code == c)) c = 'en';
    _code = c;
    _table = _build(c);
  }
}

/// Translates [key] (the English text) and fills in `{name}` placeholders.
String tr(String key, [Map<String, Object>? args]) {
  var s = L10n._table[key] ?? key;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}
