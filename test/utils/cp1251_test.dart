import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/utils/cp1251.dart';

void main() {
  test('table covers all 256 byte values', () {
    expect(cp1251.length, 256);
  });

  test('ASCII bytes map to themselves', () {
    expect(decodeCp1251('Hello, 123!'.codeUnits), 'Hello, 123!');
  });

  test('decodes Cyrillic bytes', () {
    // "Привет" in windows-1251
    expect(decodeCp1251([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]), 'Привет');
  });

  test('decodes lower and upper case ranges', () {
    expect(decodeCp1251([0xC0, 0xDF, 0xE0, 0xFF]), 'АЯая');
  });

  test('empty input yields empty string', () {
    expect(decodeCp1251(<int>[]), '');
  });
}
