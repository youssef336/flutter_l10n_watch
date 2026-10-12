import 'package:flutter_l10n_watch/flutter_l10n_watch.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('finds JSON through pubspec assets and EasyLocalization fallbackLocale', () {
    final root = tempProject({
      'pubspec.yaml': '''
name: x
dependencies:
  easy_localization: any
flutter:
  assets:
    - res/strings/
''',
      'res/strings/de-DE.json': '{"a": "A"}',
      'res/strings/en-US.json': '{"a": "A"}',
      'lib/main.dart': "x() => EasyLocalization(fallbackLocale: Locale('en', 'US'));",
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final project = loadProject(root.path, Config());
    expect(project.format, L10nFormat.easyLocalization);
    expect(project.relative(project.catalog.directory), 'res/strings');
    expect(project.catalog.baseLocale, 'en-US');
  });

  test('plain JSON without easy_localization is the json format', () {
    final root = tempProject({
      'assets/i18n/en.json': '{"a": {"one": "x", "other": "y"}}',
      'assets/i18n/es.json': '{"a": {"one": "x", "other": "y"}}',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final project = loadProject(root.path, Config());
    expect(project.format, L10nFormat.json);
    expect(project.catalog.base.entries.keys, ['a.one', 'a.other']);
  });

  test('config overrides format, folder and base locale', () {
    final root = tempProject({
      'strings/en.json': '{"a": "A"}',
      'strings/fr.json': '{"a": "B"}',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final project = loadProject(
      root.path,
      Config(format: L10nFormat.easyLocalization, translationsDir: 'strings', baseLocale: 'fr'),
    );
    expect(project.format, L10nFormat.easyLocalization);
    expect(project.catalog.baseLocale, 'fr');
  });

  test('clear errors when nothing is found', () {
    final root = tempProject({'lib/main.dart': 'void main() {}'});
    addTearDown(() => root.deleteSync(recursive: true));
    expect(() => loadProject(root.path, Config()), throwsA(isA<ProjectException>()));
    expect(
      () => loadProject(root.path, Config(translationsDir: 'nope')),
      throwsA(isA<ProjectException>()),
    );
    expect(
      () => loadProject('${root.path}/missing', Config()),
      throwsA(isA<ProjectException>()),
    );
  });

  test('unknown base locale is an error', () {
    final root = tempProject({'assets/translations/en.json': '{}'});
    addTearDown(() => root.deleteSync(recursive: true));
    expect(
      () => loadProject(root.path, Config(baseLocale: 'ja')),
      throwsA(isA<ProjectException>()),
    );
  });

  test('skips excluded globs and files with a generated banner', () {
    final root = tempProject({
      'assets/translations/en.json': '{"a": "A"}',
      'lib/a.dart': "f() => Text('Visible');",
      'lib/b.g.dart': "f() => Text('Generated');",
      'lib/c.dart': "// GENERATED CODE - DO NOT MODIFY BY HAND\nf() => Text('Banner');",
      'lib/legacy/d.dart': "f() => Text('Legacy');",
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final project = loadProject(root.path, Config(exclude: ['lib/legacy/**']));
    expect(project.sources.map((s) => s.path), ['lib/a.dart']);
  });

  test('derives LocaleKeys names when the generated class is absent', () {
    final root = tempProject({
      'pubspec.yaml': 'name: x\ndependencies:\n  easy_localization: any\n',
      'assets/translations/en.json': '{"profile": {"edit": {"title": "Edit"}}, "a-b": "x"}',
      'lib/a.dart': 'f() => [LocaleKeys.profile_edit_title.tr(), LocaleKeys.a_b.tr()];',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final result = check(root.path);
    expect(of(result, CheckId.unusedKey), isEmpty);
    expect(of(result, CheckId.undefinedKey), isEmpty);
  });

  test('LocaleKeys pointing at a group marks its children as possibly used', () {
    final root = tempProject({
      'pubspec.yaml': 'name: x\ndependencies:\n  easy_localization: any\n',
      'assets/translations/en.json': '{"menu": {"home": "Home", "exit": "Exit"}}',
      'lib/a.dart': r"f(k) => '${LocaleKeys.menu}.$k'.tr();",
    });
    addTearDown(() => root.deleteSync(recursive: true));
    expect(of(check(root.path), CheckId.unusedKey), isEmpty);
  });
}
