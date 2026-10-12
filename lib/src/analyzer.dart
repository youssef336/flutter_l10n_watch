import 'catalog.dart';
import 'checks/catalog_checks.dart';
import 'checks/code_checks.dart';
import 'finding.dart';
import 'project.dart';
import 'usage.dart';

/// The outcome of one run.
class CheckResult {
  CheckResult(this.project, this.findings, this.usage);

  final Project project;

  /// Findings in report order (check, then locale, key, file, line).
  final List<Finding> findings;
  final UsageIndex usage;

  int count(Severity severity) => findings.where((f) => f.severity == severity).length;

  /// Findings grouped by check id, in [CheckId.all] order.
  Map<String, List<Finding>> get byCheck {
    final groups = <String, List<Finding>>{};
    for (final id in CheckId.all) {
      final list = findings.where((f) => f.check == id).toList();
      if (list.isNotEmpty) {
        groups[id] = list;
      }
    }
    return groups;
  }

  /// True when a finding is at least as serious as [threshold].
  bool failsAt(Severity threshold) =>
      threshold != Severity.off && findings.any((f) => f.severity.atLeast(threshold));

  Map<String, Object?> get stats => <String, Object?>{
        'format': project.format.id,
        'translationsDir': project.relative(project.catalog.directory),
        'baseLocale': project.catalog.baseLocale,
        'locales': project.catalog.locales.keys.toList(),
        'keys': project.catalog.base.entries.length,
        'dartFiles': project.sources.length,
        'references': usage.references.length,
      };
}

/// Runs every enabled check. [only] limits the run to those check ids.
CheckResult runChecks(Project project, {Set<String>? only}) {
  final config = project.config;
  final findings = <Finding>[];
  bool enabled(String id) =>
      config.severityOf(id) != Severity.off && (only == null || only.contains(id));

  void emit(
    String check,
    String message, {
    String? locale,
    String? key,
    String? file,
    int? line,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (!enabled(check)) {
      return;
    }
    findings.add(Finding(
      check: check,
      severity: config.severityOf(check),
      message: message,
      locale: locale,
      key: key,
      file: file,
      line: line,
      data: data,
    ));
  }

  final messages = MessageAnalyzer(project);
  runCatalogChecks(project, messages, emit);
  final usage = scanUsages(project);
  runKeyUsageChecks(project, usage, messages, emit);
  runHardcodedCheck(project, usage, emit);
  runRtlCheck(project, emit);

  final order = <String, int>{
    for (var i = 0; i < CheckId.all.length; i++) CheckId.all[i]: i,
  };
  int compareNullable(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null ? (b == null ? 0 : -1) : 1;
    }
    if (a is int && b is int) {
      return a.compareTo(b);
    }
    return '$a'.compareTo('$b');
  }

  findings.sort((a, b) {
    var c = order[a.check]!.compareTo(order[b.check]!);
    if (c != 0) {
      return c;
    }
    c = compareNullable(a.locale, b.locale);
    if (c != 0) {
      return c;
    }
    c = compareNullable(a.file, b.file);
    if (c != 0) {
      return c;
    }
    c = compareNullable(a.line, b.line);
    if (c != 0) {
      return c;
    }
    return compareNullable(a.key, b.key);
  });
  return CheckResult(project, findings, usage);
}

/// Locales sorted with the base first, for display.
List<String> displayLocales(Catalog catalog) => <String>[
      catalog.baseLocale,
      ...catalog.locales.keys.where((l) => l != catalog.baseLocale),
    ];
