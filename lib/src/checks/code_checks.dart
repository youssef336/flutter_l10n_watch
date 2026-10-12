import '../catalog.dart';
import '../dart_source.dart';
import '../finding.dart';
import '../project.dart';
import '../usage.dart';
import 'catalog_checks.dart';

/// Unused, undefined and dynamic keys.
void runKeyUsageChecks(
  Project project,
  UsageIndex usage,
  MessageAnalyzer messages,
  Emit emit,
) {
  final catalog = project.catalog;
  final config = project.config;
  final defined = catalog.allKeys;
  final groups = <String>{
    for (final file in catalog.locales.values)
      for (final entry in file.entries.values)
        if (entry.kind != EntryKind.text) entry.key,
  };
  final used = <String>{...usage.loose};
  final prefixes = <String>{};

  // Keys pulled in by easy_localization links (`@:other.key`).
  for (final file in catalog.locales.values) {
    for (final entry in file.entries.values) {
      used.addAll(messages.of(entry).links);
    }
  }

  final reported = <String>{};
  for (final reference in usage.references) {
    final key = reference.key;
    if (defined.contains(key)) {
      used.add(key);
      continue;
    }
    if (catalog.parents.contains(key)) {
      prefixes.add('$key.');
      continue;
    }
    final dot = key.lastIndexOf('.');
    if (dot > 0 && groups.contains(key.substring(0, dot))) {
      used.add(key.substring(0, dot));
      continue;
    }
    if (config.isIgnoredKey(key) || !reported.add('$key@${reference.file}:${reference.line}')) {
      continue;
    }
    emit(
      CheckId.undefinedKey,
      '"$key" is used (${reference.how}) but not defined in ${catalog.baseLocale}',
      key: key,
      file: reference.file,
      line: reference.line,
    );
  }

  final baseKeys = catalog.base.entries.keys.where((k) => !config.isIgnoredKey(k)).toList();
  final unusedKeys = baseKeys.where((k) => !used.contains(k)).toList();
  final viaPrefix = <String>{};
  for (final key in unusedKeys) {
    if (prefixes.any(key.startsWith)) {
      viaPrefix.add(key);
    }
  }

  for (final ref in usage.dynamics) {
    if (ref.prefix.isEmpty) {
      emit(
        CheckId.dynamicKey,
        'key computed at runtime: ${_clip(ref.expression)} '
        '(unused keys may include keys looked up here)',
        file: ref.file,
        line: ref.line,
        data: <String, Object?>{'expression': ref.expression, 'prefix': ''},
      );
      continue;
    }
    final matches = unusedKeys.where((k) => k.startsWith(ref.prefix)).toList();
    viaPrefix.addAll(matches);
    final allMatches = baseKeys.where((k) => k.startsWith(ref.prefix)).length;
    emit(
      CheckId.dynamicKey,
      '${_clip(ref.expression)} → prefix "${ref.prefix}" matches $allMatches '
      'key${allMatches == 1 ? '' : 's'}${matches.isEmpty ? '' : ' (${matches.length} otherwise unused)'}',
      file: ref.file,
      line: ref.line,
      data: <String, Object?>{
        'expression': ref.expression,
        'prefix': ref.prefix,
        'matches': allMatches,
        'possiblyUsed': matches,
      },
    );
  }

  final relative = project.relative(catalog.base.path);
  for (final key in unusedKeys) {
    if (viaPrefix.contains(key)) {
      continue;
    }
    emit(
      CheckId.unusedKey,
      '"$key" is never referenced in ${config.sourceDirs.join(', ')}',
      locale: catalog.baseLocale,
      key: key,
      file: relative,
    );
  }
}

final _letter = RegExp(r'\p{L}', unicode: true);
final _ignoreComment = RegExp(r'l10n[-_]ignore|ignore:\s*hardcoded');

/// Hardcoded user-facing strings in widget text and common text arguments.
void runHardcodedCheck(Project project, UsageIndex usage, Emit emit) {
  final config = project.config;
  final widgets = config.hardcodedWidgets.toSet();
  final plainArgs = config.hardcodedArgs.where((a) => !a.contains('.')).toSet();
  final qualifiedArgs = config.hardcodedArgs.where((a) => a.contains('.')).toSet();
  final defined = project.catalog.allKeys;
  final namedBefore = RegExp(r'(?:^|[,(\s])([A-Za-z_]\w*)\s*:\s*$');
  final calleeBefore =
      RegExp(r'(?:^|[^\w$.])([A-Za-z_$][\w$]*)(?:\s*\.\s*([A-Za-z_$][\w$]*))?\s*$');

  for (final source in project.sources) {
    for (final literal in source.literals) {
      if (usage.isKeyLiteral(source.path, literal.start)) {
        continue;
      }
      final open = literal.enclosingOpen;
      if (open < 0 || source.masked[open] != '(') {
        continue;
      }
      final callee = calleeBefore.firstMatch(source.codeBefore(open, 80));
      final calleeName = callee == null
          ? null
          : callee[2] != null && RegExp('^[A-Z]').hasMatch(callee[2]!)
              ? callee[2]
              : callee[1];
      String? context;
      final named = namedBefore.firstMatch(source.codeBefore(literal.start, 80))?[1];
      if (named != null) {
        if (plainArgs.contains(named)) {
          context = '$named:';
        } else if (calleeName != null && qualifiedArgs.contains('$calleeName.$named')) {
          context = '$calleeName($named:)';
        }
      } else if (calleeName != null && widgets.contains(calleeName)) {
        final firstArgStart = source.masked.substring(open + 1).indexOf(RegExp(r'\S')) + open + 1;
        if (firstArgStart == literal.start || _isRawStart(source, firstArgStart, literal)) {
          context = '$calleeName()';
        }
      }
      if (context == null) {
        continue;
      }
      final visible = literal.value.replaceAll(interpolationMarker, '{…}').trim();
      if (_letter.allMatches(literal.value).length < 2 ||
          defined.contains(literal.value) ||
          config.hardcodedIgnore.any((r) => r.hasMatch(visible)) ||
          _ignoreComment.hasMatch(source.lineText(literal.start))) {
        continue;
      }
      emit(
        CheckId.hardcodedString,
        '${_clip(visible)} in $context',
        file: source.path,
        line: source.lineOf(literal.start),
        data: <String, Object?>{'text': visible, 'context': context},
      );
    }
  }
}

bool _isRawStart(DartSource source, int at, StringLiteral literal) =>
    at + 1 == literal.start && source.text[at] == 'r';

class _RtlRule {
  const _RtlRule(this.pattern, this.suggest, {this.args, this.symmetric, this.skipAfter});

  final RegExp pattern;
  final String Function(Match match) suggest;

  /// Named arguments that make a call direction-dependent.
  final Set<String>? args;

  /// Argument pairs that, when equal, make the call direction-neutral.
  final List<(String, String)>? symmetric;

  /// Skip a match right after this code (e.g. gradient `begin:`).
  final RegExp? skipAfter;
}

final _rtlRules = <_RtlRule>[
  _RtlRule(
    RegExp(r'\bTextDirection\s*\.\s*(ltr|rtl)\b'),
    (m) => 'TextDirection.${m[1]} is hardcoded; let Directionality decide',
  ),
  _RtlRule(
    RegExp(r'\bEdgeInsets\s*\.\s*only\s*\('),
    (m) => 'EdgeInsets.only(left/right) → EdgeInsetsDirectional.only(start/end)',
    args: const <String>{'left', 'right'},
    symmetric: const <(String, String)>[('left', 'right')],
  ),
  _RtlRule(
    RegExp(r'\bEdgeInsets\s*\.\s*fromLTRB\s*\('),
    (m) => 'EdgeInsets.fromLTRB → EdgeInsetsDirectional.fromSTEB',
    symmetric: const <(String, String)>[(r'$0', r'$2')],
  ),
  _RtlRule(
    RegExp(r'\bAlignment\s*\.\s*(top|center|bottom)(Left|Right)\b'),
    (m) => 'Alignment.${m[1]}${m[2]} → AlignmentDirectional.${m[1]}'
        '${m[2] == 'Left' ? 'Start' : 'End'}',
    // Gradient directions are usually decorative, not reading order.
    skipAfter: RegExp(r'\b(begin|end|center|focal)\s*:\s*(const\s+)?$'),
  ),
  _RtlRule(
    RegExp(r'\bPositioned\s*\('),
    (m) => 'Positioned(left/right) → PositionedDirectional(start/end)',
    args: const <String>{'left', 'right'},
    symmetric: const <(String, String)>[('left', 'right')],
  ),
  _RtlRule(
    RegExp(r'\bTextAlign\s*\.\s*(left|right)\b'),
    (m) => 'TextAlign.${m[1]} → TextAlign.${m[1] == 'left' ? 'start' : 'end'}',
  ),
  _RtlRule(
    RegExp(r'\bBorderRadius\s*\.\s*only\s*\('),
    (m) => 'BorderRadius.only(topLeft/...) → BorderRadiusDirectional.only(topStart/...)',
    args: const <String>{'topLeft', 'topRight', 'bottomLeft', 'bottomRight'},
    symmetric: const <(String, String)>[('topLeft', 'topRight'), ('bottomLeft', 'bottomRight')],
  ),
];

/// Direction-dependent layout code that breaks or looks wrong in RTL.
void runRtlCheck(Project project, Emit emit) {
  for (final source in project.sources) {
    for (final rule in _rtlRules) {
      for (final match in rule.pattern.allMatches(source.masked)) {
        if (_ignoreComment.hasMatch(source.lineText(match.start)) ||
            (rule.skipAfter?.hasMatch(source.codeBefore(match.start, 40)) ?? false)) {
          continue;
        }
        if (rule.args != null || rule.symmetric != null) {
          final args = source.argumentsOf(match.end - 1);
          if (rule.args != null && !args.keys.any(rule.args!.contains)) {
            continue;
          }
          final symmetric = rule.symmetric!.every((pair) {
            final a = args[pair.$1]?.replaceAll(RegExp(r'\s+'), '');
            final b = args[pair.$2]?.replaceAll(RegExp(r'\s+'), '');
            return a == b;
          });
          if (symmetric) {
            continue;
          }
        }
        final suggestion = rule.suggest(match);
        emit(
          CheckId.rtlSmell,
          suggestion,
          file: source.path,
          line: source.lineOf(match.start),
          data: <String, Object?>{
            'code': match[0]!.replaceAll(RegExp(r'\s+'), '').replaceAll('(', ''),
          },
        );
      }
    }
  }
}

String _clip(String text, [int max = 60]) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ');
  return oneLine.length <= max ? '"$oneLine"' : '"${oneLine.substring(0, max - 1)}…"';
}
