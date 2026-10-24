import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/recording_controller.dart';
import 'package:quill_fb2/services/voice/recording_error.dart';
import 'package:quill_fb2/services/voice/recording_status.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition_failure.dart';

import '../../support/voice/fake_microphone_permission.dart';
import '../../support/voice/fake_speech_recognition.dart';

const _en = SpeechLanguage.english;
const _ru = SpeechLanguage.russian;

class _Harness {
  _Harness() {
    controller.addListener(() => warmUpStates.add(controller.warmUpState));
  }

  final engine = FakeSpeechRecognition();
  final permission = FakeMicrophonePermission();
  final warmUpStates = <WarmUpState>[];
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

  Completer<void> holdInitialize() => engine.initializeGate = Completer<void>();
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
  await Future<void>.delayed(Duration.zero);
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  group('one shared load per language', () {
    test('repeat warm-ups share one initialize and one Future', () async {
      final gate = h.holdInitialize();

      final first = h.controller.warmUp(_en);
      final second = h.controller.warmUp(_en);
      await settle();

      expect(identical(first, second), isTrue);
      expect(h.engine.initializedLanguages, [_en]);

      gate.complete();
      await first;

      expect(h.controller.warmUpState, WarmUpState.ready);
      expect(h.engine.initializedLanguages, [_en]);
    });

    test('a record started during warm-up waits for it and loads nothing '
        'more', () async {
      await h.controller.setLanguage(_en);
      h.engine.finalText = 'hello';
      final gate = h.holdInitialize();
      final warmUp = h.controller.warmUp(_en);
      await settle();

      final recording = h.record();
      await settle();
      expect(h.controller.status, RecordingStatus.loadingModel);
      expect(h.engine.startCalls, 0);

      gate.complete();
      await warmUp;
      await recording;
      expect(h.controller.status, RecordingStatus.recording);
      await h.stop();

      expect(h.engine.initializedLanguages, [_en]);
      expect(h.engine.startedLanguages, [_en]);
      expect(h.controller.captureText, 'hello');
    });

    test('a record after a finished warm-up loads nothing more', () async {
      await h.controller.setLanguage(_en);
      await h.controller.warmUp(_en);

      await h.record();

      expect(h.controller.status, RecordingStatus.recording);
      expect(h.engine.initializedLanguages, [_en]);
    });

    test(
      'a warm-up after a recording loaded the model loads nothing more',
      () async {
        await h.controller.setLanguage(_en);
        await h.record();

        await h.controller.warmUp(_en);

        expect(h.engine.initializedLanguages, [_en]);
        expect(h.controller.warmUpState, WarmUpState.ready);
      },
    );
  });

  group('loads for different languages never overlap', () {
    test('a record in another language waits for the warm-up, then loads its '
        'own language once', () async {
      h.engine.finalText = 'privet';
      final gate = h.holdInitialize();
      final warmUp = h.controller.warmUp(_en);
      await settle();

      final recording = h.record();
      await settle();
      expect(h.engine.initializedLanguages, [_en]);

      gate.complete();
      await warmUp;
      await recording;
      await h.stop();

      expect(h.engine.initializedLanguages, [_en, _ru]);
      expect(h.engine.maxConcurrentInitializations, 1);
      expect(h.engine.startedLanguages, [_ru]);
      expect(h.controller.captureText, 'privet');
    });

    test(
      'a warm-up in another language gets its own load after the first',
      () async {
        final gate = h.holdInitialize();
        final english = h.controller.warmUp(_en);
        final russian = h.controller.warmUp(_ru);
        await settle();

        expect(identical(english, russian), isFalse);
        expect(h.engine.initializedLanguages, [_en]);

        gate.complete();
        await russian;

        expect(h.engine.initializedLanguages, [_en, _ru]);
        expect(h.engine.maxConcurrentInitializations, 1);
        expect(h.controller.warmUpState, WarmUpState.ready);

        await h.record();
        expect(h.engine.initializedLanguages, [_en, _ru]);
        expect(h.engine.startedLanguages, [_ru]);
      },
    );

    test(
      'a warm-up in another language is ignored while a session runs',
      () async {
        await h.record();

        await h.controller.warmUp(_en);

        expect(h.engine.initializedLanguages, [_ru]);
        expect(h.controller.status, RecordingStatus.recording);
        expect(h.controller.warmUpState, WarmUpState.ready);
      },
    );
  });

  group('warm-up state', () {
    test(
      'goes idle -> warmingUp -> ready with one notification per change',
      () async {
        expect(h.controller.warmUpState, WarmUpState.idle);

        await h.controller.warmUp(_en);
        await h.controller.warmUp(_en);

        expect(h.warmUpStates, [WarmUpState.warmingUp, WarmUpState.ready]);
      },
    );

    test('a missing model returns to idle silently and record() still '
        'reports it', () async {
      h.engine.initializeError = const ModelNotInstalled(_ru);

      await h.controller.warmUp(_ru);

      expect(h.warmUpStates, [WarmUpState.warmingUp, WarmUpState.idle]);
      expect(h.controller.error, isNull);
      expect(h.controller.status, RecordingStatus.idle);

      await h.record();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.modelMissing);
    });

    test(
      'an engine error returns to idle and the next record loads again',
      () async {
        h.engine.initializeError = const EngineFailure('load failed');

        await h.controller.warmUp(_ru);
        expect(h.controller.warmUpState, WarmUpState.idle);
        expect(h.controller.error, isNull);

        h.engine.initializeError = null;
        h.engine.finalText = 'works';
        await h.record();
        await h.stop();

        expect(h.engine.initializedLanguages, [_ru, _ru]);
        expect(h.controller.captureText, 'works');
        expect(h.controller.warmUpState, WarmUpState.ready);
      },
    );

    test(
      'a fire-and-forget warm-up that fails raises no uncaught error',
      () async {
        h.engine.initializeError = const ModelNotInstalled(_en);
        final errors = <Object>[];

        await runZonedGuarded(() async {
          unawaited(h.controller.warmUp(_en));
          await settle();
        }, (error, _) => errors.add(error));

        expect(errors, isEmpty);
        expect(h.controller.warmUpState, WarmUpState.idle);
      },
    );
  });
}
