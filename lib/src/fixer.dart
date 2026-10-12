import 'dart:convert';
import 'dart:io';

import 'catalog.dart';
import 'project.dart';

/// What `fix` changed (or would change) in one file.
class FileFix {
  FileFix(this.path, this.locale, this.added, this.sorted, this.written);

  final String path;
  final String locale;

  /// Keys added from the base locale.
  final List<String> added;

  /// Whether the key order changed.
  final bool sorted;

  /// Whether the file was written (false on a dry run).
  final bool written;
}

/// Sorts keys and/or adds missing keys to every locale file.
///
/// Nothing happens unless [sort] or [addMissing] is set. Added values are
/// the base value prefixed with [todoMarker], so the `untranslated` check
/// keeps flagging them until someone translates them.
List<FileFix> fixCatalog(
  Project project, {
  required bool sort,
  required bool addMissing,
  required bool dryRun,
  String? todoMarker,
}) {
  if (!sort && !addMissing) {
    return const <FileFix>[];
  }
  final catalog = project.catalog;
  final marker = todoMarker ?? project.config.todoMarker;
  final broken = catalog.locales.values.where((f) => f.errors.isNotEmpty).toList();
  if (broken.isNotEmpty) {
    throw ProjectException(
      'Refusing to rewrite: ${broken.map((f) => project.relative(f.path)).join(', ')} '
      'could not be parsed.',
    );
  }
  final baseRaw = _read(catalog.base.path);
  final fixes = <FileFix>[];
  for (final file in catalog.locales.values) {
    final original = File(file.path).readAsStringSync();
    var data = _read(file.path);
    final added = <String>[];
    final isBase = file.locale == catalog.baseLocale;
    if (addMissing && !isBase) {
      if (catalog.format == L10nFormat.arb) {
        _addMissingArb(baseRaw, data, marker, added);
      } else {
        _addMissingJson(baseRaw, data, marker, '', added);
      }
    }
    final beforeSort = jsonEncode(data);
    if (sort) {
      data = catalog.format == L10nFormat.arb ? _sortArb(data) : _sortJson(data);
    }
    final sorted = jsonEncode(data) != beforeSort;
    final indent = _indentOf(original);
    var output = JsonEncoder.withIndent(indent).convert(data);
    if (original.endsWith('\n')) {
      output += '\n';
    }
    if (output == original) {
      continue;
    }
    if (added.isEmpty && !sorted) {
      continue;
    }
    if (!dryRun) {
      File(file.path).writeAsStringSync(output);
    }
    fixes.add(FileFix(project.relative(file.path), file.locale, added, sorted, !dryRun));
  }
  return fixes;
}

Map<String, Object?> _read(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  return (decoded as Map).map((k, v) => MapEntry('$k', v));
}

String _indentOf(String text) {
  final match = RegExp(r'\n([ \t]+)\S').firstMatch(text);
  return match?[1] ?? '  ';
}

Object? _mark(Object? value, String marker) {
  if (value is String) {
    return '$marker$value';
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry('$k', _mark(v, marker)));
  }
  return value;
}

void _addMissingJson(
  Map<String, Object?> base,
  Map<String, Object?> target,
  String marker,
  String prefix,
  List<String> added,
) {
  base.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    final existing = target[key];
    if (!target.containsKey(key)) {
      target[key] = _mark(value, marker);
      added.add(path);
    } else if (value is Map && existing is Map) {
      final child = existing.map((k, v) => MapEntry('$k', v));
      _addMissingJson(value.map((k, v) => MapEntry('$k', v)), child, marker, path, added);
      target[key] = child;
    }
  });
}

void _addMissingArb(
  Map<String, Object?> base,
  Map<String, Object?> target,
  String marker,
  List<String> added,
) {
  base.forEach((key, value) {
    if (key.startsWith('@') || target.containsKey(key) || value is! String) {
      return;
    }
    target[key] = '$marker$value';
    added.add(key);
  });
}

int _compareKeys(String a, String b) {
  final ia = pluralCategories.indexOf(a);
  final ib = pluralCategories.indexOf(b);
  if (ia >= 0 && ib >= 0) {
    return ia.compareTo(ib);
  }
  return a.compareTo(b);
}

Map<String, Object?> _sortJson(Map<String, Object?> map) {
  final keys = map.keys.toList()..sort(_compareKeys);
  return <String, Object?>{
    for (final key in keys)
      key: map[key] is Map
          ? _sortJson((map[key]! as Map).map((k, v) => MapEntry('$k', v)))
          : map[key],
  };
}

Map<String, Object?> _sortArb(Map<String, Object?> map) {
  final fileMeta = map.keys.where((k) => k.startsWith('@@')).toList()..sort();
  final messages = map.keys.where((k) => !k.startsWith('@')).toList()..sort();
  final result = <String, Object?>{for (final k in fileMeta) k: map[k]};
  for (final key in messages) {
    result[key] = map[key];
    if (map.containsKey('@$key')) {
      result['@$key'] = map['@$key'];
    }
  }
  // Orphan metadata (no message) stays, at the end.
  for (final key in map.keys) {
    if (!result.containsKey(key)) {
      result[key] = map[key];
    }
  }
  return result;
}
