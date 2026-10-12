import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'home.dart';

void main() {
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const HomePage(),
    ),
  );
}
