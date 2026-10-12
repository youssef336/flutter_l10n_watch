import 'package:flutter_l10n_watch/src/dart_source.dart';
import 'package:test/test.dart';

void main() {
  test('masks comments and keeps line breaks', () {
    const code = "a(); // 'not a string'\n/* b('x') /* nested */ */ c('y');";
    final source = DartSource('f.dart', code);
    expect(source.masked.length, code.length);
    expect(source.masked, isNot(contains('not a string')));
    expect(source.masked, isNot(contains('nested')));
    expect(source.literals.map((l) => l.value), ['y']);
    expect(source.lineOf(source.literals.single.start), 2);
  });

  test('decodes escapes, raw and triple-quoted strings', () {
    const code = r"""f('it\'s\n', r'raw\n$x', '''multi
line''', "dA\x42", 'a' 'b');""";
    final values = DartSource('f.dart', code).literals.map((l) => l.value).toList();
    expect(values, ["it's\n", r'raw\n$x', 'multi\nline', 'dAB', 'a', 'b']);
  });

  test('tracks interpolation prefix and keeps interpolated code visible', () {
    const code = r"""x('status_$value'.tr(), 'a ${b.c('inner')} d');""";
    final source = DartSource('f.dart', code);
    final outer = source.literals.firstWhere((l) => l.value.startsWith('status_'));
    expect(outer.interpolated, isTrue);
    expect(outer.prefix, 'status_');
    expect(outer.value, 'status_$interpolationMarker');
    expect(source.literals.map((l) => l.value), contains('inner'));
    expect(source.masked, contains('b.c('));
    expect(source.masked, isNot(contains('status_')));
  });

  test('finds the enclosing bracket and its arguments', () {
    const code = "Text('hi', style: s(1, 2), maxLines: 2)";
    final source = DartSource('f.dart', code);
    final literal = source.literals.single;
    expect(literal.enclosingOpen, 4);
    final args = source.argumentsOf(4);
    expect(args[r'$0'], "'hi'");
    expect(args['style'], 's(1, 2)');
    expect(args['maxLines'], '2');
    expect(source.closeOf(4), code.length - 1);
    expect(source.openOf(code.length - 1), 4);
  });

  test('lineText returns the source line', () {
    final source = DartSource('f.dart', "a\nb('x') // note\nc");
    expect(source.lineText(source.literals.single.start), "b('x') // note");
  });

  test('unterminated literal stops at the end of the line', () {
    final source = DartSource('f.dart', "a('oops\nb('ok');");
    expect(source.literals.map((l) => l.value), ['oops', 'ok']);
  });
}
