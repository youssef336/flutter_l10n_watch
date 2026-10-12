import '../catalog.dart';
import '../config.dart';
import '../finding.dart';
import '../message.dart';
import '../project.dart';

/// Builds [MessageInfo] for entries, cached per entry.
class MessageAnalyzer {
  MessageAnalyzer(this.project);

  final Project project;
  final Map<Entry, MessageInfo> _cache = Map<Entry, MessageInfo>.identity();

  MessageInfo of(Entry entry) => _cache.putIfAbsent(entry, () => _build(entry));

  MessageInfo ofText(String text) {
    switch (project.format) {
      case L10nFormat.arb:
        return analyzeIcu(text, useEscaping: project.arb.useEscaping);
      case L10nFormat.json:
        return analyzeSimple(text, pattern: project.config.placeholderPattern, links: false);
      case L10nFormat.easyLocalization:
        // ICU syntax is not parsed by easy_localization; read it as ICU so
        // the placeholder comparison is not confused by branch bodies.
        return icuSyntax.hasMatch(text) ? analyzeIcu(text) : analyzeSimple(text);
    }
  }

  MessageInfo _build(Entry entry) {
    if (entry.text != null) {
      return ofText(entry.text!);
    }
    final named = <String>{};
    final links = <String>{};
    var positional = 0;
    String? error;
    for (final form in entry.forms.values) {
      final info = ofText(form);
      named.addAll(info.named);
      links.addAll(info.links);
      if (info.positional > positional) {
        positional = info.positional;
      }
      error ??= info.error;
    }
    return MessageInfo(
      named: named,
      positional: positional,
      links: links,
      plain: ofText(entry.display).plain,
      error: error,
    );
  }
}

/// An ICU plural/select argument, e.g. `{count, plural,`.
final icuSyntax = RegExp(r'\{\s*[A-Za-z_]\w*\s*,\s*(plural|select|selectordinal)\s*,');

typedef Emit = void Function(
  String check,
  String message, {
  String? locale,
  String? key,
  String? file,
  int? line,
  Map<String, Object?> data,
});

/// Checks that only need the translation files.
void runCatalogChecks(Project project, MessageAnalyzer messages, Emit emit) {
  final catalog = project.catalog;
  final config = project.config;
  final base = catalog.base;
  final baseLanguage = base.language;

  for (final file in catalog.locales.values) {
    for (final error in file.errors) {
      emit(CheckId.invalidMessage, '${file.locale}: $error',
          locale: file.locale, file: project.relative(file.path));
    }
  }

  for (final file in catalog.locales.values) {
    final isBase = file.locale == catalog.baseLocale;
    final relative = project.relative(file.path);
    for (final entry in file.entries.values) {
      if (config.isIgnoredKey(entry.key)) {
        continue;
      }
      final info = messages.of(entry);
      _emptyCheck(file, entry, relative, emit);
      if (info.error != null) {
        emit(
          CheckId.invalidMessage,
          '${file.locale}: "${entry.key}" ${info.error}',
          locale: file.locale,
          key: entry.key,
          file: relative,
        );
      }
      if (project.format == L10nFormat.easyLocalization && entry.strings.any(icuSyntax.hasMatch)) {
        emit(
          CheckId.invalidMessage,
          '${file.locale}: "${entry.key}" uses ICU plural/select syntax, which '
          'easy_localization shows as-is; use a plural object with .plural()',
          locale: file.locale,
          key: entry.key,
          file: relative,
        );
      }
      _pluralCheck(project, file, entry, messages, relative, emit);
      if (isBase) {
        continue;
      }
      final baseEntry = base.entries[entry.key];
      if (baseEntry == null) {
        emit(
          CheckId.extraTranslation,
          '${file.locale}: "${entry.key}" is not in ${catalog.baseLocale}',
          locale: file.locale,
          key: entry.key,
          file: relative,
        );
        continue;
      }
      if (entry.isEmpty || baseEntry.isEmpty) {
        continue;
      }
      final baseInfo = messages.of(baseEntry);
      if (info.error == null && baseInfo.error == null && !_samePlaceholders(baseInfo, info)) {
        emit(
          CheckId.placeholderMismatch,
          '${file.locale}: "${entry.key}" has ${info.describePlaceholders()}, '
          '${catalog.baseLocale} has ${baseInfo.describePlaceholders()}',
          locale: file.locale,
          key: entry.key,
          file: relative,
          data: <String, Object?>{
            'expected': baseInfo.describePlaceholders(),
            'actual': info.describePlaceholders(),
          },
        );
      }
      if (file.language != baseLanguage) {
        _untranslatedCheck(project, file, entry, baseEntry, messages, relative, emit);
      }
      if (info.error == null && baseInfo.error == null) {
        _lengthCheck(project, file, entry, info, baseInfo, relative, emit);
      }
    }
    if (!isBase) {
      for (final key in base.entries.keys) {
        if (!file.entries.containsKey(key) && !config.isIgnoredKey(key)) {
          emit(
            CheckId.missingTranslation,
            '${file.locale}: missing "$key"',
            locale: file.locale,
            key: key,
            file: relative,
          );
        }
      }
    }
  }

  if (project.format == L10nFormat.arb) {
    _arbMetadataCheck(project, messages, emit);
  }
}

void _emptyCheck(LocaleFile file, Entry entry, String relative, Emit emit) {
  if (entry.text != null) {
    if (entry.text!.trim().isEmpty) {
      emit(CheckId.emptyValue, '${file.locale}: "${entry.key}" is empty',
          locale: file.locale, key: entry.key, file: relative);
    }
    return;
  }
  for (final form in entry.forms.entries) {
    if (form.value.trim().isEmpty) {
      emit(CheckId.emptyValue, '${file.locale}: "${entry.key}.${form.key}" is empty',
          locale: file.locale, key: entry.key, file: relative);
    }
  }
}

bool _samePlaceholders(MessageInfo a, MessageInfo b) =>
    a.positional == b.positional &&
    a.named.length == b.named.length &&
    a.named.containsAll(b.named);

/// `=0` / `=1` / `=2` cover the zero / one / two categories for counts.
String _category(String selector) => switch (selector) {
      '=0' => 'zero',
      '=1' => 'one',
      '=2' => 'two',
      _ => selector,
    };

void _pluralCheck(
  Project project,
  LocaleFile file,
  Entry entry,
  MessageAnalyzer messages,
  String relative,
  Emit emit,
) {
  final required = project.config.requiredPlurals(file.language);
  void checkSelectors(String what, Iterable<String> selectors, {required bool plural}) {
    final present = selectors.map(_category).toSet();
    if (!present.contains('other')) {
      emit(
        CheckId.invalidMessage,
        '${file.locale}: "${entry.key}" $what has no "other" branch',
        locale: file.locale,
        key: entry.key,
        file: relative,
      );
    }
    if (!plural) {
      return;
    }
    final missing = required.where((c) => !present.contains(c)).toList();
    if (missing.isNotEmpty) {
      emit(
        CheckId.pluralForms,
        '${file.locale}: "${entry.key}" $what lacks ${missing.join(', ')} '
        '(${file.language} uses ${required.join('/')})',
        locale: file.locale,
        key: entry.key,
        file: relative,
        data: <String, Object?>{'missing': missing, 'present': present.toList()},
      );
    }
  }

  if (entry.kind == EntryKind.plural) {
    checkSelectors('plural', entry.forms.keys, plural: true);
  } else if (entry.kind == EntryKind.text && project.format == L10nFormat.arb) {
    for (final choice in messages.of(entry).choices) {
      checkSelectors('{${choice.argument}, ${choice.type}}', choice.selectors,
          plural: choice.isPlural);
    }
  }
  if (file.locale != project.catalog.baseLocale) {
    final baseEntry = project.catalog.base.entries[entry.key];
    if (baseEntry != null && baseEntry.kind != entry.kind) {
      emit(
        CheckId.pluralForms,
        '${file.locale}: "${entry.key}" is ${_kindName(entry.kind)} but '
        '${baseEntry.kind == EntryKind.text ? 'plain text' : 'a ${baseEntry.kind.name}'} '
        'in ${project.catalog.baseLocale}',
        locale: file.locale,
        key: entry.key,
        file: relative,
      );
    }
  }
}

String _kindName(EntryKind kind) => kind == EntryKind.text ? 'plain text' : 'a ${kind.name}';

final _letter = RegExp(r'\p{L}', unicode: true);
final _urlOrEmail = RegExp(r'^(https?://\S+|[\w.+-]+@[\w-]+\.[\w.-]+|www\.\S+)$');

/// Whether [text] is too short, symbolic or brand-like to need translating.
bool isTranslationExempt(String visible, Config config) {
  if (_letter.allMatches(visible).length < config.untranslatedMinLetters) {
    return true;
  }
  if (_urlOrEmail.hasMatch(visible)) {
    return true;
  }
  final allow = config.untranslatedAllow.map((w) => w.toLowerCase()).toSet();
  if (allow.isEmpty) {
    return false;
  }
  final lower = visible.toLowerCase();
  if (allow.contains(lower)) {
    return true;
  }
  final words = lower
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty && _letter.hasMatch(w));
  return words.every(allow.contains);
}

void _untranslatedCheck(
  Project project,
  LocaleFile file,
  Entry entry,
  Entry baseEntry,
  MessageAnalyzer messages,
  String relative,
  Emit emit,
) {
  final config = project.config;
  if (config.untranslatedIgnoreKeys.any((r) => r.hasMatch(entry.key))) {
    return;
  }
  final marker = config.todoMarker;
  if (marker.isNotEmpty && entry.strings.any((s) => s.startsWith(marker))) {
    emit(
      CheckId.untranslated,
      '${file.locale}: "${entry.key}" is marked "${marker.trim()}"',
      locale: file.locale,
      key: entry.key,
      file: relative,
    );
    return;
  }
  final pairs = <(String, String)>[];
  if (entry.text != null && baseEntry.text != null) {
    pairs.add((entry.text!, baseEntry.text!));
  } else {
    for (final form in entry.forms.entries) {
      final baseForm = baseEntry.forms[form.key];
      if (baseForm != null) {
        pairs.add((form.value, baseForm));
      }
    }
  }
  if (pairs.isEmpty || pairs.any((pair) => pair.$1.trim() != pair.$2.trim())) {
    return;
  }
  final visible = visibleText(messages.of(baseEntry));
  if (isTranslationExempt(visible, config)) {
    return;
  }
  emit(
    CheckId.untranslated,
    '${file.locale}: "${entry.key}" is identical to ${project.catalog.baseLocale} '
    '("${_clip(visible)}")',
    locale: file.locale,
    key: entry.key,
    file: relative,
    data: <String, Object?>{'value': visible},
  );
}

void _lengthCheck(
  Project project,
  LocaleFile file,
  Entry entry,
  MessageInfo info,
  MessageInfo baseInfo,
  String relative,
  Emit emit,
) {
  final config = project.config;
  final baseLength = visibleText(baseInfo).runes.length;
  final length = visibleText(info).runes.length;
  if (baseLength == 0 || length <= config.lengthMinChars) {
    return;
  }
  final ratio = length / baseLength;
  if (ratio <= config.lengthRatio) {
    return;
  }
  emit(
    CheckId.lengthRisk,
    '${file.locale}: "${entry.key}" is ${ratio.toStringAsFixed(1)}x longer than '
    '${project.catalog.baseLocale} ($length vs $baseLength chars)',
    locale: file.locale,
    key: entry.key,
    file: relative,
    data: <String, Object?>{
      'ratio': double.parse(ratio.toStringAsFixed(2)),
      'length': length,
      'baseLength': baseLength,
    },
  );
}

void _arbMetadataCheck(Project project, MessageAnalyzer messages, Emit emit) {
  final base = project.catalog.base;
  final relative = project.relative(base.path);
  base.metadata.forEach((key, meta) {
    if (!base.entries.containsKey(key) && !project.config.isIgnoredKey(key)) {
      emit(CheckId.arbMetadata, '${base.locale}: "@$key" describes a message that does not exist',
          locale: base.locale, key: key, file: relative);
    }
  });
  for (final entry in base.entries.values) {
    if (project.config.isIgnoredKey(entry.key)) {
      continue;
    }
    final info = messages.of(entry);
    if (info.error != null) {
      continue;
    }
    final placeholders = base.metadata[entry.key]?['placeholders'];
    final declared = placeholders is Map ? placeholders.keys.map((k) => '$k').toSet() : <String>{};
    final undeclared = info.named.difference(declared);
    final unused = declared.difference(info.named);
    if (undeclared.isNotEmpty) {
      emit(
        CheckId.arbMetadata,
        '${base.locale}: "${entry.key}" uses ${_braces(undeclared)} without '
        '"@${entry.key}" placeholders metadata',
        locale: base.locale,
        key: entry.key,
        file: relative,
      );
    }
    if (unused.isNotEmpty) {
      emit(
        CheckId.arbMetadata,
        '${base.locale}: "@${entry.key}" declares ${_braces(unused)} but the message '
        'does not use ${unused.length == 1 ? 'it' : 'them'}',
        locale: base.locale,
        key: entry.key,
        file: relative,
      );
    }
  }
}

String _braces(Set<String> names) => (names.toList()..sort()).map((n) => '{$n}').join(', ');

String _clip(String text, [int max = 60]) =>
    text.length <= max ? text : '${text.substring(0, max - 1)}…';
