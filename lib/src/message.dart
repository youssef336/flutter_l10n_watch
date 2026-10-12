/// A plural, select or selectordinal argument of an ICU message.
class ChoiceArg {
  const ChoiceArg(this.argument, this.type, this.selectors);

  final String argument;

  /// `plural`, `select` or `selectordinal`.
  final String type;

  /// Branch selectors in source order (`=0`, `one`, `other`, `male`, ...).
  final List<String> selectors;

  bool get isPlural => type == 'plural';
}

/// What a translated string contains, independent of its wording.
class MessageInfo {
  const MessageInfo({
    this.named = const <String>{},
    this.positional = 0,
    this.choices = const <ChoiceArg>[],
    this.links = const <String>{},
    required this.plain,
    this.error,
  });

  /// Named placeholders (`{name}`); for ICU, every argument name.
  final Set<String> named;

  /// Positional `{}` placeholders (easy_localization).
  final int positional;
  final List<ChoiceArg> choices;

  /// Keys referenced through easy_localization links (`@:other.key`).
  final Set<String> links;

  /// Readable rendering used for length and similarity comparisons.
  final String plain;

  /// Parse error, if the message is malformed.
  final String? error;

  /// A comparable description of the placeholders, e.g. `{}×2, {name}`.
  String describePlaceholders() {
    final parts = <String>[
      if (positional > 0) positional == 1 ? '{}' : '{}×$positional',
      ...(named.toList()..sort()).map((n) => '{$n}'),
    ];
    return parts.isEmpty ? 'none' : parts.join(', ');
  }
}

final _easyPlaceholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)?\}');
final _easyLink = RegExp(r'@(?:\.[a-z]+)?:([A-Za-z0-9_.\-]+)');

/// Analyzes an easy_localization (or plain JSON) string.
///
/// [pattern] overrides the placeholder syntax; its first group is the name,
/// and an empty or missing group counts as a positional placeholder.
MessageInfo analyzeSimple(String text, {RegExp? pattern, bool links = true}) {
  final named = <String>{};
  var positional = 0;
  for (final match in (pattern ?? _easyPlaceholder).allMatches(text)) {
    final name = match.groupCount >= 1 ? match.group(1) : null;
    if (name == null || name.isEmpty) {
      positional++;
    } else {
      named.add(name);
    }
  }
  final linked = <String>{};
  if (links) {
    for (final match in _easyLink.allMatches(text)) {
      var key = match.group(1)!;
      while (key.endsWith('.')) {
        key = key.substring(0, key.length - 1);
      }
      if (key.isNotEmpty) {
        linked.add(key);
      }
    }
  }
  return MessageInfo(named: named, positional: positional, links: linked, plain: text);
}

/// Analyzes an ICU message as used by ARB files.
///
/// When [useEscaping] is true, single quotes escape syntax characters as in
/// gen_l10n's `use-escaping: true`.
MessageInfo analyzeIcu(String text, {bool useEscaping = false}) {
  final parser = _IcuParser(text, useEscaping);
  try {
    final plain = parser.parseMessage(topLevel: true);
    return MessageInfo(named: parser.names, choices: parser.choices, plain: plain);
  } on FormatException catch (e) {
    return MessageInfo(
      named: parser.names,
      choices: parser.choices,
      plain: text,
      error: e.message,
    );
  }
}

class _IcuParser {
  _IcuParser(this.text, this.useEscaping);

  final String text;
  final bool useEscaping;
  final Set<String> names = <String>{};
  final List<ChoiceArg> choices = <ChoiceArg>[];
  int pos = 0;

  static const _choiceTypes = <String>{'plural', 'select', 'selectordinal'};
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  bool get atEnd => pos >= text.length;

  String parseMessage({required bool topLevel}) {
    final out = StringBuffer();
    while (!atEnd) {
      final char = text[pos];
      if (useEscaping && char == "'") {
        out.write(_readQuoted());
      } else if (char == '{') {
        pos++;
        out.write(_parseArgument());
      } else if (char == '}') {
        if (topLevel) {
          throw FormatException('unexpected "}" at offset $pos');
        }
        return out.toString();
      } else {
        out.write(char);
        pos++;
      }
    }
    if (!topLevel) {
      throw const FormatException('unclosed "{" in a plural/select branch');
    }
    return out.toString();
  }

  String _readQuoted() {
    // At a quote. '' is a literal quote; 'x...' quotes until the next quote.
    if (pos + 1 < text.length && text[pos + 1] == "'") {
      pos += 2;
      return "'";
    }
    final close = text.indexOf("'", pos + 1);
    if (close < 0) {
      final rest = text.substring(pos + 1);
      pos = text.length;
      return rest;
    }
    final quoted = text.substring(pos + 1, close);
    pos = close + 1;
    return quoted;
  }

  String _readUntil(Set<String> stops) {
    final start = pos;
    while (!atEnd && !stops.contains(text[pos])) {
      pos++;
    }
    return text.substring(start, pos);
  }

  void _skipSpace() {
    while (!atEnd && text[pos].trim().isEmpty) {
      pos++;
    }
  }

  String _parseArgument() {
    final openedAt = pos - 1;
    final name = _readUntil(const <String>{',', '}', '{'}).trim();
    if (atEnd) {
      throw FormatException('unclosed "{" at offset $openedAt');
    }
    if (name.isEmpty || !_identifier.hasMatch(name)) {
      throw FormatException('invalid placeholder name "{$name" at offset $openedAt');
    }
    names.add(name);
    if (text[pos] == '}') {
      pos++;
      return '{$name}';
    }
    if (text[pos] == '{') {
      throw FormatException('unexpected "{" after "$name" at offset $pos');
    }
    pos++; // ','
    final type = _readUntil(const <String>{',', '}', '{'}).trim();
    if (atEnd) {
      throw FormatException('unclosed "{$name, $type" at offset $openedAt');
    }
    if (!_choiceTypes.contains(type)) {
      // number, date, time, ... with an optional style: skip to the close.
      var depth = 1;
      while (!atEnd && depth > 0) {
        if (text[pos] == '{') {
          depth++;
        } else if (text[pos] == '}') {
          depth--;
        }
        pos++;
      }
      if (depth > 0) {
        throw FormatException('unclosed "{$name, $type" at offset $openedAt');
      }
      return '{$name}';
    }
    if (text[pos] != ',') {
      throw FormatException('"{$name, $type}" has no branches');
    }
    pos++;
    final selectors = <String>[];
    String? other;
    String? first;
    while (true) {
      _skipSpace();
      if (atEnd) {
        throw FormatException('unclosed "{$name, $type" at offset $openedAt');
      }
      if (text[pos] == '}') {
        pos++;
        break;
      }
      final selector = _readUntil(const <String>{'{', '}', ' ', '\n', '\t', '\r'}).trim();
      _skipSpace();
      if (selector.startsWith('offset:')) {
        continue;
      }
      if (selector.isEmpty || atEnd || text[pos] != '{') {
        throw FormatException('branch "$selector" of "$name" has no {message}');
      }
      pos++;
      final branch = parseMessage(topLevel: false);
      pos++; // '}'
      selectors.add(selector);
      first ??= branch;
      if (selector == 'other') {
        other = branch;
      }
    }
    if (selectors.isEmpty) {
      throw FormatException('"{$name, $type}" has no branches');
    }
    choices.add(ChoiceArg(name, type, selectors));
    return other ?? first ?? '';
  }
}

/// Strips placeholders and ICU/link syntax, leaving the words a reader sees.
String visibleText(MessageInfo info) => info.plain
    .replaceAll(_easyPlaceholder, ' ')
    .replaceAll(_easyLink, ' ')
    .replaceAll('#', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
