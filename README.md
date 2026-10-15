[العربية](README.ar.md)

<p align="center"><img src="https://raw.githubusercontent.com/youssef336/flutter_l10n_watch/main/screenshots/banner.png" alt="flutter_l10n_watch banner" width="100%"></p>

<h1 align="center">Flutter L10n Watch</h1>

<p align="center">
  A translation health check for Flutter projects: missing keys, broken placeholders, Arabic plurals, unused and undefined keys, hardcoded strings and RTL smells, in one command.
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_l10n_watch"><img src="https://img.shields.io/pub/v/flutter_l10n_watch?style=for-the-badge&logo=dart&label=pub.dev" alt="pub.dev"/></a>
  <img src="https://img.shields.io/badge/Dart-CLI-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart CLI">
  <img src="https://img.shields.io/badge/Flutter-l10n-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/easy__localization-JSON-6E4C9E?style=for-the-badge" alt="easy_localization">
  <img src="https://img.shields.io/badge/gen__l10n-ARB-2ea44f?style=for-the-badge" alt="gen_l10n ARB">
  <img src="https://img.shields.io/badge/RTL-ready-F7931E?style=for-the-badge" alt="RTL">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT">
</p>

> **English summary.** `l10n_watch` is a zero-setup Dart CLI that audits the translations of a
> Flutter app. It detects the setup on its own (easy_localization JSON with nested keys and the
> generated `LocaleKeys` class, gen_l10n / intl_utils ARB with ICU messages, or plain JSON maps),
> then reports: keys missing per locale (and keys only some locales have), empty values, values
> identical to the base language, placeholder mismatches (`{}`, `{name}`, ICU arguments), plural
> forms each language needs (Arabic: zero/one/two/few/many/other), malformed ICU, ARB placeholder
> metadata out of sync, keys used in code but not defined, keys defined but never used (with
> `'status_$x'.tr()` treated as a *possibly used* prefix), translations long enough to overflow,
> hardcoded strings in `Text(...)` / `hintText:` / `tooltip:` and friends, and RTL smells such as
> `EdgeInsets.only(left:)` or `Alignment.centerLeft`. `check` exits 1 on errors so it fits CI;
> `report` prints text, Markdown, JSON or GitHub annotations. Everything is configurable in
> `l10n_watch.yaml`. Pure Dart, no Flutter SDK needed to run it, no network.

A command-line tool that checks all the translations of a Flutter project in one command: what is
missing, what was never translated, which placeholder got broken, which Arabic plural forms are
missing, which text is hardcoded in the code, and what will break the screen when the language
is right-to-left.

## ✨ What it checks

| Check | id | Default |
|---|---|---|
| 🔑 Keys missing from a locale compared with the base locale | `missing_translation` | error |
| ➕ Keys present in a locale but not in the base locale | `extra_translation` | warning |
| ⬜ Empty values | `empty_value` | warning |
| 🪞 Value identical to the English one (probably forgotten) or marked `TODO:` | `untranslated` | warning |
| 🧩 Placeholders differ: `{}`, `{name}` and ICU | `placeholder_mismatch` | error |
| 🔢 Plural forms missing for the language (Arabic needs zero/one/two/few/many/other) | `plural_forms` | warning |
| 💥 Broken ICU message, a plural without `other`, or ICU inside easy_localization JSON | `invalid_message` | error |
| 🏷 `@key.placeholders` in the ARB does not match the message | `arb_metadata` | warning |
| ❓ Key used in the code but not defined | `undefined_key` | error |
| 🗑 Key defined but never used | `unused_key` | warning |
| 🌀 Key built at runtime (`'status_$x'.tr()`) | `dynamic_key` | info |
| 📏 Translation much longer than the source (overflow risk) | `length_risk` | info |
| ✍️ Text written in the code instead of coming from the translations | `hardcoded_string` | warning |
| ↔️ Things that break in RTL | `rtl_smell` | info |

## 🧠 It understands the project on its own

- **easy_localization**: finds the translations folder from `EasyLocalization(path: ...)` in the
  code, from `assets` in `pubspec.yaml`, or from the well-known locations (`assets/translations`,
  `assets/lang`, …). It understands nested keys (`cart.title`), plural objects (`one`/`other`),
  links (`@:key`), and the base locale from `fallbackLocale`. It counts usage from `'key'.tr()`,
  `tr('key')`, `context.tr('key')`, `'key'.plural(n)`, `Text('key').tr()` and
  `(cond ? 'a' : 'b').tr()`, and from `LocaleKeys.foo_bar`: it reads the generated `LocaleKeys`
  class if it exists, and if it does not, it maps `foo.bar` and `foo_bar` to the same name the
  way the generator does.
- **gen_l10n (ARB)**: reads `l10n.yaml` (`arb-dir`, `template-arb-file`, `output-class` and
  `use-escaping`), and understands full ICU: placeholders, plural, select and nesting. Usage is
  counted from `AppLocalizations.of(context)!.key`, `context.l10n.key`, `S.of(context).key` and
  `S.current.key`, and from any variable created from them
  (`final t = AppLocalizations.of(context)!;` or a field of type `AppLocalizations`).
  **intl_utils** (`flutter_intl` in pubspec, class `S`) works too.
- **Plain JSON** for any other library: `format: json`, with placeholders matched by the regex
  you choose.
- Generated files (`*.g.dart`, `generated/`, any file starting with "GENERATED / DO NOT EDIT",
  and the generated localizations class) are not counted for usage or for hardcoded strings.

## 🚀 Installation

```bash
dart pub global activate flutter_l10n_watch
cd my_flutter_app
l10n_watch check
```

Or inside the project as a dev dependency:

```yaml
dev_dependencies:
  flutter_l10n_watch: ^0.1.0
```

```bash
dart run flutter_l10n_watch:l10n_watch check
```

## 🕹 Commands

```bash
l10n_watch check                        # all checks, exit 1 if there is an error
l10n_watch check --fail-on warning      # make warnings fail the CI too
l10n_watch check --checks missing_translation,placeholder_mismatch
l10n_watch report --format markdown -o l10n.md   # for a PR comment or job summary
l10n_watch report --format json                  # for any other tool
l10n_watch report --format github                # annotations on the PR lines
l10n_watch report --all                          # without truncating long lists
l10n_watch fix --sort --dry-run                  # shows what it would change without writing
l10n_watch fix --sort                            # sorts the keys in every file
l10n_watch fix --add-missing                     # adds missing keys with the base value + "TODO: "
l10n_watch init                                  # writes an l10n_watch.yaml with every setting
```

`fix` **does nothing without a flag**, and never touches a file it cannot read. The values it
adds are prefixed with `TODO: ` so the `untranslated` check keeps catching them until someone
translates them.

## 🖥 What the report looks like

```text
l10n_watch 0.1.0 · easy_localization · assets/translations · base en · 3 locales · 16 keys · 2 Dart files

✖ Missing translations (1 error) [missing_translation]
  ar: missing "cart.checkout"

✖ Placeholder mismatch (2 errors) [placeholder_mismatch]
  ar: "greeting" has {user}, en has {name}
  ar: "items_count" has {}, en has {}×2

⚠ Plural forms missing for the language (1 warning) [plural_forms]
  ar: "apples" plural lacks zero, two, few, many (ar uses zero/one/two/few/many/other)

✖ Keys used in code but not defined (2 errors) [undefined_key]
  lib/home.dart:29  "missing_key" is used ('key'.tr()) but not defined in en
  lib/home.dart:30  "removed_key" is used (LocaleKeys.removed_key) but not defined in en

ℹ Dynamic keys (possibly used) (3 infos) [dynamic_key]
  lib/home.dart:27  "'status_$status'" → prefix "status_" matches 2 keys (2 otherwise unused)

⚠ Hardcoded user-facing strings (5 warnings) [hardcoded_string]
  top files:
       5  lib/home.dart
  lib/home.dart:35  "Hardcoded hello" in Text()
  lib/home.dart:39  "Type here" in hintText:

ℹ RTL smells (6 infos) [rtl_smell]
     1  EdgeInsets.only(left/right) → EdgeInsetsDirectional.only(start/end)
     1  Alignment.centerLeft → AlignmentDirectional.centerStart
     1  Positioned(left/right) → PositionedDirectional(start/end)

✖ 8 errors · 14 warnings · 10 info
```

## ⚙️ Configuration (`l10n_watch.yaml`)

Everything is optional. Without the file the tool runs with the defaults.

```yaml
format: auto                  # auto | easy_localization | arb | json
translations_dir: assets/translations
base_locale: en
source_dirs: [lib]
exclude: ['lib/legacy/**']    # on top of the defaults (*.g.dart, generated/, ...)
ignore_keys: ['^debug_']      # regex, ignored by every check
locale_keys_class: LocaleKeys
tr_functions: [tr, plural, trExists]
arb_accessors: ['context.loc']        # if you have a shortcut other than context.l10n
placeholder_pattern: '\{\{\s*(\w*)\s*\}\}'   # for format: json only

untranslated:
  min_letters: 3              # shorter than this (OK, ID, 1st) is not counted
  allow: [Visa, PayPal, WhatsApp]     # words that stay the same in every language
  ignore_keys: ['^country_']
  todo_marker: 'TODO: '

length:
  ratio: 1.6
  min_chars: 20

hardcoded:
  widgets: [Text, SelectableText, AutoSizeText]
  named_args: [hintText, labelText, helperText, errorText, tooltip, TextSpan.text, Tooltip.message]
  ignore: ['^Lorem']

plural_rules:                 # on top of the default CLDR table
  fr: [one, many, other]

severity:                     # error | warning | info | off
  unused_key: error
  rtl_smell: off

fail_on: error                # check returns 1 from this level and above
```

A line containing `// l10n-ignore` is not reported by `hardcoded_string` or `rtl_smell`.

## 🤖 In CI

```yaml
- run: dart pub global activate flutter_l10n_watch
- run: l10n_watch report --format github      # annotations on the PR
- run: l10n_watch report --format markdown >> "$GITHUB_STEP_SUMMARY"
- run: l10n_watch check                       # fails the job if there is an error
```

| exit code | Meaning |
|---|---|
| `0` | Nothing reached `fail_on` |
| `1` | There are findings that reached `fail_on` (`check` only) |
| `2` | Invalid configuration, or the translation files could not be found |

## ❓ FAQ

**Why is a key reported as unused when I am sure it is used?**
Most likely the key is built at runtime from a variable (`tr(item.titleKey)`). Those cases show
up in `dynamic_key` with their location in the code, so if you see a line there doing that, add
the keys to `ignore_keys`. If the key is written as a string anywhere in the code (even in a map
or a const list) it counts as used.

**How is `'status_$x'.tr()` handled?**
The constant part (`status_`) becomes a prefix, and every key starting with it is reported as
"possibly used" in `dynamic_key` instead of `unused_key`.

**English only needs `one` and `other`, so why does Arabic get a warning?**
Arabic has six plural forms in CLDR. If `two` is missing, for example, "٢ رسالة" ("2 messages")
will be shown with the `other` form, which is grammatically wrong. `=0`, `=1` and `=2` in ICU
count as zero, one and two.

**A word like "Email" or the brand name is reported as untranslated.**
Add it to `untranslated.allow`. Words shorter than 3 letters, numbers, links and emails are not
counted in the first place. And if the locale is a regional variant of the base language
(`en_GB` with `en`), it is not checked.

**JSON with `{count, plural, ...}` in easy_localization?**
easy_localization does not understand ICU, so the sentence is shown to the user as is. That is
why it is reported as `invalid_message`; the fix is a plural object
(`{"one": "...", "other": "..."}`) with `.plural()`.

**Can `fix` break the files?**
It writes valid JSON with the same indentation, keeps the trailing newline, and does nothing if
any file cannot be read. What changes: escapes like `é` are written as the plain character.
Try `--dry-run` first.

## ⚖️ Limitations

- It is not a full Dart parser: it reads the code with a lexer that understands strings, comments
  and interpolation, and the rest is regex. Very unusual usage patterns may slip past it (and the
  key is then reported as unused).
- Any string in the code that equals a key name makes that key "used", so the unused count may be
  lower than the real one (safer than telling you to delete something that is used).
- In ARB, any `.name` after a dot that equals a key name counts as a usage. A key named `title`,
  for example, will most likely look used.
- easy_localization: one JSON file per locale only (not a folder per locale, nor CSV/YAML).
- `hardcoded_string` looks at the first argument of `Text` and the types you configure, and at the
  known named args only. A string stored in a variable and displayed later is not caught.
- `length_risk` compares character counts, not the real width on screen.
- The plural table inside the tool is a condensed CLDR table for integers, and you can adjust it
  with `plural_rules`.

## 🛠 Development

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart run bin/l10n_watch.dart check -p test/fixtures/easy_app
```

## 🏗 Project structure

| File | Role |
|---|---|
| `bin/l10n_watch.dart` | executable |
| `lib/src/cli.dart` | commands, options, exit codes |
| `lib/src/config.dart` | `l10n_watch.yaml` parsing and defaults (incl. CLDR plural table) |
| `lib/src/project.dart` | setup detection, locale files, Dart sources |
| `lib/src/catalog.dart` | JSON / ARB loaders, nested keys, plural and gender groups |
| `lib/src/message.dart` | `{}` / `{name}` placeholders, links and a small ICU parser |
| `lib/src/dart_source.dart` | Dart lexer: string literals, comments, interpolation, brackets |
| `lib/src/usage.dart` | key references: `tr`, `LocaleKeys`, `AppLocalizations`, dynamic keys |
| `lib/src/checks/` | catalog checks and code checks |
| `lib/src/report/reporters.dart` | text, Markdown, JSON and GitHub output |
| `lib/src/fixer.dart` | `fix --sort` / `--add-missing` |
| `test/fixtures/` | an easy_localization app and a gen_l10n app with one problem per check |

## 📄 License

[MIT](LICENSE)

## 👤 Author

**Youssef Belal Zakaria** · [GitHub @youssef336](https://github.com/youssef336)

⭐ If you like this project, give it a star!
