## 0.1.0

First release.

- Auto-detects easy_localization JSON, gen_l10n / intl_utils ARB and plain JSON setups.
- Checks: missing and extra keys, empty values, probably-untranslated values, placeholder
  mismatches (`{}`, `{name}`, ICU), plural forms per language (Arabic needs all six), invalid
  ICU messages, ARB placeholder metadata, keys used in code but not defined, unused keys,
  dynamic keys (`'status_$x'.tr()`), overflow risk, hardcoded user-facing strings and RTL smells.
- Commands: `check` (exit 1 on errors), `report --format text|markdown|json|github`,
  `fix --sort` / `fix --add-missing` (opt-in only), `init`.
- Config file `l10n_watch.yaml`: paths, base locale, ignore regexes, thresholds, severity per check.
