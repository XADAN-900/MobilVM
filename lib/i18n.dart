import 'l10n.dart';
import 'state.dart';

/// Uygulamanın desteklediği diller (ilk açılışta İngilizce).
const languages = <String, String>{
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'pt': 'Português',
  'ru': 'Русский',
  'tr': 'Türkçe',
  'ar': 'العربية',
};

/// Sağdan sola yazılan diller.
const rtlLanguages = {'ar'};

String _fill(String s, List<Object?> args) {
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Çok dilli metin: t('Türkçe', 'English', [argümanlar]).
/// İngilizce metin anahtardır; diğer diller l10n.dart'taki tablolardan gelir.
String t(String tr, String en, [List<Object?> args = const []]) {
  final lang = app.lang;
  final s = switch (lang) {
    'tr' => tr,
    'en' => en,
    _ => translations[lang]?[en] ?? en,
  };
  return _fill(s, args);
}

/// Yalnızca İngilizce anahtarı olan metinler (ör. "Other / Unknown (64-bit)").
String tx(String en, [List<Object?> args = const []]) =>
    _fill(app.lang == 'en' ? en : translations[app.lang]?[en] ?? en, args);
