import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/recognition_result.dart';

void main() {
  group('RecognitionResult', () {
    test('equal values are equal and share a hashCode', () {
      const a = RecognitionResult(text: 'a', isFinal: true);
      const b = RecognitionResult(text: 'a', isFinal: true);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different text is not equal', () {
      expect(
        const RecognitionResult(text: 'a', isFinal: true),
        isNot(const RecognitionResult(text: 'b', isFinal: true)),
      );
    });

    test('different isFinal is not equal', () {
      expect(
        const RecognitionResult(text: 'a', isFinal: true),
        isNot(const RecognitionResult(text: 'a', isFinal: false)),
      );
    });

    test('a Set de-duplicates equal results', () {
      final results = {
        RecognitionResult(text: 'a', isFinal: true),
        RecognitionResult(text: 'a', isFinal: true),
        RecognitionResult(text: 'a', isFinal: false),
      };

      expect(results, hasLength(2));
    });
  });
}
