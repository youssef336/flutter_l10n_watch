/// Translation health checker for Flutter projects.
///
/// Use the `l10n_watch` executable, or call [loadProject] and [runChecks]
/// from Dart and render the result with [render].
library;

export 'src/analyzer.dart' show CheckResult, runChecks;
export 'src/catalog.dart' show Catalog, Entry, EntryKind, L10nFormat, LocaleFile;
export 'src/cli.dart' show ExitCode, runCli;
export 'src/config.dart' show Config, configFileName;
export 'src/finding.dart' show CheckId, Finding, Severity;
export 'src/fixer.dart' show FileFix, fixCatalog;
export 'src/message.dart' show ChoiceArg, MessageInfo, analyzeIcu, analyzeSimple;
export 'src/project.dart' show ArbSettings, Project, ProjectException, loadProject;
export 'src/report/reporters.dart' show ReportFormat, render;
export 'src/version.dart' show packageVersion;
