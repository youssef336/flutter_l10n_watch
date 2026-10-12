import 'package:flutter_l10n_watch/src/message.dart';
import 'package:test/test.dart';

void main() {
  group('analyzeSimple', () {
    test('counts positional and named placeholders', () {
      final info = analyzeSimple('Hi {name}, you have {} new {} from {sender}');
      expect(info.positional, 2);
      expect(info.named, {'name', 'sender'});
      expect(info.describePlaceholders(), '{}×2, {name}, {sender}');
    });

    test('reports none when there are no placeholders', () {
      expect(analyzeSimple('Plain').describePlaceholders(), 'none');
    });

    test('collects easy_localization links and trims sentence dots', () {
      final info = analyzeSimple('See @:help.text. Or @.upper:other_key');
      expect(info.links, {'help.text', 'other_key'});
    });

    test('custom pattern overrides the syntax', () {
      final info = analyzeSimple(
        'Hello {{ user }} and {{count}}',
        pattern: RegExp(r'\{\{\s*(\w*)\s*\}\}'),
        links: false,
      );
      expect(info.named, {'user', 'count'});
      expect(info.positional, 0);
    });
  });

  group('analyzeIcu', () {
    test('simple placeholders', () {
      final info = analyzeIcu('Hello {name}, welcome to {place}');
      expect(info.error, isNull);
      expect(info.named, {'name', 'place'});
      expect(info.choices, isEmpty);
    });

    test('plural with exact selectors and nested argument', () {
      final info = analyzeIcu('{count, plural, =0{No items} =1{One item} other{{count} items}}');
      expect(info.error, isNull);
      expect(info.named, {'count'});
      expect(info.choices.single.isPlural, isTrue);
      expect(info.choices.single.selectors, ['=0', '=1', 'other']);
      expect(info.plain, '{count} items');
    });

    test('select and nested plural inside a branch', () {
      final info = analyzeIcu(
        '{gender, select, male{He has {n, plural, one{# cat} other{# cats}}} other{They}}',
      );
      expect(info.error, isNull);
      expect(info.named, {'gender', 'n'});
      expect(info.choices.map((c) => c.type), containsAll(<String>['plural', 'select']));
    });

    test('offset and typed arguments', () {
      final info = analyzeIcu(
        '{count, plural, offset:1 one{x} other{y}} on {date, date, short} cost {p, number}',
      );
      expect(info.error, isNull);
      expect(info.named, {'count', 'date', 'p'});
      expect(info.choices.single.selectors, ['one', 'other']);
    });

    test('unclosed brace is an error', () {
      expect(analyzeIcu('{gender, select, male{He}').error, contains('unclosed'));
      expect(analyzeIcu('Hello {name').error, contains('unclosed'));
    });

    test('stray closing brace is an error', () {
      expect(analyzeIcu('Hello } there').error, contains('unexpected'));
    });

    test('invalid placeholder name is an error', () {
      expect(analyzeIcu('Hello {first name}').error, contains('invalid placeholder'));
    });

    test('branch without message is an error', () {
      expect(analyzeIcu('{n, plural, one other{x}}').error, isNotNull);
      expect(analyzeIcu('{n, plural}').error, contains('no branches'));
    });

    test('quotes are literal unless escaping is on', () {
      expect(analyzeIcu("It's {name}'s").named, {'name'});
      final escaped = analyzeIcu("Use '{' and '}' with {name}, it''s fine", useEscaping: true);
      expect(escaped.error, isNull);
      expect(escaped.named, {'name'});
      expect(escaped.plain, "Use { and } with {name}, it's fine");
    });
  });

  test('visibleText strips placeholders, links and #', () {
    expect(visibleText(analyzeSimple('Hi {name}, see @:a.b now')), 'Hi , see now');
    expect(visibleText(analyzeIcu('{n, plural, one{# item} other{# items}}')), 'items');
  });
}
