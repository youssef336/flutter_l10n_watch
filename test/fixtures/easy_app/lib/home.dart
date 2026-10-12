import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'generated/locale_keys.g.dart';

const _brandKeys = ['brand_line'];

class HomePage extends StatelessWidget {
  const HomePage({super.key, this.status = 'active', this.dynamicKey = 'x'});

  final String status;
  final String dynamicKey;

  @override
  Widget build(BuildContext context) {
    final count = 3;
    // Text('Commented out text') must not be reported.
    return Column(
      children: [
        Text('app_title'.tr()),
        Text(tr('greeting', namedArgs: {'name': 'Sam'})),
        Text(LocaleKeys.items_count.tr(args: ['1', '2'])),
        Text(LocaleKeys.cart_title.tr()),
        Text(context.tr('cart.empty')),
        Text(LocaleKeys.cart_checkout.tr()),
        Text('apples'.plural(count)),
        Text('status_$status'.tr()),
        Text(tr(dynamicKey)),
        Text('missing_key'.tr()),
        Text(LocaleKeys.removed_key.tr()),
        Text(_brandKeys.first.tr()),
        const Text('ok').tr(),
        Text('about'.tr()),
        Text((count > 1 ? 'long_label' : 'app_title').tr()),
        const Text('Hardcoded hello'),
        Text('$count'),
        Text('Total: $count items'),
        const Text('Ignored on purpose'), // l10n-ignore
        const TextField(decoration: InputDecoration(hintText: 'Type here')),
        Tooltip(message: 'Tooltip words', child: const SizedBox()),
        RichText(text: const TextSpan(text: 'Span words')),
        const Padding(padding: EdgeInsets.only(left: 8)),
        const Padding(padding: EdgeInsets.only(left: 8, right: 8)),
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 12, 0)),
        const Align(alignment: Alignment.centerLeft),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        const Text('x', textDirection: TextDirection.ltr),
        const Text('y', textAlign: TextAlign.right),
        const Stack(children: [Positioned(left: 0, top: 0, child: SizedBox())]),
        const Stack(children: [Positioned(left: 0, right: 0, child: SizedBox())]),
      ],
    );
  }
}
