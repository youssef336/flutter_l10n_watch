import 'dart:io';

import 'package:flutter_l10n_watch/flutter_l10n_watch.dart';
import 'package:flutter_l10n_watch/src/catalog.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('catalog', () {
    test('locale names', () {
      expect(isLocaleName('en'), isTrue);
      expect(isLocaleName('pt-BR'), isTrue);
      expect(isLocaleName('zh_Hant_TW'), isTrue);
      expect(isLocaleName('config'), isFalse);
      expect(isLocaleName('English'), isFalse);
      expect(localeFromArbName('app_en'), 'en');
      expect(localeFromArbName('intl_pt_BR'), 'pt_BR');
      expect(localeFromArbName('app_zh_Hant_TW'), 'zh_Hant_TW');
      expect(localeFromArbName('my_app_de'), 'de');
      expect(localeFromArbName('en'), 'en');
      expect(localeFromArbName('strings'), isNull);
      expect(languageOf('pt_BR'), 'pt');
    });

    test('groupKindOf detects plural and gender groups', () {
      expect(groupKindOf({'one': 'a', 'other': 'b'}), EntryKind.plural);
      expect(groupKindOf({'other': 'b'}), EntryKind.plural);
      expect(groupKindOf({'male': 'a', 'female': 'b', 'other': 'c'}), EntryKind.gender);
      expect(groupKindOf({'title': 'a', 'other': 'b'}), isNull);
      expect(groupKindOf({'one': 'a', 'other': <String, String>{}}), isNull);
    });

    test('loads nested JSON with groups', () {
      final file = loadJsonLocale(p.join(fixture('easy_app'), 'assets/translations/en.json'), 'en');
      expect(file.errors, isEmpty);
      expect(file.entries['cart.title']!.text, 'Your cart');
      expect(file.entries['apples']!.kind, EntryKind.plural);
      expect(file.entries['apples']!.display, '{} apples');
    });

    test('plain JSON keeps plural-looking objects as nested keys', () {
      final file = loadJsonLocale(
        p.join(fixture('easy_app'), 'assets/translations/en.json'),
        'en',
        detectGroups: false,
      );
      expect(file.entries['apples.one']!.text, '{} apple');
    });

    test('invalid JSON is reported, not thrown', () {
      final root = tempProject({'en.json': '{"a": '});
      addTearDown(() => root.deleteSync(recursive: true));
      final file = loadJsonLocale(p.join(root.path, 'en.json'), 'en');
      expect(file.errors.single, startsWith('invalid JSON'));
    });

    test('loads ARB messages and metadata', () {
      final file = loadArbLocale(p.join(fixture('arb_app'), 'lib/l10n/app_en.arb'), 'xx');
      expect(file.locale, 'en');
      expect(file.entries.keys, contains('hello'));
      expect(file.entries.keys, isNot(contains('@hello')));
      expect(file.metadata['hello']!['placeholders'], isA<Map<dynamic, dynamic>>());
      expect(file.metadata.keys, contains('ghost'));
    });
  });

  group('config', () {
    test('defaults', () {
      final config = Config.parse('');
      expect(config.format, isNull);
      expect(config.sourceDirs, ['lib']);
      expect(config.lengthRatio, 1.6);
      expect(config.severityOf(CheckId.missingTranslation), Severity.error);
      expect(config.requiredPlurals('ar'), hasLength(6));
      expect(config.requiredPlurals('en'), ['one', 'other']);
      expect(config.exclude, contains('**/*.g.dart'));
    });

    test('reads every section', () {
      final config = Config.parse('''
format: arb
translations_dir: res/l10n
base_locale: de
source_dirs: [lib, packages/ui/lib]
exclude: ['lib/legacy/**']
ignore_keys: ['^debug_']
untranslated:
  min_letters: 5
  allow: [Acme]
  todo_marker: 'XX '
length:
  ratio: 2
  min_chars: 10
hardcoded:
  ignore: ['^Lorem']
plural_rules:
  en: [one, other, many]
severity:
  unused_key: error
  rtl_smell: off
fail_on: warning
''');
      expect(config.format, L10nFormat.arb);
      expect(config.translationsDir, 'res/l10n');
      expect(config.baseLocale, 'de');
      expect(config.sourceDirs, ['lib', 'packages/ui/lib']);
      expect(config.exclude, containsAll(<String>['lib/legacy/**', '**/*.g.dart']));
      expect(config.isIgnoredKey('debug_menu'), isTrue);
      expect(config.untranslatedMinLetters, 5);
      expect(config.untranslatedAllow, ['Acme']);
      expect(config.todoMarker, 'XX ');
      expect(config.lengthRatio, 2.0);
      expect(config.lengthMinChars, 10);
      expect(config.hardcodedIgnore.single.pattern, '^Lorem');
      expect(config.requiredPlurals('en'), ['one', 'other', 'many']);
      expect(config.severityOf(CheckId.unusedKey), Severity.error);
      expect(config.severityOf(CheckId.rtlSmell), Severity.off);
      expect(config.failOn, Severity.warning);
    });

    test('rejects unknown options, checks and bad values', () {
      expect(() => Config.parse('formt: arb'), throwsFormatException);
      expect(() => Config.parse('format: po'), throwsFormatException);
      expect(() => Config.parse('severity: {nope: error}'), throwsFormatException);
      expect(() => Config.parse('severity: {unused_key: loud}'), throwsFormatException);
      expect(() => Config.parse('length: {ratio: big}'), throwsFormatException);
      expect(() => Config.parse('ignore_keys: ["("]'), throwsFormatException);
      expect(() => Config.parse('- a list'), throwsFormatException);
      expect(() => Config.parse('untranslated: {colour: red}'), throwsFormatException);
    });

    test('load returns defaults when the file is missing', () {
      expect(Config.load(p.join(Directory.systemTemp.path, 'nope.yaml')).sourceDirs, ['lib']);
    });
  });
}
