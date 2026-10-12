import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

class Home extends StatelessWidget {
  const Home({super.key, required this.strings});

  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(l10n.appTitle),
        Text(AppLocalizations.of(context)!.hello('Sam')),
        Text(context.l10n.itemCount(3)),
        Text(strings.genderMsg('male')),
        Text(l10n.undeclared('x') + l10n.declaredUnused),
        Text(l10n.doesNotExist),
        Text(l10n.localeName),
        TextButton(onPressed: null, child: Text(context.l10n.saveButton)),
        const Text('Hardcoded ARB text'),
        const Padding(padding: EdgeInsetsDirectional.only(start: 8)),
      ],
    );
  }
}
