import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/utils/color.utils.dart';

void main() {
  test('stringToHexInt is deterministic and fully opaque', () {
    final a = ColorUtils.stringToHexInt('abc');
    expect(ColorUtils.stringToHexInt('abc'), a);
    expect(a >> 24, 0xFF);
  });

  test('different strings generally give different colors', () {
    expect(ColorUtils.stringToHexInt('abc'),
        isNot(ColorUtils.stringToHexInt('xyz')));
  });

  test('stringToColor wraps stringToHexInt', () {
    expect(ColorUtils.stringToColor('abc').toARGB32(),
        ColorUtils.stringToHexInt('abc'));
  });

  test('stringToHexColor has 0xFF prefix and 6 hex digits', () {
    expect(RegExp(r'^0xFF[0-9A-F]{6}$').hasMatch(ColorUtils.stringToHexColor('abc')),
        isTrue);
  });

  test('empty string maps to black', () {
    expect(ColorUtils.stringToHexInt(''), 0xFF000000);
  });
}
