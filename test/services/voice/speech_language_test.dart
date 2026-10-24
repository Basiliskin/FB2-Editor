import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';

void main() {
  _choiceAndDetectedLanguageTests();

  group('SpeechLanguage.fromCode', () {
    test('round-trips every language code', () {
      for (final language in SpeechLanguage.values) {
        expect(SpeechLanguage.fromCode(language.code), language);
      }
    });

    test('uses ISO 639-1 codes', () {
      expect(SpeechLanguage.russian.code, 'ru');
      expect(SpeechLanguage.hebrew.code, 'he');
      expect(SpeechLanguage.english.code, 'en');
    });

    test('rejects unsupported and empty codes', () {
      expect(() => SpeechLanguage.fromCode('fr'), throwsArgumentError);
      expect(() => SpeechLanguage.fromCode(''), throwsArgumentError);
    });

    test('rejects case variants', () {
      expect(() => SpeechLanguage.fromCode('EN'), throwsArgumentError);
      expect(() => SpeechLanguage.fromCode('Ru'), throwsArgumentError);
    });

    test("rejects Android's legacy Hebrew code 'iw'", () {
      expect(() => SpeechLanguage.fromCode('iw'), throwsArgumentError);
    });

    test('rejects enum names', () {
      expect(() => SpeechLanguage.fromCode('english'), throwsArgumentError);
    });
  });
}

void _choiceAndDetectedLanguageTests() {
  group('SpeechLanguageChoice', () {
    test('auto has code auto and no language', () {
      expect(SpeechLanguageChoice.auto.code, 'auto');
      expect(SpeechLanguageChoice.auto.language, isNull);
      expect(SpeechLanguageChoice.auto.isAuto, isTrue);
    });

    test('round-trips auto and every language code', () {
      expect(SpeechLanguageChoice.fromCode('auto'), SpeechLanguageChoice.auto);
      for (final language in SpeechLanguage.values) {
        expect(
          SpeechLanguageChoice.fromCode(language.code),
          SpeechLanguageChoice.of(language),
        );
      }
      expect(() => SpeechLanguageChoice.fromCode('fr'), throwsArgumentError);
    });

    test('has value equality', () {
      expect(
        SpeechLanguageChoice.of(SpeechLanguage.hebrew),
        SpeechLanguageChoice.of(SpeechLanguage.hebrew),
      );
      expect(
        SpeechLanguageChoice.of(SpeechLanguage.hebrew).hashCode,
        SpeechLanguageChoice.of(SpeechLanguage.hebrew).hashCode,
      );
      expect(
        SpeechLanguageChoice.auto,
        isNot(SpeechLanguageChoice.of(SpeechLanguage.english)),
      );
    });
  });

  group('resolveDetectedLanguage', () {
    const fallback = SpeechLanguage.english;

    test('maps ru, he and en to their language', () {
      expect(resolveDetectedLanguage('ru', fallback), SpeechLanguage.russian);
      expect(
        resolveDetectedLanguage('he', SpeechLanguage.russian),
        SpeechLanguage.hebrew,
      );
      expect(
        resolveDetectedLanguage('en', SpeechLanguage.russian),
        SpeechLanguage.english,
      );
    });

    test('tolerates case and surrounding whitespace', () {
      expect(resolveDetectedLanguage(' RU ', fallback), SpeechLanguage.russian);
    });

    test('uses the fallback for empty, null and out-of-set results', () {
      for (final lang in [null, '', 'fr', '<|ru|>']) {
        expect(
          resolveDetectedLanguage(lang, SpeechLanguage.hebrew),
          SpeechLanguage.hebrew,
          reason: '$lang',
        );
      }
    });
  });
}
