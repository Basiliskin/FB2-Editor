import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/name_check.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';

StorySection _sec(List<String> paras, [String id = 's']) => StorySection(id, 'T', paras);

/// `n` paragraphs that mention [name] in the middle of a sentence.
List<String> _mentions(String name, int n, {String tail = 'пришёл домой'}) =>
    [for (var i = 0; i < n; i++) '<p>Потом $name $tail $i.</p>'];

NameFinding? _with(List<NameFinding> all, String a, String b) {
  for (final f in all) {
    final s = [for (final v in f.variants) v.surface];
    if (s.contains(a) && s.contains(b)) return f;
  }
  return null;
}

void main() {
  group('transliterate', () {
    test('brings Russian and English spellings of a name together', () {
      expect(transliterate('Иван'), transliterate('Ivan'));
      expect(transliterate('Катя'), transliterate('Katja'));
      expect(transliterate('Юрий'), transliterate('Yuri'));
      expect(transliterate('Сергей'), transliterate('Sergei'));
      expect(transliterate('Фёдор'), transliterate('Федор'));
    });

    test('keeps different names apart', () {
      expect(transliterate('Анна'), isNot(transliterate('Инна')));
    });
  });

  group('checkNames', () {
    test('Ivan and Иван are one name in two scripts', () {
      final found = checkNames([
        _sec([..._mentions('Иван', 4), ..._mentions('Ivan', 2)])
      ]);
      final f = _with(found, 'Иван', 'Ivan')!;
      expect(f.kind, NameFindingKind.script);
      expect(f.certain, isTrue);
      expect(f.variants.first.surface, 'Иван'); // the more used one first
      expect(f.variants.first.count, 4);
    });

    test('ё and е are one spelling', () {
      final found = checkNames([
        _sec([..._mentions('Фёдор', 3), ..._mentions('Федор', 2)])
      ]);
      expect(_with(found, 'Фёдор', 'Федор')!.kind, NameFindingKind.spelling);
    });

    test('a case ending is not a different spelling', () {
      final found = checkNames([
        _sec([..._mentions('Артур', 3), '<p>Он видел Артура и дал Артуру хлеб.</p>', '<p>Потом Артуром звали пса.</p>'])
      ]);
      expect(found, isEmpty);
    });

    test('a rare near-spelling of a common name is possible, not certain', () {
      final found = checkNames([
        _sec([..._mentions('Артур', 12), ..._mentions('Артор', 1)])
      ]);
      final f = _with(found, 'Артур', 'Артор')!;
      expect(f.kind, NameFindingKind.similar);
      expect(f.certain, isFalse);
    });

    test('two well-used names that are close are left alone', () {
      final found = checkNames([
        _sec([..._mentions('Ирина', 9), ..._mentions('Арина', 8)])
      ]);
      expect(_with(found, 'Ирина', 'Арина'), isNull);
    });

    test('every quote is really in the text it points to', () {
      final sections = [
        _sec([..._mentions('Иван', 4), ..._mentions('Ivan', 2)]),
        _sec([..._mentions('Иван', 1)], 't'),
      ];
      final f = _with(checkNames(sections), 'Иван', 'Ivan')!;
      for (final v in f.variants) {
        for (final w in v.where) {
          expect(quoteInText(w.quote, sections, w), isTrue, reason: w.quote);
          expect(w.quote, contains(v.surface));
        }
      }
    });

    test('a made-up quote does not verify', () {
      final sections = [_sec(_mentions('Иван', 3))];
      expect(quoteInText('Потом Ivan пришёл', sections, const NameLocation(0, 0, 'Потом Ivan пришёл')), isFalse);
      expect(quoteInText('x', sections, const NameLocation(5, 0, 'x')), isFalse);
    });

    test('a big book with thousands of different names stays quick', () {
      const letters = 'абвгдежзиклмнопрстуф';
      String name(int i) => '${letters[i % 20].toUpperCase()}${letters[(i ~/ 20) % 20]}${letters[(i ~/ 400) % 20]}'
          '${letters[(i * 7) % 20]}${letters[(i * 13 + 3) % 20]}${letters[(i ~/ 3) % 20]}';
      final paras = [for (var i = 0; i < 3000; i++) '<p>Потом ${name(i)} увидел ${name(i)} и ${name(i)}.</p>'];
      final sw = Stopwatch()..start();
      checkNames([_sec(paras)]);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a book with consistent names has no findings', () {
      expect(checkNames([_sec(_mentions('Артур', 5))]), isEmpty);
    });
  });
}
