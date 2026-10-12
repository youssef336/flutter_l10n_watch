import 'package:flutter_l10n_watch/flutter_l10n_watch.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late CheckResult result;

  setUpAll(() => result = check(fixture('easy_app')));

  test('detects the setup', () {
    final project = result.project;
    expect(project.format, L10nFormat.easyLocalization);
    expect(project.catalog.baseLocale, 'en');
    expect(project.catalog.locales.keys, ['ar', 'en', 'fr']);
    expect(project.localeKeys['cart_title'], 'cart.title');
    // The generated LocaleKeys file is parsed but not scanned.
    expect(project.sources.map((s) => s.path), ['lib/home.dart', 'lib/main.dart']);
  });

  test('missing and extra keys', () {
    expect(keysOf(result, CheckId.missingTranslation), ['ar:cart.checkout']);
    expect(keysOf(result, CheckId.extraTranslation), ['ar:old_key']);
  });

  test('empty values', () {
    expect(keysOf(result, CheckId.emptyValue), ['ar:status_active']);
  });

  test('untranslated: identical values and TODO markers, short tokens ignored', () {
    final keys = keysOf(result, CheckId.untranslated);
    expect(keys, containsAll(<String>['ar:unused_thing', 'ar:brand_line', 'fr:cart.empty']));
    expect(keys, isNot(contains('ar:ok')));
    expect(of(result, CheckId.untranslated).firstWhere((f) => f.key == 'cart.empty').message,
        contains('marked'));
  });

  test('brand allow list silences untranslated', () {
    final quiet = check(
      fixture('easy_app'),
      config: Config.parse('untranslated: {allow: [shop, pro]}'),
      only: {CheckId.untranslated},
    );
    expect(keysOf(quiet, CheckId.untranslated), isNot(contains('ar:brand_line')));
  });

  test('placeholder mismatch: named and positional', () {
    final findings = of(result, CheckId.placeholderMismatch);
    expect(findings.map((f) => f.key), ['greeting', 'items_count']);
    expect(findings.first.message, contains('{user}'));
    expect(findings.last.data['expected'], '{}×2');
  });

  test('Arabic plural groups need six forms', () {
    final finding = of(result, CheckId.pluralForms).single;
    expect(finding.key, 'apples');
    expect(finding.data['missing'], ['zero', 'two', 'few', 'many']);
  });

  test('ICU syntax in easy_localization JSON is invalid', () {
    expect(
        keysOf(result, CheckId.invalidMessage), ['ar:icu_label', 'en:icu_label', 'fr:icu_label']);
  });

  test('undefined keys from tr calls and stale LocaleKeys', () {
    final findings = of(result, CheckId.undefinedKey);
    expect(findings.map((f) => f.key), ['missing_key', 'removed_key']);
    expect(findings.first.file, 'lib/home.dart');
    expect(findings.first.line, greaterThan(0));
  });

  test('unused keys honour links, loose literals, groups and dynamic prefixes', () {
    final unused = of(result, CheckId.unusedKey).map((f) => f.key).toList();
    expect(unused, ['icu_label', 'unused_thing']);
    // help_text is only used through "@:help_text", brand_line only as a literal,
    // status_* only through 'status_$status'.tr().
  });

  test('dynamic keys are reported separately', () {
    final dynamics = of(result, CheckId.dynamicKey);
    final prefixed = dynamics.firstWhere((f) => f.data['prefix'] == 'status_');
    expect(prefixed.data['possiblyUsed'], ['status_active', 'status_paused']);
    expect(dynamics.where((f) => f.data['prefix'] == ''), hasLength(2));
  });

  test('length risk', () {
    final finding = of(result, CheckId.lengthRisk).single;
    expect(finding.key, 'long_label');
    expect(finding.data['ratio'], greaterThan(1.6));
  });

  test('hardcoded strings', () {
    final texts = of(result, CheckId.hardcodedString).map((f) => f.data['text']).toList();
    expect(texts, [
      'Hardcoded hello',
      'Total: {…} items',
      'Type here',
      'Tooltip words',
      'Span words',
    ]);
  });

  test('RTL smells skip symmetric values and gradients', () {
    final codes = of(result, CheckId.rtlSmell).map((f) => f.data['code']).toList();
    expect(codes, [
      'EdgeInsets.only',
      'EdgeInsets.fromLTRB',
      'Alignment.centerLeft',
      'TextDirection.ltr',
      'TextAlign.right',
      'Positioned',
    ]);
  });

  test('severities and exit decision', () {
    expect(result.count(Severity.error), 8);
    expect(result.failsAt(Severity.error), isTrue);
  });

  test('severity off and ignore_keys remove findings', () {
    final quiet = check(
      fixture('easy_app'),
      config: Config.parse('''
ignore_keys: ['^icu_', '^cart\\.']
severity:
  rtl_smell: off
  placeholder_mismatch: warning
'''),
    );
    expect(of(quiet, CheckId.rtlSmell), isEmpty);
    expect(of(quiet, CheckId.missingTranslation), isEmpty);
    expect(of(quiet, CheckId.invalidMessage), isEmpty);
    expect(of(quiet, CheckId.placeholderMismatch).first.severity, Severity.warning);
  });
}
