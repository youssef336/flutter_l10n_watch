/// Marks where an interpolation (`$x` / `${...}`) sat inside a literal value.
const interpolationMarker = '\u{FFFC}';

/// A string literal found in Dart source.
class StringLiteral {
  const StringLiteral({
    required this.start,
    required this.end,
    required this.value,
    required this.interpolated,
    required this.prefix,
    required this.enclosingOpen,
  });

  /// Offset of the opening quote (or of the `r` of a raw string).
  final int start;

  /// Offset just after the closing quote.
  final int end;

  /// Decoded text; each interpolation is replaced by [interpolationMarker].
  final String value;
  final bool interpolated;

  /// Text before the first interpolation (the whole value if there is none).
  final String prefix;

  /// Offset of the innermost `(`, `[` or `{` around the literal, or -1.
  final int enclosingOpen;
}

/// A Dart file split into code and string literals, without a full parser.
///
/// [masked] has the same length and line breaks as [text], with comments and
/// literal string contents blanked out. Quotes and code inside `${...}` are
/// kept, so regular expressions over [masked] only ever see real code.
class DartSource {
  DartSource(this.path, this.text) {
    _masked = text.split('');
    _lex(0, stopAtBrace: false);
    masked = _masked.join();
    _matchBrackets();
    _lineStarts = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        _lineStarts.add(i + 1);
      }
    }
  }

  /// Path relative to the project root, with forward slashes.
  final String path;
  final String text;
  late final String masked;
  final List<StringLiteral> literals = <StringLiteral>[];
  late final List<String> _masked;
  final List<_RawLiteral> _raw = <_RawLiteral>[];
  final Map<int, int> _closeOf = <int, int>{};
  final Map<int, int> _openOf = <int, int>{};
  late final List<int> _lineStarts;

  /// 1-based line of [offset].
  int lineOf(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low + 1;
  }

  /// The full source line containing [offset].
  String lineText(int offset) {
    final line = lineOf(offset);
    final start = _lineStarts[line - 1];
    final end = line < _lineStarts.length ? _lineStarts[line] - 1 : text.length;
    return text.substring(start, end);
  }

  /// Offset of the bracket closing the one opened at [open], or -1.
  int closeOf(int open) => _closeOf[open] ?? -1;

  /// Offset of the bracket opening the one closed at [close], or -1.
  int openOf(int close) => _openOf[close] ?? -1;

  /// Masked code before [offset], at most [window] characters.
  String codeBefore(int offset, [int window = 160]) =>
      masked.substring(offset - window < 0 ? 0 : offset - window, offset);

  /// Masked code after [offset], at most [window] characters.
  String codeAfter(int offset, [int window = 160]) =>
      masked.substring(offset, offset + window > masked.length ? masked.length : offset + window);

  void _blank(int i) {
    if (i < _masked.length && _masked[i] != '\n') {
      _masked[i] = ' ';
    }
  }

  static bool _isIdentChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;

  /// Lexes code from [i]. With [stopAtBrace], returns after the `}` that
  /// closes an interpolation; otherwise runs to the end of the text.
  int _lex(int i, {required bool stopAtBrace}) {
    var depth = 0;
    final n = text.length;
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (c == 0x2F && i + 1 < n && text.codeUnitAt(i + 1) == 0x2F) {
        while (i < n && text.codeUnitAt(i) != 0x0A) {
          _blank(i++);
        }
        continue;
      }
      if (c == 0x2F && i + 1 < n && text.codeUnitAt(i + 1) == 0x2A) {
        i = _blockComment(i);
        continue;
      }
      final isRawPrefix = (c == 0x72 || c == 0x52) &&
          i + 1 < n &&
          (text.codeUnitAt(i + 1) == 0x27 || text.codeUnitAt(i + 1) == 0x22) &&
          (i == 0 || !_isIdentChar(text.codeUnitAt(i - 1)));
      if (isRawPrefix) {
        i = _string(i, i + 1, raw: true);
        continue;
      }
      if (c == 0x27 || c == 0x22) {
        i = _string(i, i, raw: false);
        continue;
      }
      if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        if (stopAtBrace && depth == 0) {
          _blank(i);
          return i + 1;
        }
        depth--;
      }
      i++;
    }
    return i;
  }

  int _blockComment(int i) {
    final n = text.length;
    var depth = 0;
    while (i < n) {
      if (text.startsWith('/*', i)) {
        depth++;
        _blank(i);
        _blank(i + 1);
        i += 2;
      } else if (text.startsWith('*/', i)) {
        depth--;
        _blank(i);
        _blank(i + 1);
        i += 2;
        if (depth == 0) {
          return i;
        }
      } else {
        _blank(i++);
      }
    }
    return i;
  }

  int _string(int start, int quoteAt, {required bool raw}) {
    final n = text.length;
    final quote = text[quoteAt];
    final triple = text.startsWith(quote * 3, quoteAt);
    final closing = triple ? quote * 3 : quote;
    if (raw) {
      _blank(start);
    }
    var i = quoteAt + closing.length;
    final value = StringBuffer();
    String? prefix;
    var interpolated = false;
    while (i < n) {
      if (text.startsWith(closing, i)) {
        i += closing.length;
        break;
      }
      final c = text[i];
      if (!triple && c == '\n') {
        break; // Unterminated literal: stop at the end of the line.
      }
      if (!raw && c == r'\' && i + 1 < n) {
        final (decoded, length) = _escape(i);
        value.write(decoded);
        for (var k = 0; k < length; k++) {
          _blank(i + k);
        }
        i += length;
        continue;
      }
      if (!raw && c == r'$' && i + 1 < n) {
        final next = text.codeUnitAt(i + 1);
        if (next == 0x7B) {
          interpolated = true;
          prefix ??= value.toString();
          value.write(interpolationMarker);
          _blank(i);
          _blank(i + 1);
          i = _lex(i + 2, stopAtBrace: true);
          continue;
        }
        if (_isIdentStart(next)) {
          interpolated = true;
          prefix ??= value.toString();
          value.write(interpolationMarker);
          _blank(i++);
          while (i < n && _isIdentChar(text.codeUnitAt(i)) && text[i] != r'$') {
            _blank(i++);
          }
          continue;
        }
      }
      value.write(c);
      _blank(i++);
    }
    final decoded = value.toString();
    _raw.add(_RawLiteral(start, i, decoded, interpolated, prefix ?? decoded));
    return i;
  }

  (String, int) _escape(int i) {
    final next = text[i + 1];
    switch (next) {
      case 'n':
        return ('\n', 2);
      case 't':
        return ('\t', 2);
      case 'r':
        return ('\r', 2);
      case 'b':
        return ('\b', 2);
      case 'f':
        return ('\f', 2);
      case 'v':
        return ('\v', 2);
      case 'x':
        final hex = RegExp('[0-9a-fA-F]{2}').matchAsPrefix(text, i + 2);
        if (hex != null) {
          return (String.fromCharCode(int.parse(hex[0]!, radix: 16)), 4);
        }
        return ('x', 2);
      case 'u':
        final braced = RegExp(r'\{([0-9a-fA-F]{1,6})\}').matchAsPrefix(text, i + 2);
        if (braced != null) {
          return (String.fromCharCode(int.parse(braced[1]!, radix: 16)), 2 + braced[0]!.length);
        }
        final hex = RegExp('[0-9a-fA-F]{4}').matchAsPrefix(text, i + 2);
        if (hex != null) {
          return (String.fromCharCode(int.parse(hex[0]!, radix: 16)), 6);
        }
        return ('u', 2);
      default:
        return (next, 2);
    }
  }

  void _matchBrackets() {
    final stack = <int>[];
    final starts = _raw.map((l) => l.start).toList()..sort();
    final enclosing = <int, int>{};
    var nextLiteral = 0;
    for (var i = 0; i < masked.length; i++) {
      while (nextLiteral < starts.length && starts[nextLiteral] == i) {
        enclosing[i] = stack.isEmpty ? -1 : stack.last;
        nextLiteral++;
      }
      final c = masked.codeUnitAt(i);
      if (c == 0x28 || c == 0x5B || c == 0x7B) {
        stack.add(i);
      } else if (c == 0x29 || c == 0x5D || c == 0x7D) {
        if (stack.isNotEmpty) {
          final open = stack.removeLast();
          _closeOf[open] = i;
          _openOf[i] = open;
        }
      }
    }
    _raw.sort((a, b) => a.start.compareTo(b.start));
    for (final raw in _raw) {
      literals.add(StringLiteral(
        start: raw.start,
        end: raw.end,
        value: raw.value,
        interpolated: raw.interpolated,
        prefix: raw.prefix,
        enclosingOpen: enclosing[raw.start] ?? -1,
      ));
    }
  }

  /// Splits the top-level arguments of the call whose `(` is at [open] into
  /// `name → expression` (positional arguments get `$0`, `$1`, ...).
  Map<String, String> argumentsOf(int open) {
    final close = closeOf(open);
    if (close < 0) {
      return const <String, String>{};
    }
    final args = <String, String>{};
    var depth = 0;
    var segmentStart = open + 1;
    var positional = 0;
    void flush(int end) {
      final raw = masked.substring(segmentStart, end);
      final original = text.substring(segmentStart, end).trim();
      final named = RegExp(r'^\s*([A-Za-z_]\w*)\s*:(?!:)').firstMatch(raw);
      if (named != null) {
        final valueStart = segmentStart + named.end;
        args[named[1]!] = text.substring(valueStart, end).trim();
      } else if (original.isNotEmpty) {
        args['\$${positional++}'] = original;
      }
    }

    for (var i = open + 1; i < close; i++) {
      final c = masked.codeUnitAt(i);
      if (c == 0x28 || c == 0x5B || c == 0x7B) {
        depth++;
      } else if (c == 0x29 || c == 0x5D || c == 0x7D) {
        depth--;
      } else if (c == 0x2C && depth == 0) {
        flush(i);
        segmentStart = i + 1;
      }
    }
    flush(close);
    return args;
  }
}

class _RawLiteral {
  _RawLiteral(this.start, this.end, this.value, this.interpolated, this.prefix);

  final int start;
  final int end;
  final String value;
  final bool interpolated;
  final String prefix;
}
