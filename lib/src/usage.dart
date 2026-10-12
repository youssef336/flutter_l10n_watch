import 'catalog.dart';
import 'dart_source.dart';
import 'project.dart';

/// A key referenced explicitly from code (a `tr` call, `LocaleKeys`, an
/// `AppLocalizations` getter, ...). It may or may not be defined.
class KeyReference {
  const KeyReference(this.key, this.file, this.line, this.how);

  final String key;
  final String file;
  final int line;

  /// Short description of the pattern, e.g. `'key'.tr()`.
  final String how;
}

/// A translation lookup whose key is built at runtime.
class DynamicReference {
  const DynamicReference(this.prefix, this.expression, this.file, this.line);

  /// Constant text before the first interpolation; empty when unknown.
  final String prefix;

  /// Source of the key expression, for the report.
  final String expression;
  final String file;
  final int line;
}

/// How the code uses translation keys.
class UsageIndex {
  UsageIndex();

  /// Explicit references, defined or not.
  final List<KeyReference> references = <KeyReference>[];

  /// Defined keys that appear in code in a way that is not a known lookup
  /// pattern (e.g. a string literal equal to the key stored in a map).
  final Set<String> loose = <String>{};

  final List<DynamicReference> dynamics = <DynamicReference>[];

  /// Literal offsets per file that are keys, not user-facing text.
  final Map<String, Set<int>> keyLiterals = <String, Set<int>>{};

  bool isKeyLiteral(String file, int start) => keyLiterals[file]?.contains(start) ?? false;
}

/// Members of the generated localizations class that are not messages.
const _nonMessageMembers = <String>{
  'localeName',
  'delegate',
  'supportedLocales',
  'localizationsDelegates',
  'of',
  'current',
  'load',
  'runtimeType',
  'toString',
  'hashCode',
  'noSuchMethod',
};

/// Scans every Dart source of [project] for key usages.
UsageIndex scanUsages(Project project) {
  final index = UsageIndex();
  final catalog = project.catalog;
  final known = <String>{...catalog.allKeys, ...catalog.parents};
  if (project.format == L10nFormat.arb) {
    for (final source in project.sources) {
      _scanArb(source, project, known, index);
    }
  } else {
    final constants = _localeKeyConstants(project, known);
    for (final source in project.sources) {
      _scanJson(source, project, known, constants, index);
    }
  }
  return index;
}

/// Maps `LocaleKeys` constant names to keys. Prefers the generated class;
/// otherwise derives names the way easy_localization's generator does
/// (dots and other separators become `_`).
Map<String, String> _localeKeyConstants(Project project, Set<String> known) {
  if (project.localeKeys.isNotEmpty) {
    return project.localeKeys;
  }
  final result = <String, String>{};
  for (final key in known) {
    result.putIfAbsent(constantNameOf(key), () => key);
  }
  return result;
}

/// The `LocaleKeys` constant easy_localization generates for [key].
String constantNameOf(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), '_');

String _alternation(Iterable<String> names) => names.map(RegExp.escape).join('|');

void _scanJson(
  DartSource source,
  Project project,
  Set<String> known,
  Map<String, String> constants,
  UsageIndex index,
) {
  final fns = _alternation(project.config.trFunctions);
  final afterCall = RegExp('^\\s*\\.\\s*(?:$fns)\\s*[(<]');
  final asFirstArg = RegExp('(?:^|[^\\w\$])(?:[\\w\$]+\\s*\\.\\s*)?($fns)\\s*\\(\\s*\$');
  final widgets = project.config.hardcodedWidgets.toSet();
  final keyLiterals = index.keyLiterals.putIfAbsent(source.path, () => <int>{});

  void reference(StringLiteral literal, String how) {
    keyLiterals.add(literal.start);
    final line = source.lineOf(literal.start);
    if (literal.interpolated) {
      index.dynamics.add(DynamicReference(
        literal.prefix,
        source.text.substring(literal.start, literal.end),
        source.path,
        line,
      ));
    } else {
      index.references.add(KeyReference(literal.value, source.path, line, how));
    }
  }

  for (final literal in source.literals) {
    if (afterCall.hasMatch(source.codeAfter(literal.end, 40))) {
      reference(literal, "'key'.tr()");
      continue;
    }
    if (asFirstArg.hasMatch(source.codeBefore(literal.start, 80))) {
      reference(literal, "tr('key')");
      continue;
    }
    final open = literal.enclosingOpen;
    if (open >= 0 && source.masked[open] == '(') {
      final close = source.closeOf(open);
      if (close >= 0 && afterCall.hasMatch(source.codeAfter(close + 1, 40))) {
        final callee = RegExp(r'([\w$]+)\s*$').firstMatch(source.codeBefore(open, 60))?[1];
        if (callee == null || widgets.contains(callee)) {
          reference(literal, "Text('key').tr()");
          continue;
        }
      }
    }
    if (!literal.interpolated && known.contains(literal.value)) {
      index.loose.add(literal.value);
      keyLiterals.add(literal.start);
    }
  }

  final className = RegExp.escape(project.config.localeKeysClass);
  for (final m
      in RegExp('\\b$className\\s*\\.\\s*([A-Za-z_\$][\\w\$]*)').allMatches(source.masked)) {
    final name = m[1]!;
    final key = constants[name] ?? name;
    index.references.add(KeyReference(
      key,
      source.path,
      source.lineOf(m.start),
      '${project.config.localeKeysClass}.$name',
    ));
  }

  // Lookups whose key is not a literal: tr(variable), variable.tr(), ...
  final calls = RegExp('(?:(\\.)\\s*|(?<![\\w\$.]))($fns)\\s*\\(');
  for (final m in calls.allMatches(source.masked)) {
    final open = m.end - 1;
    final first = source.argumentsOf(open)[r'$0'];
    final firstIsKey = first != null && _isKeyExpression(first, className);
    String? expression;
    if (m[1] == null) {
      expression = first == null || firstIsKey ? null : first;
    } else {
      final receiver = _receiverOf(source, m.start, className);
      if (receiver != null && !firstIsKey) {
        final functionForm = first != null && receiver.toLowerCase().endsWith('context');
        expression = functionForm ? first : receiver;
      }
    }
    if (expression != null) {
      index.dynamics.add(DynamicReference('', expression, source.path, source.lineOf(m.start)));
    }
  }
}

bool _isKeyExpression(String expression, String className) =>
    RegExp('^(r?[\'"]|$className\\s*\\.)').hasMatch(expression.trim());

/// The receiver of a `.tr(` call at [dot] when it is not a literal, a
/// `LocaleKeys` constant or a group that already holds a literal key.
String? _receiverOf(DartSource source, int dot, String className) {
  final before = source.codeBefore(dot, 200);
  final trimmed = before.trimRight();
  if (trimmed.isEmpty) {
    return null;
  }
  final last = trimmed[trimmed.length - 1];
  if (last == "'" || last == '"') {
    return null;
  }
  if (last == ')') {
    final closeAt = dot - (before.length - trimmed.length) - 1;
    final open = source.openOf(closeAt);
    if (open < 0) {
      return null;
    }
    final inner = source.text.substring(open + 1, closeAt);
    final innerMasked = source.masked.substring(open + 1, closeAt);
    if (RegExp('[\'"]').hasMatch(innerMasked) || RegExp('\\b$className\\s*\\.').hasMatch(inner)) {
      return null;
    }
    final callee = RegExp(r'([\w$.]+)\s*$').firstMatch(source.codeBefore(open, 80))?[1] ?? '';
    return '$callee(${inner.trim()})';
  }
  final chain = RegExp(r'([A-Za-z_$][\w$]*(?:\s*[!?]?\.\s*[A-Za-z_$][\w$]*)*)\s*[!]?$')
      .firstMatch(trimmed)?[1];
  if (chain == null || RegExp('^$className\\b').hasMatch(chain)) {
    return null;
  }
  return chain.replaceAll(RegExp(r'\s+'), '');
}

void _scanArb(DartSource source, Project project, Set<String> known, UsageIndex index) {
  final cls = RegExp.escape(project.arb.outputClass);
  final extra = project.config.arbAccessors.map(RegExp.escape);
  final accessor = <String>[
    '(?:$cls|S)\\s*\\.\\s*of\\s*\\(\\s*[^()]*\\)\\s*!?',
    'S\\s*\\.\\s*current',
    '(?:[\\w\$]+\\s*\\.\\s*)?l10n\\s*!?',
    'lookup$cls\\s*\\([^()]*\\)',
    ...extra,
  ].join('|');
  final aliases = <String>{};
  for (final m in RegExp('(?<![\\w\$.])([A-Za-z_\$][\\w\$]*)\\s*=\\s*(?:$accessor)\\s*[;,)]')
      .allMatches(source.masked)) {
    aliases.add(m[1]!);
  }
  for (final m
      in RegExp('\\b(?:$cls|S)\\s*\\??\\s+([A-Za-z_\$][\\w\$]*)\\b').allMatches(source.masked)) {
    aliases.add(m[1]!);
  }
  final patterns = <RegExp>[
    RegExp('(?:$accessor)\\s*\\.\\s*([A-Za-z_\$][\\w\$]*)'),
    if (aliases.isNotEmpty)
      RegExp('(?<![\\w\$.])(?:${_alternation(aliases)})\\s*!?\\s*\\.\\s*([A-Za-z_\$][\\w\$]*)'),
  ];
  final seen = <int>{};
  for (final pattern in patterns) {
    for (final m in pattern.allMatches(source.masked)) {
      final member = m[1]!;
      final at = m.start + m[0]!.length - member.length;
      if (_nonMessageMembers.contains(member) || !seen.add(at)) {
        continue;
      }
      index.references.add(KeyReference(member, source.path, source.lineOf(at), 'l10n.$member'));
    }
  }
  for (final m in RegExp(r'\.\s*([A-Za-z_$][\w$]*)').allMatches(source.masked)) {
    if (known.contains(m[1])) {
      index.loose.add(m[1]!);
    }
  }
}
