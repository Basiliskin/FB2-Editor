import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition_failure.dart';

String _describe(SpeechRecognitionFailure failure) => switch (failure) {
      ModelNotInstalled(:final language) => 'model:${language.code}',
      EngineFailure(:final reason) => 'engine:$reason',
      AudioTooLong(:final limit) => 'too-long:${limit.inSeconds}',
    };

void main() {
  group('SpeechRecognitionFailure', () {
    test('an exhaustive switch covers every failure without a default', () {
      expect(
        _describe(const ModelNotInstalled(SpeechLanguage.hebrew)),
        'model:he',
      );
      expect(
        _describe(const EngineFailure('decoder crashed')),
        'engine:decoder crashed',
      );
      expect(
        _describe(const AudioTooLong(Duration(minutes: 2))),
        'too-long:120',
      );
    });

    test('is an Exception', () {
      expect(const EngineFailure('x'), isA<Exception>());
    });

    test('ModelNotInstalled names the missing language', () {
      final text = const ModelNotInstalled(SpeechLanguage.hebrew).toString();

      expect(text, contains('he'));
      expect(text, isNot(contains('Instance of')));
    });

    test('EngineFailure names its reason', () {
      expect(
        const EngineFailure('decoder crashed').toString(),
        contains('decoder crashed'),
      );
    });

    test('AudioTooLong names its limit', () {
      expect(
        const AudioTooLong(Duration(minutes: 2)).toString(),
        contains('120 s'),
      );
    });
  });
}
