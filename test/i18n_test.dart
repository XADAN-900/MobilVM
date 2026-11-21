import 'package:flutter_test/flutter_test.dart';
import 'package:strata_vm/models.dart';
import 'package:strata_vm/state.dart';

void main() {
  tearDown(() => app.settings['language'] = 'en');

  test('ilk açılış İngilizce', () {
    expect(app.lang, 'en');
    expect(t('Ayarlar', 'Settings'), 'Settings');
  });

  test('8 dil çalışıyor', () {
    final expected = {
      'en': 'Settings',
      'de': 'Einstellungen',
      'fr': 'Paramètres',
      'es': 'Ajustes',
      'pt': 'Configurações',
      'ru': 'Настройки',
      'tr': 'Ayarlar',
      'ar': 'الإعدادات',
    };
    expect(languages.keys.toSet(), expected.keys.toSet());
    for (final e in expected.entries) {
      app.settings['language'] = e.key;
      expect(t('Ayarlar', 'Settings'), e.value, reason: e.key);
    }
  });

  test('yer tutucular ve OS adları', () {
    app.settings['language'] = 'de';
    expect(t('"{0}" silinsin mi?', 'Delete "{0}"?', ['XP']), '„XP“ löschen?');
    expect(osById('custom').label, 'Andere / Unbekannt (64-Bit)');
    app.settings['language'] = 'tr';
    expect(osById('linux64').label, 'Linux (64-bit, diğer)');
    app.settings['language'] = 'ar';
    expect(rtlLanguages.contains(app.lang), isTrue);
  });
}
