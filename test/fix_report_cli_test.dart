import 'dart:convert';
import 'dart:io';

import 'package:flutter_l10n_watch/flutter_l10n_watch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('reporters', () {
    late CheckResult result;
    setUpAll(() => result = check(fixture('easy_app')));

    test('text', () {
      final text = render(result, ReportFormat.text, maxPerCheck: 1);
      expect(text, contains('easy_localization · assets/translations · base en'));
      expect(text, contains('[missing_translation]'));
      expect(text, contains('… and'));
      expect(text, contains('8 errors'));
      expect(text, isNot(contains('\x1B[')));
      expect(render(result, ReportFormat.text, color: true), contains('\x1B['));
    });

    test('markdown', () {
      final md = render(result, ReportFormat.markdown);
      expect(md, contains('| Check | Severity | Count |'));
      expect(md, contains('<details><summary><b>Missing translations</b> (1)</summary>'));
      expect(md, contains('`lib/home.dart:'));
    });

    test('json', () {
      final json = jsonDecode(render(result, ReportFormat.json)) as Map<String, dynamic>;
      expect(json['summary'], containsPair('errors', 8));
      expect((json['project'] as Map)['format'], 'easy_localization');
      expect(json['findings'], hasLength(result.findings.length));
    });

    test('github annotations', () {
      final gh = render(result, ReportFormat.github);
      expect(gh, contains('::error file=lib/home.dart,line='));
      expect(gh, contains('title=undefined_key::'));
      expect(gh, contains('::notice '));
      expect(gh.trim().split('\n').last, startsWith('l10n_watch: 8 errors'));
    });

    test('empty result', () {
      final root = tempProject({
        'assets/translations/en.json': '{"a": "Hello there"}',
        'assets/translations/de.json': '{"a": "Hallo du"}',
        'lib/a.dart': "f() => 'a'.tr();",
      });
      addTearDown(() => root.deleteSync(recursive: true));
      final clean = check(root.path);
      expect(clean.findings, isEmpty);
      expect(render(clean, ReportFormat.text), contains('No findings'));
      expect(render(clean, ReportFormat.markdown), contains('No findings'));
    });
  });

  group('fix', () {
    late Directory root;
    setUp(() => root = copyFixture('easy_app'));
    tearDown(() => root.deleteSync(recursive: true));

    String read(String locale) =>
        File(p.join(root.path, 'assets/translations/$locale.json')).readAsStringSync();

    test('does nothing without flags', () {
      final project = loadProject(root.path, Config());
      expect(fixCatalog(project, sort: false, addMissing: false, dryRun: false), isEmpty);
    });

    test('dry run writes nothing', () {
      final before = read('ar');
      final fixes = fixCatalog(
        loadProject(root.path, Config()),
        sort: true,
        addMissing: true,
        dryRun: true,
      );
      expect(fixes.map((f) => f.locale), contains('ar'));
      expect(read('ar'), before);
    });

    test('adds missing keys with a TODO marker and sorts', () {
      final fixes = fixCatalog(
        loadProject(root.path, Config()),
        sort: true,
        addMissing: true,
        dryRun: false,
      );
      final ar = fixes.firstWhere((f) => f.locale == 'ar');
      expect(ar.added, ['cart.checkout']);
      final json = jsonDecode(read('ar')) as Map<String, dynamic>;
      expect((json['cart'] as Map)['checkout'], 'TODO: Proceed to checkout');
      expect(json.keys.toList(), [...json.keys]..sort());
      expect(read('ar'), endsWith('}\n'));
      // The TODO marker keeps the key visible as untranslated.
      final after = check(root.path);
      expect(of(after, CheckId.missingTranslation), isEmpty);
      expect(keysOf(after, CheckId.untranslated), contains('ar:cart.checkout'));
      // Running again changes nothing.
      expect(
        fixCatalog(loadProject(root.path, Config()), sort: true, addMissing: true, dryRun: false),
        isEmpty,
      );
    });

    test('ARB sort keeps @@locale first and metadata after its message', () {
      final arb = copyFixture('arb_app');
      addTearDown(() => arb.deleteSync(recursive: true));
      fixCatalog(loadProject(arb.path, Config()), sort: true, addMissing: true, dryRun: false);
      final en = jsonDecode(File(p.join(arb.path, 'lib/l10n/app_en.arb')).readAsStringSync())
          as Map<String, dynamic>;
      final keys = en.keys.toList();
      expect(keys.first, '@@locale');
      expect(keys.indexOf('@hello'), keys.indexOf('hello') + 1);
      expect(keys.last, '@ghost');
      final ar = jsonDecode(File(p.join(arb.path, 'lib/l10n/app_ar.arb')).readAsStringSync())
          as Map<String, dynamic>;
      expect(ar['saveButton'], 'TODO: Save');
    });

    test('refuses to rewrite unparsable files', () {
      File(p.join(root.path, 'assets/translations/fr.json')).writeAsStringSync('{');
      expect(
        () => fixCatalog(loadProject(root.path, Config()),
            sort: true, addMissing: false, dryRun: false),
        throwsA(isA<ProjectException>()),
      );
    });
  });

  group('cli', () {
    (int, String, String) run(List<String> args) {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = runCli(args, out: out, err: err);
      return (code, out.toString(), err.toString());
    }

    test('check exits 1 on errors, 0 when only below fail-on', () {
      expect(run(['check', '-p', fixture('easy_app')]).$1, ExitCode.findings);
      expect(run(['check', '-p', fixture('easy_app'), '--checks', 'rtl_smell']).$1, ExitCode.ok);
      expect(
        run(['check', '-p', fixture('easy_app'), '--checks', 'rtl_smell', '--fail-on', 'info']).$1,
        ExitCode.findings,
      );
    });

    test('report always exits 0 and supports formats', () {
      final (code, out, _) = run(['report', '-p', fixture('arb_app'), '-f', 'json']);
      expect(code, ExitCode.ok);
      expect(jsonDecode(out), isA<Map<String, dynamic>>());
    });

    test('writes to --output', () {
      final dir = Directory.systemTemp.createTempSync('l10n_watch_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = p.join(dir.path, 'r.md');
      final (code, out, _) =
          run(['report', '-p', fixture('arb_app'), '-f', 'markdown', '-o', file]);
      expect(code, ExitCode.ok);
      expect(out, contains('Report written'));
      expect(File(file).readAsStringSync(), contains('Translation health'));
    });

    test('usage errors exit 2', () {
      expect(run(['check', '--checks', 'nope', '-p', fixture('easy_app')]).$1, ExitCode.usage);
      expect(run(['explode']).$1, ExitCode.usage);
      expect(run(['check', '-p', '/definitely/not/here']).$1, ExitCode.usage);
      expect(run(['check', '-p', fixture('easy_app'), '-c', '/nope.yaml']).$1, ExitCode.usage);
      expect(run(['fix', '-p', fixture('easy_app')]).$1, ExitCode.usage);
    });

    test('bad config is reported', () {
      final root = copyFixture('easy_app');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, configFileName)).writeAsStringSync('severity: {bogus: error}');
      final (code, _, err) = run(['check', '-p', root.path]);
      expect(code, ExitCode.usage);
      expect(err, contains('unknown check "bogus"'));
    });

    test('version, help and default command', () {
      expect(run(['--version']).$2, contains(packageVersion));
      expect(run(['--help']).$2, contains('Commands:'));
      expect(run(['check', '--help']).$2, contains('--fail-on'));
    });

    test('init writes a config once, and the sample parses', () {
      final root = Directory.systemTemp.createTempSync('l10n_watch_');
      addTearDown(() => root.deleteSync(recursive: true));
      expect(run(['init', '-p', root.path]).$1, ExitCode.ok);
      final written = File(p.join(root.path, configFileName)).readAsStringSync();
      expect(() => Config.parse(written), returnsNormally);
      expect(run(['init', '-p', root.path]).$1, ExitCode.usage);
    });

    test('fix --dry-run lists changes', () {
      final root = copyFixture('easy_app');
      addTearDown(() => root.deleteSync(recursive: true));
      final (code, out, _) = run(['fix', '-p', root.path, '--add-missing', '--dry-run']);
      expect(code, ExitCode.ok);
      expect(out, contains('would update assets/translations/ar.json: added 1 key'));
    });
  });
}
