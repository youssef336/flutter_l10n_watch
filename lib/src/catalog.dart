import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The translation setup a project uses.
enum L10nFormat {
  /// easy_localization: one JSON file per locale, nested keys, `{}` / `{name}`.
  easyLocalization('easy_localization'),

  /// Flutter gen_l10n / intl_utils: ARB files with ICU messages.
  arb('arb'),

  /// Any other flat or nested JSON map per locale.
  json('json');

  const L10nFormat(this.id);

  final String id;

  static L10nFormat? tryParse(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('-', '_');
    for (final format in values) {
      if (format.id == value) {
        return format;
      }
    }
    if (value == 'gen_l10n' || value == 'intl_utils' || value == 'intl') {
      return L10nFormat.arb;
    }
    return null;
  }
}

/// What kind of value an [Entry] holds.
enum EntryKind { text, plural, gender }

/// CLDR plural categories, in canonical order.
const pluralCategories = <String>['zero', 'one', 'two', 'few', 'many', 'other'];
const _genderCategories = <String>{'male', 'female', 'other'};

/// One translatable key in one locale.
class Entry {
  const Entry.text(this.key, String this.text)
      : kind = EntryKind.text,
        forms = const <String, String>{};

  const Entry.group(this.key, this.kind, this.forms) : text = null;

  final String key;
  final EntryKind kind;
  final String? text;
  final Map<String, String> forms;

  /// Every string this entry contains.
  Iterable<String> get strings => text != null ? <String>[text!] : forms.values;

  /// The representative string (the `other` form for groups).
  String get display => text ?? forms['other'] ?? forms.values.first;

  bool get isEmpty => strings.every((s) => s.trim().isEmpty);
}

/// One parsed locale file.
class LocaleFile {
  LocaleFile({
    required this.locale,
    required this.path,
    required this.entries,
    Map<String, Map<String, Object?>>? metadata,
    List<String>? errors,
  })  : metadata = metadata ?? <String, Map<String, Object?>>{},
        errors = errors ?? <String>[];

  final String locale;

  /// Absolute path of the file.
  final String path;
  final Map<String, Entry> entries;

  /// ARB `@key` metadata blocks.
  final Map<String, Map<String, Object?>> metadata;

  /// Problems met while parsing; the file is still usable when not empty.
  final List<String> errors;

  String get language => languageOf(locale);
}

/// All locales of a project.
class Catalog {
  Catalog({
    required this.format,
    required this.directory,
    required this.baseLocale,
    required this.locales,
  });

  final L10nFormat format;
  final String directory;
  final String baseLocale;

  /// Locale code → file, sorted by locale code.
  final Map<String, LocaleFile> locales;

  LocaleFile get base => locales[baseLocale]!;

  Iterable<LocaleFile> get others => locales.values.where((file) => file.locale != baseLocale);

  /// Every key defined in any locale.
  Set<String> get allKeys => <String>{
        for (final file in locales.values) ...file.entries.keys,
      };

  Set<String>? _parents;

  /// Dotted prefixes of nested keys, e.g. `a` and `a.b` for `a.b.c`.
  Set<String> get parents => _parents ??= _computeParents(allKeys);

  static Set<String> _computeParents(Set<String> keys) {
    final result = <String>{};
    for (final key in keys) {
      var index = key.indexOf('.');
      while (index > 0) {
        result.add(key.substring(0, index));
        index = key.indexOf('.', index + 1);
      }
    }
    return result;
  }
}

/// Lower-case language subtag of a locale code (`pt_BR` → `pt`).
String languageOf(String locale) => locale.split(RegExp('[_-]')).first.toLowerCase();

final _localeName = RegExp(r'^[a-z]{2,3}([_-][A-Za-z0-9]{2,8})*$');
final _languageSubtag = RegExp(r'^[a-z]{2,3}$');
final _laterSubtag = RegExp(r'^([A-Z][a-z]{3}|[A-Z]{2}|\d{3})$');

/// True when a file's basename (no extension) looks like a locale code.
bool isLocaleName(String name) => _localeName.hasMatch(name);

/// Locale code at the end of an ARB file name (`app_pt_BR` → `pt_BR`).
String? localeFromArbName(String name) {
  final parts = name.split(RegExp('[_-]'));
  for (var i = 0; i < parts.length; i++) {
    if (_languageSubtag.hasMatch(parts[i]) && parts.skip(i + 1).every(_laterSubtag.hasMatch)) {
      return parts.sublist(i).join('_');
    }
  }
  return null;
}

/// Loads a JSON locale file (easy_localization or plain JSON).
LocaleFile loadJsonLocale(String path, String locale, {bool detectGroups = true}) {
  final errors = <String>[];
  final entries = <String, Entry>{};
  Object? decoded;
  try {
    decoded = jsonDecode(File(path).readAsStringSync());
  } on FormatException catch (e) {
    errors.add('invalid JSON: ${e.message}');
  }
  if (decoded != null && decoded is! Map) {
    errors.add('top-level JSON must be an object');
  } else if (decoded is Map) {
    _flatten(decoded, '', entries, errors, detectGroups);
  }
  return LocaleFile(locale: locale, path: path, entries: entries, errors: errors);
}

void _flatten(
  Map<Object?, Object?> map,
  String prefix,
  Map<String, Entry> out,
  List<String> errors,
  bool detectGroups,
) {
  map.forEach((rawKey, value) {
    final key = prefix.isEmpty ? '$rawKey' : '$prefix.$rawKey';
    if (value is String) {
      out[key] = Entry.text(key, value);
    } else if (value is Map) {
      final kind = detectGroups ? groupKindOf(value) : null;
      if (kind != null) {
        out[key] = Entry.group(key, kind, <String, String>{
          for (final e in value.entries) '${e.key}': e.value as String,
        });
      } else {
        _flatten(value, key, out, errors, detectGroups);
      }
    } else if (value is num || value is bool) {
      out[key] = Entry.text(key, '$value');
    } else if (value == null) {
      out[key] = Entry.text(key, '');
    } else {
      errors.add('"$key" has an unsupported value (${value.runtimeType})');
    }
  });
}

/// Whether a nested JSON object is an easy_localization plural or gender group.
EntryKind? groupKindOf(Map<Object?, Object?> map) {
  if (map.isEmpty || map.values.any((v) => v is! String)) {
    return null;
  }
  final keys = map.keys.map((k) => '$k').toSet();
  if (keys.every(pluralCategories.contains) && (keys.contains('other') || keys.length > 1)) {
    return EntryKind.plural;
  }
  if (keys.every(_genderCategories.contains) &&
      (keys.contains('male') || keys.contains('female'))) {
    return EntryKind.gender;
  }
  return null;
}

/// Loads an ARB file. The locale comes from `@@locale`, else [fallbackLocale].
LocaleFile loadArbLocale(String path, String fallbackLocale) {
  final errors = <String>[];
  final entries = <String, Entry>{};
  final metadata = <String, Map<String, Object?>>{};
  var locale = fallbackLocale;
  Object? decoded;
  try {
    decoded = jsonDecode(File(path).readAsStringSync());
  } on FormatException catch (e) {
    errors.add('invalid JSON: ${e.message}');
  }
  if (decoded != null && decoded is! Map) {
    errors.add('top-level JSON must be an object');
  } else if (decoded is Map) {
    decoded.forEach((rawKey, value) {
      final key = '$rawKey';
      if (key == '@@locale') {
        if (value is String && value.isNotEmpty) {
          locale = value;
        }
      } else if (key.startsWith('@@')) {
        // File-level metadata such as @@last_modified.
      } else if (key.startsWith('@')) {
        if (value is Map) {
          metadata[key.substring(1)] = value.map((k, v) => MapEntry('$k', v));
        }
      } else if (value is String) {
        entries[key] = Entry.text(key, value);
      } else {
        errors.add('"$key" is not a string');
      }
    });
  }
  return LocaleFile(
    locale: locale,
    path: path,
    entries: entries,
    metadata: metadata,
    errors: errors,
  );
}

/// Lists the JSON files in [dir] whose names look like locale codes.
List<File> jsonLocaleFiles(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    return <File>[];
  }
  return directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .where((f) => isLocaleName(p.basenameWithoutExtension(f.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Lists the ARB files in [dir].
List<File> arbFiles(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    return <File>[];
  }
  return directory.listSync().whereType<File>().where((f) => f.path.endsWith('.arb')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}
