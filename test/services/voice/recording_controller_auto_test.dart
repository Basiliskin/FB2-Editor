import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/recording_controller.dart';
import 'package:quill_fb2/services/voice/recording_error.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';

import '../../support/voice/fake_microphone_permission.dart';
import '../../support/voice/fake_speech_recognition.dart';

const _auto = SpeechLanguageChoice.auto;

class _Harness {
  final engine = FakeSpeechRecognition();
  final permission = FakeMicrophonePermission();
  DateTime now = DateTime(2026, 10, 22);

  late final controller = RecordingController(
    engine: engine,
    permission: permission,
    clock: () => now,
  );

  Future<void> record() {
    now = now.add(const Duration(seconds: 1));
    return controller.record();
  }

  Future<void> stop() {
    now = now.add(const Duration(seconds: 1));
    return controller.stop();
  }
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  group('Auto Speech Language', () {
    test('initialises the engine with the Auto choice', () async {
      await h.controller.setChoice(_auto);

      await h.record();

      expect(h.engine.initializedChoices, [_auto]);
      expect(h.controller.choice, _auto);
    });

    test('exposes the detected language of the finished Recording', () async {
      await h.controller.setChoice(_auto);
      h.controller.setFallbackLanguage(SpeechLanguage.english);
      h.engine
        ..finalText = 'shalom'
        ..finalLang = 'he';

      await h.record();
      expect(h.controller.detectedLanguage, isNull);
      await h.stop();

      expect(h.controller.detectedLanguage, SpeechLanguage.hebrew);
    });

    test('relabels an out-of-set result to the fallback', () async {
      await h.controller.setChoice(_auto);
      h.controller.setFallbackLanguage(SpeechLanguage.english);
      h.engine
        ..finalText = 'bonjour'
        ..finalLang = 'fr';

      await h.record();
      await h.stop();

      expect(h.controller.detectedLanguage, SpeechLanguage.english);
    });

    test('uses the fallback when the engine reports no language', () async {
      await h.controller.setChoice(_auto);
      h.controller.setFallbackLanguage(SpeechLanguage.hebrew);
      h.engine.finalText = 'text';

      await h.record();
      await h.stop();

      expect(h.controller.detectedLanguage, SpeechLanguage.hebrew);
    });

    test('clears the detected language when a new Recording fails', () async {
      await h.controller.setChoice(_auto);
      h.engine
        ..finalText = 'privet'
        ..finalLang = 'ru';
      await h.record();
      await h.stop();
      expect(h.controller.detectedLanguage, SpeechLanguage.russian);

      h.engine.initializeError = StateError('boom');
      await h.controller.setChoice(
        const SpeechLanguageChoice.of(SpeechLanguage.english),
      );
      await h.record();

      expect(h.controller.error, RecordingError.engineFailed);
      expect(h.controller.detectedLanguage, isNull);
    });

    test('language getter is the fallback under Auto', () async {
      h.controller.setFallbackLanguage(SpeechLanguage.hebrew);
      await h.controller.setChoice(_auto);

      expect(h.controller.language, SpeechLanguage.hebrew);
    });
  });

  group('model cache keyed on the choice', () {
    test('Auto warm-up then Recording initialises once', () async {
      await h.controller.warmUpChoice(_auto);
      await h.controller.setChoice(_auto);

      await h.record();

      expect(h.engine.initializedChoices, [_auto]);
      expect(h.engine.startCalls, 1);
    });

    test('switching from Auto to a language initialises again', () async {
      await h.controller.warmUpChoice(_auto);
      await h.controller.warmUpChoice(
        const SpeechLanguageChoice.of(SpeechLanguage.russian),
      );

      expect(h.engine.initializedChoices, [
        _auto,
        const SpeechLanguageChoice.of(SpeechLanguage.russian),
      ]);
    });

    test('Auto is not shared with the fallback language', () async {
      h.controller.setFallbackLanguage(SpeechLanguage.english);
      await h.controller.warmUp(SpeechLanguage.english);
      await h.controller.warmUpChoice(_auto);

      expect(h.engine.initializedChoices.length, 2);
    });
  });
}
