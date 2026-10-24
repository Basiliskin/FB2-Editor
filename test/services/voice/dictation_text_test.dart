import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/dictation_text.dart';

void main() {
  soundLabelTests();
  group('insertDictation', () {
    test('goes in at the cursor with spaces on both sides', () {
      expect(insertDictation('Купить хлеб', 'молоко и', 7, 7),
          (text: 'Купить молоко и хлеб', cursor: 15));
    });

    test('adds a space where it touches a word', () {
      expect(insertDictation('ab', 'x', 1, 1), (text: 'a x b', cursor: 3));
    });

    test('adds no space before punctuation', () {
      expect(insertDictation('Hello.', 'world', 5, 5),
          (text: 'Hello world.', cursor: 11));
    });

    test('adds no space before closing quotes, brackets or an ellipsis', () {
      for (final mark in [
        '»',
        '”',
        ')',
        ']',
        '}',
        '…',
        ',',
        '!',
        '?',
        ';',
        ':'
      ]) {
        expect(insertDictation('a${mark}b', 'x', 1, 1)?.text, 'a x${mark}b',
            reason: mark);
      }
    });

    test('adds no space next to existing whitespace', () {
      expect(insertDictation('a b', 'x', 2, 2), (text: 'a x b', cursor: 3));
      expect(insertDictation('a\nb', 'x', 2, 2), (text: 'a\nx b', cursor: 3));
      expect(insertDictation('a ', 'x', 2, 2), (text: 'a x', cursor: 3));
    });

    test('replaces the selected text', () {
      expect(insertDictation('buy milk now', 'bread', 4, 8),
          (text: 'buy bread now', cursor: 9));
    });

    test('replaces the whole text when everything is selected', () {
      expect(insertDictation('old', 'new', 0, 3), (text: 'new', cursor: 3));
    });

    test('works at the start and the end', () {
      expect(insertDictation('b', 'a', 0, 0), (text: 'a b', cursor: 1));
      expect(insertDictation('a', 'b', 1, 1), (text: 'a b', cursor: 3));
      expect(insertDictation('', 'a', 0, 0), (text: 'a', cursor: 1));
    });

    test('trims the dictation', () {
      expect(insertDictation('a', '\n b \n', 1, 1), (text: 'a b', cursor: 3));
    });

    test('returns null when nothing was dictated', () {
      expect(insertDictation('a', '  ', 1, 1), isNull);
      expect(insertDictation('a', '\n\t ', 1, 1), isNull);
      expect(insertDictation('a', '', 0, 1), isNull);
    });

    test('keeps Hebrew text intact', () {
      expect(insertDictation('לקנות לחם', 'חלב ו', 6, 6),
          (text: 'לקנות חלב ו לחם', cursor: 11));
    });
  });
}

void soundLabelTests() {
  group('stripSoundLabels', () {
    test('drops labels for sounds', () {
      expect(stripSoundLabels('[Bell rings]'), '');
      expect(stripSoundLabels('(applause)'), '');
      expect(stripSoundLabels('*music*'), '');
      expect(stripSoundLabels('♪ ♪'), '');
      expect(stripSoundLabels('[Music] [BLANK_AUDIO]'), '');
    });

    test('keeps the words around a label and tidies the gap', () {
      expect(stripSoundLabels('Hello [laughs] world'), 'Hello world');
      expect(stripSoundLabels('Hello (coughs) .'), 'Hello.');
      expect(stripSoundLabels('  plain words '), 'plain words');
    });

    test('keeps a long parenthesised remark, which is speech', () {
      const long =
          '(this is a remark that goes on for well over forty characters)';
      expect(stripSoundLabels(long), long);
    });

    test('works on Russian and Hebrew text', () {
      expect(stripSoundLabels('[Музыка] Привет'), 'Привет');
      expect(stripSoundLabels('שלום (מוזיקה)'), 'שלום');
    });
  });
}
