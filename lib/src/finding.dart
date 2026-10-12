/// How serious a finding is. `off` disables a check entirely.
enum Severity {
  error,
  warning,
  info,
  off;

  /// Parses `error`, `warning`/`warn`, `info` or `off`/`none`/`ignore`.
  static Severity parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'error':
        return Severity.error;
      case 'warning':
      case 'warn':
        return Severity.warning;
      case 'info':
        return Severity.info;
      case 'off':
      case 'none':
      case 'ignore':
        return Severity.off;
    }
    throw FormatException('Unknown severity "$raw"');
  }

  /// True when this severity is at least as serious as [other].
  bool atLeast(Severity other) => index <= other.index;
}

/// Identifiers of every check, in report order.
abstract final class CheckId {
  static const missingTranslation = 'missing_translation';
  static const extraTranslation = 'extra_translation';
  static const emptyValue = 'empty_value';
  static const untranslated = 'untranslated';
  static const placeholderMismatch = 'placeholder_mismatch';
  static const pluralForms = 'plural_forms';
  static const invalidMessage = 'invalid_message';
  static const arbMetadata = 'arb_metadata';
  static const undefinedKey = 'undefined_key';
  static const unusedKey = 'unused_key';
  static const dynamicKey = 'dynamic_key';
  static const lengthRisk = 'length_risk';
  static const hardcodedString = 'hardcoded_string';
  static const rtlSmell = 'rtl_smell';

  static const all = <String>[
    missingTranslation,
    extraTranslation,
    emptyValue,
    untranslated,
    placeholderMismatch,
    pluralForms,
    invalidMessage,
    arbMetadata,
    undefinedKey,
    unusedKey,
    dynamicKey,
    lengthRisk,
    hardcodedString,
    rtlSmell,
  ];

  static const defaultSeverity = <String, Severity>{
    missingTranslation: Severity.error,
    extraTranslation: Severity.warning,
    emptyValue: Severity.warning,
    untranslated: Severity.warning,
    placeholderMismatch: Severity.error,
    pluralForms: Severity.warning,
    invalidMessage: Severity.error,
    arbMetadata: Severity.warning,
    undefinedKey: Severity.error,
    unusedKey: Severity.warning,
    dynamicKey: Severity.info,
    lengthRisk: Severity.info,
    hardcodedString: Severity.warning,
    rtlSmell: Severity.info,
  };

  static const titles = <String, String>{
    missingTranslation: 'Missing translations',
    extraTranslation: 'Keys only in non-base locales',
    emptyValue: 'Empty values',
    untranslated: 'Probably untranslated (same as base)',
    placeholderMismatch: 'Placeholder mismatch',
    pluralForms: 'Plural forms missing for the language',
    invalidMessage: 'Invalid messages',
    arbMetadata: 'ARB metadata out of sync',
    undefinedKey: 'Keys used in code but not defined',
    unusedKey: 'Unused keys',
    dynamicKey: 'Dynamic keys (possibly used)',
    lengthRisk: 'Overflow risk (much longer than base)',
    hardcodedString: 'Hardcoded user-facing strings',
    rtlSmell: 'RTL smells',
  };
}

/// One problem reported by a check.
class Finding {
  const Finding({
    required this.check,
    required this.severity,
    required this.message,
    this.locale,
    this.key,
    this.file,
    this.line,
    this.data = const <String, Object?>{},
  });

  final String check;
  final Severity severity;
  final String message;
  final String? locale;
  final String? key;

  /// Path relative to the project root, with forward slashes.
  final String? file;
  final int? line;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
        'check': check,
        'severity': severity.name,
        'message': message,
        if (locale != null) 'locale': locale,
        if (key != null) 'key': key,
        if (file != null) 'file': file,
        if (line != null) 'line': line,
        if (data.isNotEmpty) 'data': data,
      };

  @override
  String toString() => '[${severity.name}] $check: $message';
}
