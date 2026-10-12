import 'dart:io';

import 'package:yaml/yaml.dart';

import 'catalog.dart';
import 'finding.dart';

/// Default name of the config file at the project root.
const configFileName = 'l10n_watch.yaml';

const _defaultExclude = <String>[
  '**/*.g.dart',
  '**/*.freezed.dart',
  '**/*.gr.dart',
  '**/*.config.dart',
  '**/*.mocks.dart',
  '**/generated/**',
  '**/generated_plugin_registrant.dart',
];

const _defaultHardcodedWidgets = <String>['Text', 'SelectableText', 'AutoSizeText'];

const _defaultHardcodedArgs = <String>[
  'hintText',
  'labelText',
  'helperText',
  'errorText',
  'counterText',
  'prefixText',
  'suffixText',
  'tooltip',
  'semanticsLabel',
  'semanticLabel',
  'TextSpan.text',
  'Tooltip.message',
];

/// Plural categories each language needs (CLDR, integer counts).
///
/// French, Spanish, Italian and Portuguese also have `many`, but only for very
/// large numbers, so it is not required here. Languages not listed need
/// `one` and `other`.
const defaultPluralRules = <String, List<String>>{
  'ar': <String>['zero', 'one', 'two', 'few', 'many', 'other'],
  'cy': <String>['zero', 'one', 'two', 'few', 'many', 'other'],
  'ga': <String>['one', 'two', 'few', 'many', 'other'],
  'he': <String>['one', 'two', 'other'],
  'ru': <String>['one', 'few', 'many', 'other'],
  'uk': <String>['one', 'few', 'many', 'other'],
  'be': <String>['one', 'few', 'many', 'other'],
  'pl': <String>['one', 'few', 'many', 'other'],
  'lt': <String>['one', 'few', 'many', 'other'],
  'cs': <String>['one', 'few', 'other'],
  'sk': <String>['one', 'few', 'other'],
  'hr': <String>['one', 'few', 'other'],
  'sr': <String>['one', 'few', 'other'],
  'bs': <String>['one', 'few', 'other'],
  'sl': <String>['one', 'two', 'few', 'other'],
  'ro': <String>['one', 'few', 'other'],
  'lv': <String>['zero', 'one', 'other'],
  'ja': <String>['other'],
  'zh': <String>['other'],
  'ko': <String>['other'],
  'vi': <String>['other'],
  'th': <String>['other'],
  'id': <String>['other'],
  'ms': <String>['other'],
  'fa': <String>['one', 'other'],
  'tr': <String>['one', 'other'],
};

/// Settings for one run. Every field has a sensible default, so an empty
/// config (or no file at all) works for most projects.
class Config {
  Config({
    this.format,
    this.translationsDir,
    this.baseLocale,
    this.sourceDirs = const <String>['lib'],
    List<String> exclude = const <String>[],
    this.ignoreKeys = const <RegExp>[],
    this.localeKeysClass = 'LocaleKeys',
    this.trFunctions = const <String>['tr', 'plural', 'trExists'],
    this.arbAccessors = const <String>[],
    this.placeholderPattern,
    this.untranslatedMinLetters = 3,
    this.untranslatedAllow = const <String>[],
    this.untranslatedIgnoreKeys = const <RegExp>[],
    this.todoMarker = 'TODO: ',
    this.lengthRatio = 1.6,
    this.lengthMinChars = 20,
    this.hardcodedWidgets = _defaultHardcodedWidgets,
    this.hardcodedArgs = _defaultHardcodedArgs,
    this.hardcodedIgnore = const <RegExp>[],
    Map<String, List<String>>? pluralRules,
    Map<String, Severity>? severity,
    this.failOn = Severity.error,
  })  : exclude = <String>[..._defaultExclude, ...exclude],
        pluralRules = <String, List<String>>{...defaultPluralRules, ...?pluralRules},
        severityOverrides = severity ?? const <String, Severity>{};

  /// Reads [path] when it exists, else returns the defaults.
  factory Config.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return Config();
    }
    return Config.parse(file.readAsStringSync(), source: path);
  }

  /// Parses YAML text; throws [FormatException] with a readable message.
  factory Config.parse(String yamlText, {String source = configFileName}) {
    final Object? doc;
    try {
      doc = loadYaml(yamlText, sourceUrl: Uri.file(source));
    } on YamlException catch (e) {
      throw FormatException('$source: ${e.message}');
    }
    if (doc == null) {
      return Config();
    }
    if (doc is! Map) {
      throw FormatException('$source: the top level must be a map');
    }
    final r = _Reader(doc, source);
    r.checkKeys(const <String>{
      'format',
      'translations_dir',
      'base_locale',
      'source_dirs',
      'exclude',
      'ignore_keys',
      'locale_keys_class',
      'tr_functions',
      'arb_accessors',
      'placeholder_pattern',
      'untranslated',
      'length',
      'hardcoded',
      'plural_rules',
      'severity',
      'fail_on',
    });
    final formatRaw = r.string('format');
    L10nFormat? format;
    if (formatRaw != null && formatRaw != 'auto') {
      format = L10nFormat.tryParse(formatRaw) ??
          (throw FormatException(
            '$source: format must be auto, easy_localization, arb or json',
          ));
    }
    final untranslated = r.child('untranslated', const <String>{
      'min_letters',
      'allow',
      'ignore_keys',
      'todo_marker',
    });
    final length = r.child('length', const <String>{'ratio', 'min_chars'});
    final hardcoded = r.child('hardcoded', const <String>{'widgets', 'named_args', 'ignore'});
    final severity = <String, Severity>{};
    final severityMap = r.mapOf('severity');
    severityMap?.forEach((key, value) {
      if (!CheckId.all.contains(key)) {
        throw FormatException(
          '$source: unknown check "$key" in severity (known: ${CheckId.all.join(', ')})',
        );
      }
      severity['$key'] = _severity('$value', source);
    });
    final pluralRules = <String, List<String>>{};
    r.mapOf('plural_rules')?.forEach((key, value) {
      if (value is! List) {
        throw FormatException('$source: plural_rules.$key must be a list');
      }
      pluralRules['$key'] = value.map((v) => '$v').toList();
    });
    final pattern = r.string('placeholder_pattern');
    return Config(
      format: format,
      translationsDir: r.string('translations_dir'),
      baseLocale: r.string('base_locale'),
      sourceDirs: r.list('source_dirs') ?? const <String>['lib'],
      exclude: r.list('exclude') ?? const <String>[],
      ignoreKeys: r.regexes('ignore_keys'),
      localeKeysClass: r.string('locale_keys_class') ?? 'LocaleKeys',
      trFunctions: r.list('tr_functions') ?? const <String>['tr', 'plural', 'trExists'],
      arbAccessors: r.list('arb_accessors') ?? const <String>[],
      placeholderPattern: pattern == null ? null : _regex(pattern, source),
      untranslatedMinLetters: untranslated.integer('min_letters') ?? 3,
      untranslatedAllow: untranslated.list('allow') ?? const <String>[],
      untranslatedIgnoreKeys: untranslated.regexes('ignore_keys'),
      todoMarker: untranslated.string('todo_marker') ?? 'TODO: ',
      lengthRatio: length.number('ratio') ?? 1.6,
      lengthMinChars: length.integer('min_chars') ?? 20,
      hardcodedWidgets: hardcoded.list('widgets') ?? _defaultHardcodedWidgets,
      hardcodedArgs: hardcoded.list('named_args') ?? _defaultHardcodedArgs,
      hardcodedIgnore: hardcoded.regexes('ignore'),
      pluralRules: pluralRules,
      severity: severity,
      failOn:
          r.string('fail_on') == null ? Severity.error : _severity(r.string('fail_on')!, source),
    );
  }

  final L10nFormat? format;
  final String? translationsDir;
  final String? baseLocale;
  final List<String> sourceDirs;

  /// Globs skipped when scanning Dart files (defaults plus configured ones).
  final List<String> exclude;
  final List<RegExp> ignoreKeys;
  final String localeKeysClass;
  final List<String> trFunctions;
  final List<String> arbAccessors;
  final RegExp? placeholderPattern;
  final int untranslatedMinLetters;
  final List<String> untranslatedAllow;
  final List<RegExp> untranslatedIgnoreKeys;
  final String todoMarker;
  final double lengthRatio;
  final int lengthMinChars;
  final List<String> hardcodedWidgets;
  final List<String> hardcodedArgs;
  final List<RegExp> hardcodedIgnore;
  final Map<String, List<String>> pluralRules;
  final Map<String, Severity> severityOverrides;
  final Severity failOn;

  Severity severityOf(String check) =>
      severityOverrides[check] ?? CheckId.defaultSeverity[check] ?? Severity.warning;

  bool isIgnoredKey(String key) => ignoreKeys.any((r) => r.hasMatch(key));

  /// Plural categories required for [language], defaulting to one + other.
  List<String> requiredPlurals(String language) =>
      pluralRules[language] ?? const <String>['one', 'other'];
}

Severity _severity(String raw, String source) {
  try {
    return Severity.parse(raw);
  } on FormatException {
    throw FormatException('$source: "$raw" is not one of error, warning, info, off');
  }
}

RegExp _regex(String pattern, String source) {
  try {
    return RegExp(pattern, unicode: true);
  } on FormatException catch (e) {
    throw FormatException('$source: invalid regex "$pattern": ${e.message}');
  }
}

class _Reader {
  _Reader(this.map, this.source, [this.path = '']);

  final Map<dynamic, dynamic> map;
  final String source;
  final String path;

  String _name(String key) => path.isEmpty ? key : '$path.$key';

  void checkKeys(Set<String> known) {
    for (final key in map.keys) {
      if (!known.contains('$key')) {
        throw FormatException(
          '$source: unknown option "${_name('$key')}" (known: ${known.join(', ')})',
        );
      }
    }
  }

  _Reader child(String key, Set<String> known) {
    final value = map[key];
    if (value == null) {
      return _Reader(const <String, Object?>{}, source, _name(key));
    }
    if (value is! Map) {
      throw FormatException('$source: ${_name(key)} must be a map');
    }
    return _Reader(value, source, _name(key))..checkKeys(known);
  }

  Map<dynamic, dynamic>? mapOf(String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! Map) {
      throw FormatException('$source: ${_name(key)} must be a map');
    }
    return value;
  }

  String? string(String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is Map || value is List) {
      throw FormatException('$source: ${_name(key)} must be a string');
    }
    return '$value';
  }

  int? integer(String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw FormatException('$source: ${_name(key)} must be a whole number');
    }
    return value;
  }

  double? number(String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! num) {
      throw FormatException('$source: ${_name(key)} must be a number');
    }
    return value.toDouble();
  }

  List<String>? list(String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return <String>[value];
    }
    if (value is! List) {
      throw FormatException('$source: ${_name(key)} must be a list');
    }
    return value.map((v) => '$v').toList();
  }

  List<RegExp> regexes(String key) =>
      (list(key) ?? const <String>[]).map((p) => _regex(p, source)).toList();
}
