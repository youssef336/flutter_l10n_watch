import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'catalog.dart';
import 'config.dart';
import 'dart_source.dart';

/// gen_l10n settings read from `l10n.yaml` (or intl_utils defaults).
class ArbSettings {
  const ArbSettings({
    this.arbDir = 'lib/l10n',
    this.templateFile = 'app_en.arb',
    this.outputClass = 'AppLocalizations',
    this.useEscaping = false,
    this.fromL10nYaml = false,
  });

  final String arbDir;
  final String templateFile;
  final String outputClass;
  final bool useEscaping;
  final bool fromL10nYaml;
}

/// Raised when the project cannot be understood well enough to check it.
class ProjectException implements Exception {
  ProjectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything a check needs: the catalog, the Dart sources and settings.
class Project {
  Project({
    required this.root,
    required this.config,
    required this.catalog,
    required this.sources,
    required this.localeKeys,
    required this.arb,
    required this.notes,
  });

  final String root;
  final Config config;
  final Catalog catalog;
  final List<DartSource> sources;

  /// `LocaleKeys` constant name → key, parsed from the generated class.
  final Map<String, String> localeKeys;
  final ArbSettings arb;

  /// How the setup was detected, for the report header.
  final List<String> notes;

  L10nFormat get format => catalog.format;

  String relative(String path) => p.split(p.relative(path, from: root)).join('/');
}

/// Detects the setup under [root] and loads catalog and sources.
Project loadProject(String root, Config config) {
  root = p.normalize(p.absolute(root));
  if (!Directory(root).existsSync()) {
    throw ProjectException('Project folder not found: $root');
  }
  final notes = <String>[];
  final pubspec = _readYamlMap(p.join(root, 'pubspec.yaml'));
  final dependencies = <String>{
    ...?(pubspec?['dependencies'] as Map?)?.keys.map((k) => '$k'),
    ...?(pubspec?['dev_dependencies'] as Map?)?.keys.map((k) => '$k'),
  };
  final allDart = _dartFiles(root, config.sourceDirs);
  final arb = _arbSettings(root, pubspec);

  final codeHint = _easyLocalizationHints(allDart);
  L10nFormat? format = config.format;
  String? jsonDir;
  String? arbDir;
  if (format == null || format != L10nFormat.arb) {
    jsonDir = _findJsonDir(root, config, pubspec, codeHint.path);
  }
  if (format == null || format == L10nFormat.arb) {
    arbDir = _findArbDir(root, config, arb);
  }
  if (format == null) {
    final usesEasy = dependencies.contains('easy_localization');
    if (usesEasy && jsonDir != null) {
      format = L10nFormat.easyLocalization;
    } else if (arbDir != null) {
      format = L10nFormat.arb;
    } else if (jsonDir != null) {
      format = usesEasy ? L10nFormat.easyLocalization : L10nFormat.json;
    } else {
      throw ProjectException(
        'Could not find translation files. Set translations_dir (and format) '
        'in $configFileName.',
      );
    }
    notes.add('detected ${format.id}');
  }

  final Catalog catalog;
  if (format == L10nFormat.arb) {
    if (arbDir == null) {
      throw ProjectException('No .arb files found (looked in ${arb.arbDir}).');
    }
    catalog = _loadArbCatalog(arbDir, arb, config);
  } else {
    if (jsonDir == null) {
      throw ProjectException(
        'No locale JSON files (like en.json) found. Set translations_dir in $configFileName.',
      );
    }
    catalog = _loadJsonCatalog(jsonDir, format, config, codeHint.fallbackLocale);
  }

  final localeKeys = <String, String>{};
  final sources = <DartSource>[];
  final excludes = config.exclude.map((g) => Glob(g, context: p.posix)).toList();
  final generatedMarker = RegExp(
    '(abstract class|extends) ${RegExp.escape(arb.outputClass)}\\b|'
    'abstract\\s+class\\s+${RegExp.escape(config.localeKeysClass)}\\b',
  );
  final localeKeysClass = RegExp(
    'abstract\\s+class\\s+${RegExp.escape(config.localeKeysClass)}\\s*\\{',
  );
  for (final file in allDart) {
    final relative = p.split(p.relative(file.path, from: root)).join('/');
    final text = file.readAsStringSync();
    if (localeKeysClass.hasMatch(text)) {
      for (final m in RegExp(r'''static\s+const\s+(?:String\s+)?(\w+)\s*=\s*['"]([^'"]*)['"]''')
          .allMatches(text)) {
        localeKeys[m[1]!] = m[2]!;
      }
    }
    if (excludes.any((g) => g.matches(relative))) {
      continue;
    }
    if (generatedMarker.hasMatch(text) || _generatedHeader.hasMatch(_head(text))) {
      continue;
    }
    sources.add(DartSource(relative, text));
  }
  if (localeKeys.isNotEmpty) {
    notes.add('${config.localeKeysClass} class with ${localeKeys.length} constants');
  }
  return Project(
    root: root,
    config: config,
    catalog: catalog,
    sources: sources,
    localeKeys: localeKeys,
    arb: arb,
    notes: notes,
  );
}

final _generatedHeader = RegExp(
  r'(automatically generated|generated code|generated by|do not edit|do not modify)',
  caseSensitive: false,
);

/// The leading comment block of a file, where generators put their banner.
String _head(String text) {
  final lines = <String>[];
  for (final line in text.split('\n').take(15)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('//') ||
        trimmed.startsWith('/*') ||
        trimmed.startsWith('*')) {
      lines.add(trimmed);
    } else {
      break;
    }
  }
  return lines.join('\n');
}

Map<dynamic, dynamic>? _readYamlMap(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  try {
    final doc = loadYaml(file.readAsStringSync());
    return doc is Map ? doc : null;
  } on YamlException {
    return null;
  }
}

List<File> _dartFiles(String root, List<String> dirs) {
  final files = <File>[];
  for (final dir in dirs) {
    final directory = Directory(p.join(root, dir));
    if (!directory.existsSync()) {
      continue;
    }
    files.addAll(
      directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    );
  }
  return files..sort((a, b) => a.path.compareTo(b.path));
}

ArbSettings _arbSettings(String root, Map<dynamic, dynamic>? pubspec) {
  final l10n = _readYamlMap(p.join(root, 'l10n.yaml'));
  if (l10n != null || File(p.join(root, 'l10n.yaml')).existsSync()) {
    return ArbSettings(
      arbDir: '${l10n?['arb-dir'] ?? 'lib/l10n'}',
      templateFile: '${l10n?['template-arb-file'] ?? 'app_en.arb'}',
      outputClass: '${l10n?['output-class'] ?? 'AppLocalizations'}',
      useEscaping: l10n?['use-escaping'] == true,
      fromL10nYaml: true,
    );
  }
  final intl = pubspec?['flutter_intl'];
  if (intl is Map) {
    final mainLocale = '${intl['main_locale'] ?? 'en'}';
    return ArbSettings(
      arbDir: '${intl['arb_dir'] ?? 'lib/l10n'}',
      templateFile: 'intl_$mainLocale.arb',
      outputClass: '${intl['class_name'] ?? 'S'}',
    );
  }
  return const ArbSettings();
}

class _EasyHints {
  const _EasyHints(this.path, this.fallbackLocale);

  final String? path;
  final String? fallbackLocale;
}

_EasyHints _easyLocalizationHints(List<File> files) {
  final call = RegExp(r'EasyLocalization\s*\(');
  final path = RegExp(r'''\bpath\s*:\s*['"]([^'"]+)['"]''');
  final fallback = RegExp(
    r'''fallbackLocale\s*:\s*(?:const\s+)?Locale\s*\(\s*['"](\w+)['"]\s*(?:,\s*['"](\w+)['"])?''',
  );
  for (final file in files) {
    final text = file.readAsStringSync();
    final match = call.firstMatch(text);
    if (match == null) {
      continue;
    }
    final window = text.substring(match.start, (match.start + 1500).clamp(0, text.length));
    final pathMatch = path.firstMatch(window);
    final fallbackMatch = fallback.firstMatch(window);
    return _EasyHints(
      pathMatch?[1],
      fallbackMatch == null
          ? null
          : fallbackMatch[2] == null
              ? fallbackMatch[1]
              : '${fallbackMatch[1]}_${fallbackMatch[2]}',
    );
  }
  return const _EasyHints(null, null);
}

const _commonJsonDirs = <String>[
  'assets/translations',
  'assets/translation',
  'assets/lang',
  'assets/langs',
  'assets/languages',
  'assets/locales',
  'assets/locale',
  'assets/i18n',
  'assets/l10n',
  'assets/strings',
  'translations',
  'lang',
  'i18n',
  'locales',
];

String? _findJsonDir(
  String root,
  Config config,
  Map<dynamic, dynamic>? pubspec,
  String? codePath,
) {
  bool hasLocales(String dir) => jsonLocaleFiles(p.join(root, dir)).isNotEmpty;
  String clean(String dir) => p.normalize(dir.replaceAll(RegExp(r'/+$'), ''));

  if (config.translationsDir != null) {
    final dir = clean(config.translationsDir!);
    if (!Directory(p.join(root, dir)).existsSync()) {
      throw ProjectException('translations_dir "$dir" does not exist.');
    }
    return hasLocales(dir) || config.format == L10nFormat.arb ? p.join(root, dir) : null;
  }
  final candidates = <String>[
    if (codePath != null) clean(codePath),
  ];
  final assets = (pubspec?['flutter'] as Map?)?['assets'];
  if (assets is List) {
    final dirs = assets.map((a) => a is Map ? '${a['path']}' : '$a').map(clean).toList();
    final keyword = RegExp('transl|lang|i18n|l10n|locale|string', caseSensitive: false);
    candidates
      ..addAll(dirs.where(keyword.hasMatch))
      ..addAll(dirs.where((d) => !keyword.hasMatch(d)));
  }
  candidates.addAll(_commonJsonDirs);
  for (final dir in candidates) {
    if (Directory(p.join(root, dir)).existsSync() && hasLocales(dir)) {
      return p.join(root, dir);
    }
  }
  return null;
}

String? _findArbDir(String root, Config config, ArbSettings arb) {
  final candidates = <String>[
    if (config.translationsDir != null) config.translationsDir!,
    arb.arbDir,
    'lib/l10n',
    'lib/l10n/arb',
    'l10n',
    'assets/l10n',
    'lib/src/l10n',
    'lib/localization',
    'lib/i18n',
  ];
  for (final dir in candidates) {
    final path = p.join(root, dir);
    if (arbFiles(path).isNotEmpty) {
      return path;
    }
  }
  return null;
}

Catalog _loadArbCatalog(String dir, ArbSettings arb, Config config) {
  final locales = <String, LocaleFile>{};
  String? templateLocale;
  for (final file in arbFiles(dir)) {
    final name = p.basenameWithoutExtension(file.path);
    final loaded = loadArbLocale(file.path, localeFromArbName(name) ?? name);
    if (locales.containsKey(loaded.locale)) {
      continue; // Same locale twice (e.g. intl_en.arb + app_en.arb): keep the first.
    }
    locales[loaded.locale] = loaded;
    if (p.basename(file.path) == arb.templateFile) {
      templateLocale = loaded.locale;
    }
  }
  final base = _resolveBase(config.baseLocale ?? templateLocale, locales.keys);
  return Catalog(
    format: L10nFormat.arb,
    directory: dir,
    baseLocale: base,
    locales: _sorted(locales),
  );
}

Catalog _loadJsonCatalog(
  String dir,
  L10nFormat format,
  Config config,
  String? codeFallback,
) {
  final locales = <String, LocaleFile>{};
  for (final file in jsonLocaleFiles(dir)) {
    final locale = p.basenameWithoutExtension(file.path);
    locales[locale] = loadJsonLocale(
      file.path,
      locale,
      detectGroups: format == L10nFormat.easyLocalization,
    );
  }
  final base = _resolveBase(config.baseLocale ?? codeFallback, locales.keys);
  return Catalog(format: format, directory: dir, baseLocale: base, locales: _sorted(locales));
}

Map<String, LocaleFile> _sorted(Map<String, LocaleFile> locales) =>
    Map<String, LocaleFile>.fromEntries(
      locales.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

String _resolveBase(String? wanted, Iterable<String> available) {
  final list = available.toList();
  if (list.isEmpty) {
    throw ProjectException('No locale files found.');
  }
  String norm(String s) => s.replaceAll('-', '_').toLowerCase();
  if (wanted != null) {
    for (final locale in list) {
      if (norm(locale) == norm(wanted)) {
        return locale;
      }
    }
    for (final locale in list) {
      if (languageOf(locale) == languageOf(wanted)) {
        return locale;
      }
    }
    throw ProjectException(
      'Base locale "$wanted" not found (available: ${list.join(', ')}).',
    );
  }
  if (list.contains('en')) {
    return 'en';
  }
  return list.firstWhere((l) => languageOf(l) == 'en', orElse: () => list.first);
}
