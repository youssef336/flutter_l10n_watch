# Example

A small easy_localization app with a few typical translation problems, and what
`l10n_watch` reports for it.

## Project

```text
my_shop/
├── pubspec.yaml
├── assets/translations/
│   ├── en.json
│   └── ar.json
└── lib/main.dart
```

`pubspec.yaml`:

```yaml
name: my_shop
environment:
  sdk: ^3.6.0
dependencies:
  flutter:
    sdk: flutter
  easy_localization: ^3.0.0
flutter:
  assets:
    - assets/translations/
```

`assets/translations/en.json` (the base locale):

```json
{
  "greeting": "Hello {name}!",
  "cart": {
    "title": "Your cart",
    "checkout": "Proceed to checkout"
  },
  "messages": {
    "one": "{} message",
    "other": "{} messages"
  },
  "old_banner": "Summer sale"
}
```

`assets/translations/ar.json`:

```json
{
  "greeting": "أهلًا {user}!",
  "cart": {
    "title": "عربة التسوق"
  },
  "messages": {
    "one": "رسالة واحدة",
    "other": "{} رسالة"
  },
  "old_banner": "تخفيضات الصيف"
}
```

`lib/main.dart`:

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        children: [
          Text('greeting'.tr(namedArgs: {'name': 'Sara'})),
          Text('cart.title'.tr()),
          Text('messages'.plural(count)),
          Text('cart.coupon'.tr()),
          const Text('Pay now'),
        ],
      ),
    );
  }
}
```

## Run it

Install the CLI and run `check` from the project folder (or pass `-p <folder>`):

```bash
dart pub global activate flutter_l10n_watch
cd my_shop
l10n_watch check --no-color
```

No configuration is needed: the setup (easy_localization), the translations folder (from
`assets` in `pubspec.yaml`) and the base locale are detected automatically.

```text
l10n_watch 0.1.0 · easy_localization · assets/translations · base en · 2 locales · 5 keys · 1 Dart file

✖ Missing translations (1 error) [missing_translation]
  ar: missing "cart.checkout"

✖ Placeholder mismatch (1 error) [placeholder_mismatch]
  ar: "greeting" has {user}, en has {name}

⚠ Plural forms missing for the language (1 warning) [plural_forms]
  ar: "messages" plural lacks zero, two, few, many (ar uses zero/one/two/few/many/other)

✖ Keys used in code but not defined (1 error) [undefined_key]
  lib/main.dart:18  "cart.coupon" is used ('key'.tr()) but not defined in en

⚠ Unused keys (2 warnings) [unused_key]
  "cart.checkout" is never referenced in lib
  "old_banner" is never referenced in lib

⚠ Hardcoded user-facing strings (1 warning) [hardcoded_string]
  top files:
       1  lib/main.dart
  lib/main.dart:19  "Pay now" in Text()

ℹ RTL smells (1 info) [rtl_smell]
     1  EdgeInsets.only(left/right) → EdgeInsetsDirectional.only(start/end)
  top files:
       1  lib/main.dart

✖ 3 errors · 4 warnings · 1 info
```

`check` exits with `1` because there are errors (`fail_on: error` by default).

## Fix and report

```bash
# Preview, then add the missing "cart.checkout" to ar.json with the English value + "TODO: "
l10n_watch fix --add-missing --dry-run
l10n_watch fix --add-missing

# Sort keys in every locale file
l10n_watch fix --sort

# Reports for CI
l10n_watch report --format github
l10n_watch report --format markdown -o l10n.md
l10n_watch report --format json
```

## Configure

`l10n_watch init` writes an `l10n_watch.yaml` with every option. For this project, for example:

```yaml
base_locale: en
ignore_keys: ['^old_']        # skip legacy keys in every check
severity:
  rtl_smell: warning          # error | warning | info | off
fail_on: error
```
