import 'dart:convert';

import '../analyzer.dart';
import '../finding.dart';
import '../version.dart';

/// Output formats of `report` and `check`.
enum ReportFormat { text, markdown, json, github }

/// Renders [result] in [format]. [maxPerCheck] limits listed items per check
/// in the text and markdown formats (null lists everything).
String render(
  CheckResult result,
  ReportFormat format, {
  int? maxPerCheck = 15,
  bool color = false,
}) {
  switch (format) {
    case ReportFormat.text:
      return renderText(result, maxPerCheck: maxPerCheck, color: color);
    case ReportFormat.markdown:
      return renderMarkdown(result, maxPerCheck: maxPerCheck == null ? null : maxPerCheck * 4);
    case ReportFormat.json:
      return renderJson(result);
    case ReportFormat.github:
      return renderGithub(result);
  }
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

String _summaryLine(CheckResult result) {
  final errors = result.count(Severity.error);
  final warnings = result.count(Severity.warning);
  final info = result.count(Severity.info);
  return '${_plural(errors, 'error')} · ${_plural(warnings, 'warning')} · $info info';
}

String _header(CheckResult result) {
  final catalog = result.project.catalog;
  return 'l10n_watch $packageVersion · ${result.project.format.id} · '
      '${result.project.relative(catalog.directory)} · base ${catalog.baseLocale} · '
      '${_plural(catalog.locales.length, 'locale')} · '
      '${_plural(catalog.base.entries.length, 'key')} · '
      '${_plural(result.project.sources.length, 'Dart file')}';
}

String _location(Finding f) => f.file == null
    ? ''
    : f.line == null
        ? f.file!
        : '${f.file}:${f.line}';

/// Counts per value of [keyOf], largest first.
List<MapEntry<String, int>> _tally(Iterable<Finding> findings, String Function(Finding) keyOf) {
  final counts = <String, int>{};
  for (final f in findings) {
    counts.update(keyOf(f), (n) => n + 1, ifAbsent: () => 1);
  }
  return counts.entries.toList()
    ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
}

/// Short per-check overview lines shown above the item list.
List<String> _overview(String check, List<Finding> findings) {
  switch (check) {
    case CheckId.missingTranslation:
    case CheckId.untranslated:
    case CheckId.lengthRisk:
    case CheckId.placeholderMismatch:
    case CheckId.pluralForms:
      final perLocale = _tally(findings.where((f) => f.locale != null), (f) => f.locale!);
      if (perLocale.length < 2) {
        return const <String>[];
      }
      return <String>['by locale: ${perLocale.map((e) => '${e.key} ${e.value}').join(' · ')}'];
    case CheckId.hardcodedString:
      return _topFiles(findings);
    case CheckId.rtlSmell:
      final perRule = _tally(findings, (f) => f.message);
      return <String>[
        for (final e in perRule) '${e.value.toString().padLeft(4)}  ${e.key}',
        ..._topFiles(findings),
      ];
    default:
      return const <String>[];
  }
}

List<String> _topFiles(List<Finding> findings) {
  final perFile = _tally(findings, (f) => f.file ?? '?');
  return <String>[
    'top files:',
    for (final e in perFile.take(10)) '  ${e.value.toString().padLeft(4)}  ${e.key}',
    if (perFile.length > 10) '  … ${_plural(perFile.length - 10, 'more file')}',
  ];
}

/// Checks whose overview is enough unless every item was asked for.
bool _overviewOnly(String check, int? maxPerCheck) =>
    check == CheckId.rtlSmell && maxPerCheck != null;

const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _dim = '\x1B[2m';
const _colors = <Severity, String>{
  Severity.error: '\x1B[31m',
  Severity.warning: '\x1B[33m',
  Severity.info: '\x1B[36m',
};
const _icons = <Severity, String>{
  Severity.error: '✖',
  Severity.warning: '⚠',
  Severity.info: 'ℹ',
};

/// Human-readable terminal output.
String renderText(CheckResult result, {int? maxPerCheck = 15, bool color = false}) {
  String paint(String text, String code) => color ? '$code$text$_reset' : text;
  final out = StringBuffer()
    ..writeln(paint(_header(result), _dim))
    ..writeln();
  final groups = result.byCheck;
  if (groups.isEmpty) {
    out.writeln(paint('✔ No findings.', '\x1B[32m'));
    return out.toString();
  }
  groups.forEach((check, findings) {
    final severity = findings.first.severity;
    out.writeln(paint(
      '${_icons[severity]} ${CheckId.titles[check]} '
          '(${findings.length} ${severity.name}${findings.length == 1 ? '' : 's'}) [$check]',
      '$_bold${_colors[severity]}',
    ));
    for (final line in _overview(check, findings)) {
      out.writeln('  ${paint(line, _dim)}');
    }
    if (!_overviewOnly(check, maxPerCheck)) {
      final shown = maxPerCheck == null ? findings : findings.take(maxPerCheck);
      for (final f in shown) {
        final where = _location(f);
        final isCatalogFile = f.line == null;
        out.writeln(isCatalogFile || where.isEmpty
            ? '  ${f.message}'
            : '  ${paint(where, _dim)}  ${f.message}');
      }
      final hidden = findings.length - shown.length;
      if (hidden > 0) {
        out.writeln(paint('  … and $hidden more (use --all)', _dim));
      }
    }
    out.writeln();
  });
  final failed = result.failsAt(result.project.config.failOn);
  out.writeln(paint(
    '${failed ? '✖' : '✔'} ${_summaryLine(result)}',
    '$_bold${failed ? _colors[Severity.error] : '\x1B[32m'}',
  ));
  return out.toString();
}

String _mdEscape(String text) =>
    text.replaceAll('|', r'\|').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// GitHub-flavoured Markdown, for PR comments and job summaries.
String renderMarkdown(CheckResult result, {int? maxPerCheck = 60}) {
  final out = StringBuffer()
    ..writeln('## 🌍 Translation health')
    ..writeln()
    ..writeln('`${_header(result)}`')
    ..writeln()
    ..writeln('**${_summaryLine(result)}**')
    ..writeln();
  final groups = result.byCheck;
  if (groups.isEmpty) {
    out.writeln('✅ No findings.');
    return out.toString();
  }
  out
    ..writeln('| Check | Severity | Count |')
    ..writeln('|---|---|---:|');
  groups.forEach((check, findings) {
    out.writeln('| ${CheckId.titles[check]} (`$check`) | ${findings.first.severity.name} | '
        '${findings.length} |');
  });
  out.writeln();
  groups.forEach((check, findings) {
    out
      ..writeln('<details><summary><b>${CheckId.titles[check]}</b> (${findings.length})</summary>')
      ..writeln();
    final overview = _overview(check, findings);
    if (overview.isNotEmpty) {
      out
        ..writeln('```')
        ..writeln(overview.join('\n'))
        ..writeln('```')
        ..writeln();
    }
    if (!_overviewOnly(check, maxPerCheck)) {
      final shown = maxPerCheck == null ? findings : findings.take(maxPerCheck);
      for (final f in shown) {
        final where = f.line == null ? '' : '`${_location(f)}` ';
        out.writeln('- $where${_mdEscape(f.message)}');
      }
      final hidden = findings.length - shown.length;
      if (hidden > 0) {
        out.writeln('- … and $hidden more');
      }
    }
    out
      ..writeln()
      ..writeln('</details>')
      ..writeln();
  });
  return out.toString();
}

/// Machine-readable output with every finding.
String renderJson(CheckResult result) {
  final groups = result.byCheck;
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'tool': 'flutter_l10n_watch',
    'version': packageVersion,
    'project': result.stats,
    'summary': <String, Object?>{
      'errors': result.count(Severity.error),
      'warnings': result.count(Severity.warning),
      'info': result.count(Severity.info),
      'byCheck': <String, int>{
        for (final e in groups.entries) e.key: e.value.length,
      },
    },
    'findings': result.findings.map((f) => f.toJson()).toList(),
  });
}

String _ghData(String text) =>
    text.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');

String _ghProperty(String text) => _ghData(text).replaceAll(':', '%3A').replaceAll(',', '%2C');

/// GitHub Actions workflow commands: one annotation per finding.
String renderGithub(CheckResult result) {
  final out = StringBuffer();
  for (final f in result.findings) {
    final command = switch (f.severity) {
      Severity.error => 'error',
      Severity.warning => 'warning',
      _ => 'notice',
    };
    final props = <String>[
      if (f.file != null) 'file=${_ghProperty(f.file!)}',
      if (f.line != null) 'line=${f.line}',
      'title=${_ghProperty(f.check)}',
    ];
    out.writeln('::$command ${props.join(',')}::${_ghData(f.message)}');
  }
  out.writeln('l10n_watch: ${_summaryLine(result)}');
  return out.toString();
}
