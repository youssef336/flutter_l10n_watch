import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'analyzer.dart';
import 'config.dart';
import 'finding.dart';
import 'fixer.dart';
import 'project.dart';
import 'report/reporters.dart';
import 'version.dart';

/// Exit codes.
abstract final class ExitCode {
  static const ok = 0;
  static const findings = 1;
  static const usage = 2;
}

const _sampleConfig = '''
# l10n_watch configuration. Every option is optional.

# auto | easy_localization | arb | json
format: auto
# translations_dir: assets/translations
# base_locale: en

source_dirs: [lib]
# Extra globs to skip (generated files are skipped already).
exclude: []

# Keys (regex) that every check ignores.
ignore_keys: []

untranslated:
  min_letters: 3
  # Words that are the same in every language (brand names, ...).
  allow: []
  ignore_keys: []

length:
  ratio: 1.6
  min_chars: 20

hardcoded:
  # Literals matching these regexes are not reported.
  ignore: []

# error | warning | info | off, per check.
severity:
  missing_translation: error
  placeholder_mismatch: error
  undefined_key: error
  unused_key: warning
  hardcoded_string: warning
  rtl_smell: info

# check exits with 1 when a finding is at least this severe.
fail_on: error
''';

ArgParser _commonOptions(ArgParser parser) => parser
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command options.')
  ..addOption('project', abbr: 'p', help: 'Flutter project folder.', defaultsTo: '.')
  ..addOption('config', abbr: 'c', help: 'Config file (default: <project>/$configFileName).');

ArgParser _reportOptions(ArgParser parser, {required String defaultFormat}) => parser
  ..addOption(
    'format',
    abbr: 'f',
    allowed: ReportFormat.values.map((f) => f.name),
    defaultsTo: defaultFormat,
    help: 'Output format.',
  )
  ..addOption('output', abbr: 'o', help: 'Write the report to this file instead of stdout.')
  ..addOption('checks', help: 'Comma-separated check ids to run (default: all).')
  ..addFlag('all', negatable: false, help: 'List every finding (text/markdown).')
  ..addFlag('color', defaultsTo: null, help: 'Force or disable colors in text output.');

ArgParser buildParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag('version', negatable: false, help: 'Print the version.');
  _reportOptions(_commonOptions(parser.addCommand('check')), defaultFormat: 'text').addOption(
    'fail-on',
    allowed: <String>['error', 'warning', 'info'],
    help: 'Exit with 1 when a finding is at least this severe (default: config fail_on).',
  );
  _reportOptions(_commonOptions(parser.addCommand('report')), defaultFormat: 'text');
  _commonOptions(parser.addCommand('fix'))
    ..addFlag('sort', negatable: false, help: 'Sort keys in every locale file.')
    ..addFlag(
      'add-missing',
      negatable: false,
      help: 'Copy missing keys from the base locale, prefixed with the TODO marker.',
    )
    ..addOption('todo-marker', help: 'Prefix for added values (default: config, "TODO: ").')
    ..addFlag('dry-run', negatable: false, help: 'Show what would change, write nothing.');
  _commonOptions(parser.addCommand('init'));
  return parser;
}

String _usage(ArgParser parser) => '''
Translation health checker for Flutter projects (easy_localization, gen_l10n ARB, JSON).

Usage: l10n_watch <command> [options]

Commands:
  check    Run every check; exit 1 when a finding reaches fail_on (default: error).
  report   Same checks, always exit 0. Use --format markdown|json|github.
  fix      --sort and/or --add-missing. Never changes anything without a flag.
  init     Write a commented $configFileName.

Run "l10n_watch <command> --help" for command options.

Checks: ${CheckId.all.join(', ')}
''';

/// Runs the CLI and returns the exit code. Output goes to [out] / [err].
int runCli(List<String> arguments, {StringSink? out, StringSink? err}) {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = buildParser();
  ArgResults args;
  try {
    args = parser.parse(arguments.isEmpty ? <String>['check'] : arguments);
  } on FormatException catch (e) {
    stderrSink
      ..writeln(e.message)
      ..writeln()
      ..write(_usage(parser));
    return ExitCode.usage;
  }
  if (args.flag('version')) {
    stdoutSink.writeln('l10n_watch $packageVersion');
    return ExitCode.ok;
  }
  final command = args.command;
  if (args.flag('help') || command == null) {
    stdoutSink.write(_usage(parser));
    return command == null && !args.flag('help') ? ExitCode.usage : ExitCode.ok;
  }
  if (command.flag('help')) {
    stdoutSink.writeln(parser.commands[command.name]!.usage);
    return ExitCode.ok;
  }
  if (command.rest.isNotEmpty) {
    stderrSink.writeln('Unexpected arguments: ${command.rest.join(' ')}');
    return ExitCode.usage;
  }

  final root = p.normalize(p.absolute(command.option('project')!));
  final configPath = command.option('config') ?? p.join(root, configFileName);

  if (command.name == 'init') {
    final file = File(configPath);
    if (file.existsSync()) {
      stderrSink.writeln('$configPath already exists.');
      return ExitCode.usage;
    }
    file.writeAsStringSync(_sampleConfig);
    stdoutSink.writeln('Wrote $configPath');
    return ExitCode.ok;
  }

  final Config config;
  final Project project;
  try {
    if (command.option('config') != null && !File(configPath).existsSync()) {
      throw FormatException('Config file not found: $configPath');
    }
    config = Config.load(configPath);
    project = loadProject(root, config);
  } on FormatException catch (e) {
    stderrSink.writeln('Config error: ${e.message}');
    return ExitCode.usage;
  } on ProjectException catch (e) {
    stderrSink.writeln(e.message);
    return ExitCode.usage;
  }

  if (command.name == 'fix') {
    return _fix(command, project, stdoutSink, stderrSink);
  }

  Set<String>? only;
  final checks = command.option('checks');
  if (checks != null) {
    only = checks.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toSet();
    final unknown = only.difference(CheckId.all.toSet());
    if (unknown.isNotEmpty) {
      stderrSink
          .writeln('Unknown check(s): ${unknown.join(', ')}. Known: ${CheckId.all.join(', ')}');
      return ExitCode.usage;
    }
  }
  final result = runChecks(project, only: only);
  final format = ReportFormat.values.byName(command.option('format')!);
  final output = command.option('output');
  final colorFlag = command.wasParsed('color') ? command.flag('color') : null;
  final color = output == null &&
      (colorFlag ?? (out == null && stdout.hasTerminal && stdout.supportsAnsiEscapes));
  final rendered = render(
    result,
    format,
    maxPerCheck: command.flag('all') ? null : 15,
    color: color,
  );
  if (output != null) {
    File(output).writeAsStringSync(rendered);
    stdoutSink.writeln('Report written to $output');
  } else {
    stdoutSink.write(rendered);
  }
  if (command.name == 'report') {
    return ExitCode.ok;
  }
  final failOnRaw = command.option('fail-on');
  final failOn = failOnRaw == null ? config.failOn : Severity.parse(failOnRaw);
  return result.failsAt(failOn) ? ExitCode.findings : ExitCode.ok;
}

int _fix(ArgResults command, Project project, StringSink out, StringSink err) {
  final sort = command.flag('sort');
  final addMissing = command.flag('add-missing');
  if (!sort && !addMissing) {
    err.writeln('Nothing to do: pass --sort and/or --add-missing.');
    return ExitCode.usage;
  }
  final dryRun = command.flag('dry-run');
  final List<FileFix> fixes;
  try {
    fixes = fixCatalog(
      project,
      sort: sort,
      addMissing: addMissing,
      dryRun: dryRun,
      todoMarker: command.option('todo-marker'),
    );
  } on ProjectException catch (e) {
    err.writeln(e.message);
    return ExitCode.usage;
  }
  if (fixes.isEmpty) {
    out.writeln('Nothing to change.');
    return ExitCode.ok;
  }
  for (final fix in fixes) {
    final parts = <String>[
      if (fix.added.isNotEmpty) 'added ${fix.added.length} key${fix.added.length == 1 ? '' : 's'}',
      if (fix.sorted) 'sorted',
    ];
    out.writeln('${dryRun ? 'would update' : 'updated'} ${fix.path}: ${parts.join(', ')}');
  }
  return ExitCode.ok;
}
