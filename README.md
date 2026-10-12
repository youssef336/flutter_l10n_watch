<h1 align="center">Flutter L10n Watch</h1>

<p align="center">
  A translation health check for Flutter projects: missing keys, broken placeholders, Arabic plurals, unused and undefined keys, hardcoded strings and RTL smells, in one command.
</p>

<p align="center">
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

<div dir="rtl">

أداة سطر أوامر بتفحص ترجمات مشروع Flutter كله في أمر واحد: إيه الناقص، وإيه اللي اتنسى
يتترجم، وإيه الـ placeholder اللي اتكسر، وجمع العربي ناقصه إيه، وإيه الكلام المكتوب
hardcoded في الكود، وإيه اللي هيبوّظ الشاشة لما اللغة تبقى من اليمين للشمال.

## ✨ بتفحص إيه

| الفحص | الـ id | الافتراضي |
|---|---|---|
| 🔑 مفاتيح ناقصة في لغة عن اللغة الأساسية | `missing_translation` | error |
| ➕ مفاتيح موجودة في لغة ومش موجودة في الأساسية | `extra_translation` | warning |
| ⬜ قيم فاضية | `empty_value` | warning |
| 🪞 قيمة زي الإنجليزي بالظبط (غالبًا اتنست) أو عليها `TODO:` | `untranslated` | warning |
| 🧩 الـ placeholders مختلفة: `{}` و `{name}` و ICU | `placeholder_mismatch` | error |
| 🔢 صيغ الجمع ناقصة للغة (العربي محتاج zero/one/two/few/many/other) | `plural_forms` | warning |
| 💥 رسالة ICU مكسورة، أو plural من غير `other`، أو ICU جوه JSON بتاع easy_localization | `invalid_message` | error |
| 🏷 الـ `@key.placeholders` في الـ ARB مش ماشية مع الرسالة | `arb_metadata` | warning |
| ❓ مفتاح مستخدم في الكود ومش متعرّف | `undefined_key` | error |
| 🗑 مفتاح متعرّف ومحدش بيستخدمه | `unused_key` | warning |
| 🌀 مفتاح بيتبني وقت التشغيل (`'status_$x'.tr()`) | `dynamic_key` | info |
| 📏 ترجمة أطول بكتير من الأصل (خطر overflow) | `length_risk` | info |
| ✍️ كلام مكتوب في الكود مش من الترجمة | `hardcoded_string` | warning |
| ↔️ حاجات بتبوظ في RTL | `rtl_smell` | info |

## 🧠 بيفهم المشروع لوحده

- **easy_localization**: بيلاقي فولدر الترجمة من `EasyLocalization(path: ...)` في الكود، أو من
  `assets` في `pubspec.yaml`، أو من الأماكن المشهورة (`assets/translations`، `assets/lang`، …).
  بيفهم المفاتيح المتداخلة (`cart.title`)، والـ plural objects (`one`/`other`)، والـ links (`@:key`)،
  واللغة الأساسية من `fallbackLocale`. بيعدّ الاستخدام من `'key'.tr()` و `tr('key')` و
  `context.tr('key')` و `'key'.plural(n)` و `Text('key').tr()` و `(cond ? 'a' : 'b').tr()`،
  ومن `LocaleKeys.foo_bar`: بيقرا كلاس `LocaleKeys` المتولّد لو موجود، ولو مش موجود بيحوّل
  `foo.bar` و `foo_bar` لنفس الاسم زي ما الـ generator بيعمل.
- **gen_l10n (ARB)**: بيقرا `l10n.yaml` (`arb-dir` و `template-arb-file` و `output-class` و
  `use-escaping`)، وبيفهم ICU كامل: placeholders و plural و select و nested. الاستخدام من
  `AppLocalizations.of(context)!.key` و `context.l10n.key` و `S.of(context).key` و `S.current.key`،
  ومن أي متغير اتعمل منهم (`final t = AppLocalizations.of(context)!;` أو field نوعه `AppLocalizations`).
  **intl_utils** (`flutter_intl` في pubspec، كلاس `S`) شغال برضه.
- **JSON عادي** لأي مكتبة تانية: `format: json`، والـ placeholders بالـ regex اللي تختاره.
- الفايلات المتولّدة (`*.g.dart`، `generated/`، أي فايل أوله «GENERATED / DO NOT EDIT»، وكلاس
  الـ localizations المتولّد) مش بتتعد في الاستخدام ولا في الـ hardcoded.

## 🚀 التثبيت

```bash
dart pub global activate --source git https://github.com/youssef336/flutter_l10n_watch.git
cd my_flutter_app
l10n_watch check
```

أو جوه المشروع كـ dev dependency:

```yaml
dev_dependencies:
  flutter_l10n_watch:
    git: https://github.com/youssef336/flutter_l10n_watch.git
```

```bash
dart run flutter_l10n_watch:l10n_watch check
```

## 🕹 الأوامر

```bash
l10n_watch check                        # كل الفحوصات، exit 1 لو فيه error
l10n_watch check --fail-on warning      # خلّي الـ warnings كمان توقّف الـ CI
l10n_watch check --checks missing_translation,placeholder_mismatch
l10n_watch report --format markdown -o l10n.md   # لـ PR comment أو job summary
l10n_watch report --format json                  # لأي أداة تانية
l10n_watch report --format github                # annotations على سطور الـ PR
l10n_watch report --all                          # من غير ما يقص القوايم الطويلة
l10n_watch fix --sort --dry-run                  # يوريك هيغيّر إيه من غير ما يكتب
l10n_watch fix --sort                            # يرتّب المفاتيح في كل الفايلات
l10n_watch fix --add-missing                     # يضيف الناقص بقيمة الأساسية + "TODO: "
l10n_watch init                                  # يكتب l10n_watch.yaml فيه كل الإعدادات
```

`fix` **مش بيعمل أي حاجة من غير flag**، ومش بيلمس فايل مش عارف يقراه. القيم اللي بيضيفها
عليها `TODO: ` عشان فحص `untranslated` يفضل يمسكها لحد ما حد يترجمها.

## 🖥 شكل التقرير

</div>

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

<div dir="rtl">

## ⚙️ الإعدادات (`l10n_watch.yaml`)

كله اختياري. من غير الفايل الأداة شغالة بالافتراضي.

</div>

```yaml
format: auto                  # auto | easy_localization | arb | json
translations_dir: assets/translations
base_locale: en
source_dirs: [lib]
exclude: ['lib/legacy/**']    # فوق الافتراضي (*.g.dart, generated/, ...)
ignore_keys: ['^debug_']      # regex، كل الفحوصات بتتجاهلها
locale_keys_class: LocaleKeys
tr_functions: [tr, plural, trExists]
arb_accessors: ['context.loc']        # لو عندك اختصار تاني غير context.l10n
placeholder_pattern: '\{\{\s*(\w*)\s*\}\}'   # لـ format: json بس

untranslated:
  min_letters: 3              # أقل من كده (OK، ID، 1st) مش بيتحسب
  allow: [Visa, PayPal, WhatsApp]     # كلمات زي ما هي في كل اللغات
  ignore_keys: ['^country_']
  todo_marker: 'TODO: '

length:
  ratio: 1.6
  min_chars: 20

hardcoded:
  widgets: [Text, SelectableText, AutoSizeText]
  named_args: [hintText, labelText, helperText, errorText, tooltip, TextSpan.text, Tooltip.message]
  ignore: ['^Lorem']

plural_rules:                 # فوق جدول CLDR الافتراضي
  fr: [one, many, other]

severity:                     # error | warning | info | off
  unused_key: error
  rtl_smell: off

fail_on: error                # check بيرجع 1 من المستوى ده وأعلى
```

<div dir="rtl">

سطر فيه `// l10n-ignore` مش بيطلع في `hardcoded_string` ولا `rtl_smell`.

## 🤖 في الـ CI

</div>

```yaml
- run: dart pub global activate --source git https://github.com/youssef336/flutter_l10n_watch.git
- run: l10n_watch report --format github      # annotations على الـ PR
- run: l10n_watch report --format markdown >> "$GITHUB_STEP_SUMMARY"
- run: l10n_watch check                       # يوقّف الـ job لو فيه error
```

<div dir="rtl">

| exit code | يعني |
|---|---|
| `0` | مفيش حاجة وصلت لـ `fail_on` |
| `1` | فيه findings وصلت لـ `fail_on` (في `check` بس) |
| `2` | إعدادات غلط، أو مش لاقي فايلات الترجمة |

## ❓ أسئلة

**ليه مفتاح بيطلع unused وأنا متأكد إنه مستخدم؟**
غالبًا المفتاح بيتبني وقت التشغيل من متغير (`tr(item.titleKey)`). الحالات دي بتطلع في
`dynamic_key` بمكانها في الكود، فلو شايف هناك سطر بيعمل كده، ضيف المفاتيح في `ignore_keys`.
لو المفتاح متكتب كـ string في أي حتة في الكود (حتى في map أو const list) بيتحسب مستخدم.

**`'status_$x'.tr()` بيتعامل معاه إزاي؟**
الجزء الثابت (`status_`) بيبقى prefix، وكل المفاتيح اللي بتبدأ بيه بتطلع «ممكن تكون مستخدمة»
في `dynamic_key` بدل `unused_key`.

**الإنجليزي محتاج `one` و `other` بس، ليه العربي بيطلع warning؟**
العربي فيه ست صيغ جمع في CLDR. لو ناقص `two` مثلًا، «٢ رسالة» هتطلع بصيغة `other`
وده غلط لغويًا. `=0` و `=1` و `=2` في ICU بيتحسبوا zero و one و two.

**كلمة زي «Email» أو اسم البراند بتطلع untranslated.**
ضيفها في `untranslated.allow`. الكلمات اللي أقل من 3 حروف، والأرقام، واللينكات، والإيميلات
مش بتتحسب من الأول. ولو اللغة لهجة من نفس اللغة الأساسية (`en_GB` مع `en`) مش بتتفحص.

**JSON فيه `{count, plural, ...}` مع easy_localization؟**
easy_localization مش بيفهم ICU، فالجملة بتظهر للمستخدم زي ما هي. علشان كده بتطلع `invalid_message`،
والحل plural object (`{"one": "...", "other": "..."}`) مع `.plural()`.

**`fix` ممكن يبوّظ الفايلات؟**
بيكتب JSON صحيح بنفس الـ indentation، وبيحافظ على السطر الفاضي في الآخر، ومش بيعمل حاجة
لو فيه فايل مش بيتقري. اللي بيتغيّر: الـ escapes زي `é` بتتكتب كحرف عادي. جرّب
`--dry-run` الأول.

## ⚖️ الحدود

- مش parser كامل لـ Dart: بيقرا الكود بـ lexer بيفهم الـ strings والـ comments والـ interpolation،
  والباقي regex. أنماط غريبة جدًا للاستخدام ممكن تفوته (وساعتها المفتاح يطلع unused).
- أي string في الكود بيساوي اسم مفتاح بيخلّي المفتاح «مستخدم»، فالـ unused ممكن يقل عن الحقيقة
  (أأمن من إنه يقولك امسح حاجة مستخدمة).
- في ARB، أي `.name` بعد نقطة بيساوي اسم مفتاح بيتحسب استخدام. مفتاح اسمه `title` مثلًا
  غالبًا هيبان مستخدم.
- easy_localization: فايل JSON واحد لكل لغة بس (مش فولدر لكل لغة، ولا CSV/YAML).
- `hardcoded_string` بيدور في أول argument لـ `Text` والأنواع اللي تحددها، وفي الـ named args
  المعروفة بس. string متخزّن في متغير وبعدين اتعرض مش هيتمسك.
- `length_risk` بيقارن عدد الحروف مش العرض الحقيقي على الشاشة.
- جدول الجمع جوه الأداة مختصر من CLDR للأعداد الصحيحة، وتقدر تعدّله من `plural_rules`.

</div>

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
