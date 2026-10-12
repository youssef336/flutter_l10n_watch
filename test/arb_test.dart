import 'package:flutter_l10n_watch/flutter_l10n_watch.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late CheckResult result;

  setUpAll(() => result = check(fixture('arb_app')));

  test('detects gen_l10n from l10n.yaml and skips the generated class', () {
    final project = result.project;
    expect(project.format, L10nFormat.arb);
    expect(project.catalog.baseLocale, 'en');
    expect(project.arb.outputClass, 'AppLocalizations');
    expect(project.sources.map((s) => s.path), ['lib/main.dart']);
  });

  test('missing, untranslated and placeholder mismatch', () {
    expect(keysOf(result, CheckId.missingTranslation), ['ar:saveButton']);
    expect(keysOf(result, CheckId.untranslated), ['ar:appTitle']);
    expect(keysOf(result, CheckId.placeholderMismatch), ['ar:hello']);
  });

  test('ICU plural branches: =0/=1 count as zero/one', () {
    final finding = of(result, CheckId.pluralForms).single;
    expect(finding.locale, 'ar');
    expect(finding.data['missing'], ['two', 'few', 'many']);
  });

  test('malformed ICU is invalid and skipped by other comparisons', () {
    expect(keysOf(result, CheckId.invalidMessage), ['ar:genderMsg']);
    expect(of(result, CheckId.lengthRisk), isEmpty);
  });

  test('metadata checks on the template', () {
    expect(of(result, CheckId.arbMetadata).map((f) => f.key),
        ['declaredUnused', 'ghost', 'undeclared']);
  });

  test('getter usage: direct, extension, alias and typed field', () {
    expect(keysOf(result, CheckId.unusedKey), ['en:unusedMessage']);
    final undefined = of(result, CheckId.undefinedKey).single;
    expect(undefined.key, 'doesNotExist');
    expect(undefined.file, 'lib/main.dart');
  });

  test('hardcoded strings', () {
    expect(of(result, CheckId.hardcodedString).single.data['text'], 'Hardcoded ARB text');
    expect(of(result, CheckId.rtlSmell), isEmpty);
  });

  test('a missing "other" branch is invalid', () {
    final root = tempProject({
      'l10n.yaml': 'arb-dir: lib/l10n\n',
      'lib/l10n/app_en.arb': '{"n": "{count, plural, one{x} other{y}}"}',
      'lib/l10n/app_fr.arb': '{"n": "{count, plural, one{x} many{y}}"}',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final r = check(root.path);
    expect(of(r, CheckId.invalidMessage).single.message, contains('no "other"'));
  });

  test('intl_utils (flutter_intl) uses the S class and intl_ files', () {
    final root = tempProject({
      'pubspec.yaml': 'name: x\nflutter_intl:\n  enabled: true\n',
      'lib/l10n/intl_en.arb': '{"title": "Title", "unused": "Unused"}',
      'lib/l10n/intl_de.arb': '{"title": "Titel", "unused": "Unbenutzt"}',
      'lib/a.dart': 'f(c) => S.of(c).title + S.current.title;',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final r = check(root.path);
    expect(r.project.arb.outputClass, 'S');
    expect(keysOf(r, CheckId.unusedKey), ['en:unused']);
  });
}
