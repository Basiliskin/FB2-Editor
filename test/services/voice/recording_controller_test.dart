import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/recording_controller.dart';
import 'package:quill_fb2/services/voice/microphone_permission.dart';
import 'package:quill_fb2/services/voice/recording_error.dart';
import 'package:quill_fb2/services/voice/recording_status.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition_failure.dart';

import '../../support/voice/fake_microphone_permission.dart';
import '../../support/voice/fake_speech_recognition.dart';

class _Harness {
  _Harness() {
    controller.addListener(() => statuses.add(controller.status));
  }

  final engine = FakeSpeechRecognition();
  final permission = FakeMicrophonePermission();
  final statuses = <RecordingStatus>[];
  DateTime now = DateTime(2026, 10, 20);

  late final controller = RecordingController(
    engine: engine,
    permission: permission,
    clock: () => now,
  );

  void advance([Duration by = const Duration(seconds: 1)]) {
    now = now.add(by);
  }

  Future<void> record() {
    advance();
    return controller.record();
  }

  Future<void> stop() {
    advance();
    return controller.stop();
  }

  Future<void> session(String finalText) async {
    engine.finalText = finalText;
    await record();
    await stop();
  }

  List<RecordingStatus> get distinctStatuses => [
    for (final (i, s) in statuses.indexed)
      if (i == 0 || statuses[i - 1] != s) s,
  ];
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

const _earlierText = 'Earlier text';

typedef _ActiveState = ({
  RecordingStatus status,
  Future<void> Function(_Harness h) enter,
  void Function(_Harness h) release,
});

final _activeStates = <_ActiveState>[
  (
    status: RecordingStatus.requestingPermission,
    enter: (h) async {
      h.permission.gate = Completer<MicrophonePermissionResult>();
      unawaited(h.record());
      await settle();
    },
    release: (h) {
      final gate = h.permission.gate!;
      h.permission.gate = null;
      gate.complete(MicrophonePermissionResult.granted);
    },
  ),
  (
    status: RecordingStatus.loadingModel,
    enter: (h) async {
      h.engine.initializeGate = Completer<void>();
      unawaited(h.record());
      await settle();
    },
    release: (h) {
      final gate = h.engine.initializeGate!;
      h.engine.initializeGate = null;
      gate.complete();
    },
  ),
  (
    status: RecordingStatus.recording,
    enter: (h) async {
      await h.record();
      h.engine.emitPartial('spo');
      h.engine.emitLateFinal();
    },
    release: (_) {},
  ),
  (
    status: RecordingStatus.processing,
    enter: (h) async {
      await h.record();
      h.engine.stopGate = Completer<void>();
      unawaited(h.stop());
      await settle();
    },
    release: (h) {
      final gate = h.engine.stopGate!;
      h.engine.stopGate = null;
      gate.complete();
    },
  ),
];

void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  group('allowed transitions', () {
    test('record goes idle -> requestingPermission -> loadingModel -> '
        'recording', () async {
      expect(h.controller.status, RecordingStatus.idle);

      await h.record();

      expect(h.distinctStatuses, [
        RecordingStatus.requestingPermission,
        RecordingStatus.loadingModel,
        RecordingStatus.recording,
      ]);
      expect(h.engine.initializedLanguages, [SpeechLanguage.russian]);
      expect(h.engine.startCalls, 1);
    });

    test('stop goes recording -> processing -> idle', () async {
      await h.record();
      h.statuses.clear();

      await h.stop();

      expect(h.distinctStatuses, [
        RecordingStatus.processing,
        RecordingStatus.idle,
      ]);
      expect(h.engine.stopCalls, 1);
    });

    test('denied permission goes to error, then the next record returns '
        'to idle and proceeds', () async {
      h.permission.result = MicrophonePermissionResult.denied;
      await h.record();
      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.permissionDenied);
      expect(h.engine.initializedLanguages, isEmpty);

      h.permission.result = MicrophonePermissionResult.granted;
      h.statuses.clear();
      await h.record();

      expect(h.distinctStatuses, [
        RecordingStatus.idle,
        RecordingStatus.requestingPermission,
        RecordingStatus.loadingModel,
        RecordingStatus.recording,
      ]);
    });

    test('permanently denied permission goes to error', () async {
      h.permission.result = MicrophonePermissionResult.permanentlyDenied;
      await h.record();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.permissionBlocked);
    });

    test('ModelNotInstalled on initialize goes to error, then idle on the '
        'next record', () async {
      h.engine.initializeError = const ModelNotInstalled(
        SpeechLanguage.russian,
      );
      await h.record();
      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.modelMissing);
      expect(h.engine.startCalls, 0);

      h.engine.initializeError = null;
      await h.record();
      expect(h.controller.status, RecordingStatus.recording);
      expect(h.controller.error, isNull);
    });

    test('EngineFailure on initialize goes to error, then idle on the next '
        'record', () async {
      h.engine.initializeError = const EngineFailure('load');
      await h.record();
      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.engineFailed);

      h.engine.initializeError = null;
      await h.record();
      expect(h.controller.status, RecordingStatus.recording);
    });

    test('EngineFailure on stop goes to error', () async {
      await h.record();
      h.engine.stopError = const EngineFailure('decode');
      await h.stop();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.engineFailed);
    });

    test('AudioTooLong on stop goes to error', () async {
      await h.record();
      h.engine.stopError = const AudioTooLong(Duration(seconds: 30));
      await h.stop();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.audioTooLong);
    });

    test('AudioTooLong during recording processes the buffered audio and '
        'appends the final', () async {
      h.engine.finalText = 'buffered';
      await h.record();
      h.statuses.clear();

      h.engine.emitError(const AudioTooLong(Duration(seconds: 30)));
      await settle();

      expect(h.distinctStatuses, [
        RecordingStatus.processing,
        RecordingStatus.idle,
      ]);
      expect(h.controller.transcriptText, 'buffered');
      expect(h.engine.stopCalls, 1);
    });

    test('a result of only a sound label counts as nothing heard', () async {
      await h.session('[Bell rings]');
      expect(h.controller.captureText, '');
      expect(h.controller.transcriptText, '');
    });

    test('a sound label inside speech is dropped from the capture', () async {
      await h.session('Hello [laughs] world');
      expect(h.controller.captureText, 'Hello world');
    });

    test('AudioTooLong during recording flags the limit and keeps the text, '
        'and the next session starts clear', () async {
      h.engine.finalText = 'buffered';
      await h.record();
      expect(h.controller.hitLengthLimit, isFalse);

      h.engine.emitError(const AudioTooLong(Duration(seconds: 30)));
      await settle();

      expect(h.controller.hitLengthLimit, isTrue);
      expect(h.controller.captureText, 'buffered');

      await h.session('more');
      expect(h.controller.hitLengthLimit, isFalse);
    });

    test('AudioTooLong during recording goes to error when the engine '
        'returns no final', () async {
      await h.record();
      h.engine.stopError = const EngineFailure('decode');

      h.engine.emitError(const AudioTooLong(Duration(seconds: 30)));
      await settle();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.audioTooLong);
    });

    test(
      'AudioTooLong during recording with an empty final ends as nothing heard',
      () async {
        await h.record();

        h.engine.emitError(const AudioTooLong(Duration(seconds: 30)));
        await settle();

        expect(h.controller.status, RecordingStatus.idle);
        expect(h.controller.error, isNull);
        expect(h.controller.hitLengthLimit, isTrue);
        expect(h.controller.captureText, '');
      },
    );

    test(
      'EngineFailure on the stream during recording goes to error',
      () async {
        await h.record();

        h.engine.emitError(const EngineFailure('stream'));
        await settle();

        expect(h.controller.status, RecordingStatus.error);
        expect(h.controller.error, RecordingError.engineFailed);
      },
    );

    test('the model is loaded once per language', () async {
      await h.session('a');
      await h.session('b');

      expect(h.engine.initializedLanguages, [SpeechLanguage.russian]);
      expect(h.engine.startCalls, 2);
    });
  });

  group('rejected commands leave status unchanged', () {
    test('record during loadingModel', () async {
      h.engine.initializeGate = Completer<void>();
      unawaited(h.record());
      await settle();
      expect(h.controller.status, RecordingStatus.loadingModel);

      await h.record();

      expect(h.controller.status, RecordingStatus.loadingModel);
      expect(h.permission.requestCalls, 1);
      expect(h.engine.initializedLanguages, hasLength(1));
      h.engine.initializeGate!.complete();
    });

    test('record during processing', () async {
      await h.record();
      h.engine.stopGate = Completer<void>();
      unawaited(h.stop());
      await settle();
      expect(h.controller.status, RecordingStatus.processing);

      await h.record();

      expect(h.controller.status, RecordingStatus.processing);
      expect(h.permission.requestCalls, 1);
      h.engine.stopGate!.complete();
    });

    test('record during recording', () async {
      await h.record();

      await h.record();

      expect(h.controller.status, RecordingStatus.recording);
      expect(h.engine.startCalls, 1);
    });

    test('stop in idle', () async {
      await h.stop();

      expect(h.controller.status, RecordingStatus.idle);
      expect(h.engine.stopCalls, 0);
    });

    test('stop in requestingPermission', () async {
      h.permission.gate = Completer<MicrophonePermissionResult>();
      unawaited(h.record());
      await settle();

      await h.stop();

      expect(h.controller.status, RecordingStatus.requestingPermission);
      expect(h.engine.stopCalls, 0);
    });

    test('stop in loadingModel', () async {
      h.engine.initializeGate = Completer<void>();
      unawaited(h.record());
      await settle();

      await h.stop();

      expect(h.controller.status, RecordingStatus.loadingModel);
      expect(h.engine.stopCalls, 0);
    });

    test('stop in error', () async {
      h.permission.result = MicrophonePermissionResult.denied;
      await h.record();

      await h.stop();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.engine.stopCalls, 0);
    });
  });

  group('onInterrupted', () {
    test(
      'while recording goes through processing and keeps the final',
      () async {
        h.engine.finalText = 'kept';
        await h.record();
        h.statuses.clear();

        await h.controller.onInterrupted();

        expect(h.distinctStatuses, [
          RecordingStatus.processing,
          RecordingStatus.idle,
        ]);
        expect(h.engine.stopCalls, 1);
        expect(h.controller.transcriptText, 'kept');
      },
    );

    test('while requestingPermission cancels to idle and ignores the late '
        'permission result', () async {
      h.permission.gate = Completer<MicrophonePermissionResult>();
      unawaited(h.record());
      await settle();

      await h.controller.onInterrupted();
      expect(h.controller.status, RecordingStatus.idle);

      h.permission.gate!.complete(MicrophonePermissionResult.granted);
      await settle();

      expect(h.controller.status, RecordingStatus.idle);
      expect(h.engine.initializedLanguages, isEmpty);
      expect(h.engine.stopCalls, 0);
    });

    test(
      'while loadingModel cancels to idle without stopping the engine',
      () async {
        h.engine.initializeGate = Completer<void>();
        unawaited(h.record());
        await settle();

        await h.controller.onInterrupted();
        expect(h.controller.status, RecordingStatus.idle);

        h.engine.initializeGate!.complete();
        await settle();

        expect(h.controller.status, RecordingStatus.idle);
        expect(h.engine.startCalls, 0);
        expect(h.engine.stopCalls, 0);
      },
    );

    test('while idle does nothing', () async {
      await h.controller.onInterrupted();

      expect(h.controller.status, RecordingStatus.idle);
      expect(h.statuses, isEmpty);
      expect(h.engine.stopCalls, 0);
    });

    test('while in error does nothing', () async {
      h.permission.result = MicrophonePermissionResult.denied;
      await h.record();

      await h.controller.onInterrupted();

      expect(h.controller.status, RecordingStatus.error);
    });
  });

  group('final transcript', () {
    test('is appended once when the stream final arrives before stop '
        'returns', () async {
      h.engine.finalBeforeStop = true;
      await h.session('abc');

      expect('abc'.allMatches(h.controller.transcriptText).length, 1);
      expect(h.controller.transcriptText, 'abc');
    });

    test(
      'is appended once when stop returns before the stream final',
      () async {
        h.engine.finalBeforeStop = false;
        await h.session('abc');
        h.engine.emitLateFinal();
        await settle();

        expect('abc'.allMatches(h.controller.transcriptText).length, 1);
        expect(h.controller.transcriptText, 'abc');
      },
    );

    test('follows user text with exactly one separator', () async {
      h.controller.transcriptText = 'mine';
      await h.session('abc');

      expect(h.controller.transcriptText, 'mine abc');
    });

    test('has no leading separator when the editor is empty', () async {
      await h.session('abc');

      expect(h.controller.transcriptText, 'abc');
    });

    test('adds no separator after whitespace-only text', () async {
      h.controller.transcriptText = '  ';
      await h.session('abc');

      expect(h.controller.transcriptText, '  abc');
    });

    test('that is empty leaves the editor unchanged', () async {
      h.controller.transcriptText = 'mine';
      await h.session('');

      expect(h.controller.transcriptText, 'mine');
      expect(h.controller.status, RecordingStatus.idle);
    });

    test('partials update only the preview, which resets when the session '
        'ends', () async {
      h.controller.transcriptText = 'mine';
      await h.record();

      h.engine
        ..emitPartial('he')
        ..emitPartial('hello');
      expect(h.controller.partialPreview, 'hello');
      expect(h.controller.transcriptText, 'mine');

      h.engine.finalText = 'hello world';
      await h.stop();

      expect(h.controller.partialPreview, isNull);
      expect(h.controller.transcriptText, 'mine hello world');
    });

    test('is appended again in a second session with the same text', () async {
      await h.session('ok');
      await h.session('ok');

      expect(h.controller.transcriptText, 'ok ok');
    });
  });

  group('capture text', () {
    test('holds only the latest session final while the transcript keeps '
        'both', () async {
      await h.session('first');
      await h.session('second');

      expect(h.controller.captureText, 'second');
      expect(h.controller.transcriptText, 'first second');
    });

    test('excludes the editor text and has no leading separator', () async {
      h.controller.transcriptText = 'mine';
      await h.session('  abc  ');

      expect(h.controller.captureText, 'abc');
    });

    test('stays empty while only partials arrive', () async {
      await h.record();
      h.engine.emitPartial('he');

      expect(h.controller.partialPreview, 'he');
      expect(h.controller.captureText, '');

      h.engine.finalText = 'hello';
      await h.stop();

      expect(h.controller.captureText, 'hello');
    });

    test('includes a final that arrives after stop returns', () async {
      h.engine.finalBeforeStop = false;
      await h.session('abc');
      h.engine.emitLateFinal();
      await settle();

      expect(h.controller.status, RecordingStatus.idle);
      expect(h.controller.captureText, 'abc');
      expect(h.controller.transcriptText, 'abc');
    });

    test('resets when the next session starts, even one that fails', () async {
      await h.session('ok');
      h.permission.result = MicrophonePermissionResult.denied;
      await h.record();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.captureText, '');
      expect(h.controller.transcriptText, 'ok');
    });

    test('is empty after an empty final', () async {
      await h.session('ok');
      await h.session('');

      expect(h.controller.captureText, '');
      expect(h.controller.transcriptText, 'ok');
    });
  });

  group('failures', () {
    final failures =
        <String, (RecordingError, Future<void> Function(_Harness))>{
          'denied permission': (
            RecordingError.permissionDenied,
            (h) async {
              h.permission.result = MicrophonePermissionResult.denied;
              await h.record();
            },
          ),
          'permanently denied permission': (
            RecordingError.permissionBlocked,
            (h) async {
              h.permission.result =
                  MicrophonePermissionResult.permanentlyDenied;
              await h.record();
            },
          ),
          'ModelNotInstalled': (
            RecordingError.modelMissing,
            (h) async {
              await h.controller.setLanguage(SpeechLanguage.english);
              h.engine.initializeError = const ModelNotInstalled(
                SpeechLanguage.english,
              );
              await h.record();
            },
          ),
          'EngineFailure on initialize': (
            RecordingError.engineFailed,
            (h) async {
              await h.controller.setLanguage(SpeechLanguage.english);
              h.engine.initializeError = const EngineFailure('x');
              await h.record();
            },
          ),
          'EngineFailure on stop': (
            RecordingError.engineFailed,
            (h) async {
              await h.record();
              h.engine.stopError = const EngineFailure('x');
              await h.stop();
            },
          ),
          'AudioTooLong on stop': (
            RecordingError.audioTooLong,
            (h) async {
              await h.record();
              h.engine.stopError = const AudioTooLong(Duration(seconds: 30));
              await h.stop();
            },
          ),
        };

    for (final MapEntry(key: name, value: (message, fail))
        in failures.entries) {
      test('$name keeps the user text and sets a fixed message', () async {
        h.controller.transcriptText = 'user text';
        await h.record();
        h.engine.emitPartial('partial');
        await h.stop();
        final before = h.controller.transcriptText;

        await fail(h);

        expect(h.controller.status, RecordingStatus.error);
        expect(h.controller.transcriptText, before);
        expect(h.controller.error, message);
      });
    }

    test('the error message never contains engine text', () async {
      await h.record();
      h.engine.stopError = const EngineFailure('SECRET-TRANSCRIPT');
      await h.stop();

      expect(h.controller.error, RecordingError.engineFailed);
    });

    test('the error message is cleared when the next session starts', () async {
      h.permission.result = MicrophonePermissionResult.denied;
      await h.record();
      expect(h.controller.error, isNotNull);

      h.permission.gate = Completer<MicrophonePermissionResult>();
      unawaited(h.record());
      await settle();

      expect(h.controller.status, RecordingStatus.requestingPermission);
      expect(h.controller.error, isNull);
    });
  });

  group('debounce', () {
    test('a second record inside the window is ignored', () async {
      await h.controller.record();
      await h.controller.stop();
      h.advance(const Duration(milliseconds: 100));

      await h.controller.record();

      expect(h.permission.requestCalls, 1);
      expect(h.engine.startCalls, 1);
    });

    test(
      'a record 299 ms later is ignored and one 300 ms later is honoured',
      () async {
        final start = h.now;
        await h.controller.record();
        h.advance(const Duration(milliseconds: 10));
        await h.controller.stop();
        expect(h.controller.status, RecordingStatus.idle);

        h.now = start.add(const Duration(milliseconds: 299));
        await h.controller.record();
        expect(h.permission.requestCalls, 1);

        h.now = start.add(const Duration(milliseconds: 300));
        await h.controller.record();
        expect(h.permission.requestCalls, 2);
      },
    );

    test('stop right after record is not dropped', () async {
      await h.controller.record();
      h.advance(const Duration(milliseconds: 50));

      await h.controller.stop();

      expect(h.engine.stopCalls, 1);
      expect(h.controller.status, RecordingStatus.idle);
    });

    test('a second stop inside the window is ignored', () async {
      await h.controller.record();
      h.engine.stopGate = Completer<void>();
      unawaited(h.controller.stop());
      await settle();

      await h.controller.stop();

      expect(h.engine.stopCalls, 1);
      h.engine.stopGate!.complete();
    });
  });

  group('language', () {
    test('defaults to Russian', () {
      expect(h.controller.language, SpeechLanguage.russian);
    });

    test('changing it while recording stops first and loads the new model '
        'on the next record', () async {
      h.engine.finalText = 'privet';
      await h.record();

      await h.controller.setLanguage(SpeechLanguage.english);

      expect(h.engine.stopCalls, 1);
      expect(h.controller.status, RecordingStatus.idle);
      expect(h.controller.transcriptText, 'privet');
      expect(h.engine.initializedLanguages, [SpeechLanguage.russian]);

      await h.record();
      expect(h.engine.initializedLanguages, [
        SpeechLanguage.russian,
        SpeechLanguage.english,
      ]);
    });

    test('changing it in error returns to idle', () async {
      h.permission.result = MicrophonePermissionResult.denied;
      await h.record();

      await h.controller.setLanguage(SpeechLanguage.hebrew);

      expect(h.controller.status, RecordingStatus.idle);
      expect(h.controller.language, SpeechLanguage.hebrew);
      expect(h.controller.error, isNull);
    });
  });

  group('release', () {
    test(
      'dispose releases the engine and cancels the result subscription',
      () async {
        await h.record();
        h.controller.dispose();
        await settle();

        expect(h.engine.disposeCalls, 1);
        expect(h.engine.hasListener, isFalse);
        h.engine.emitPartial('late');
        expect(h.controller.partialPreview, isNull);
        expect(h.controller.status, RecordingStatus.recording);
      },
    );

    test('dispose twice does not throw or release the engine twice', () {
      h.controller.dispose();
      h.controller.dispose();

      expect(h.engine.disposeCalls, 1);
    });

    test(
      'a permission result arriving after dispose changes nothing',
      () async {
        h.permission.gate = Completer<MicrophonePermissionResult>();
        unawaited(h.record());
        await settle();

        h.controller.dispose();
        h.permission.gate!.complete(MicrophonePermissionResult.granted);
        await settle();

        expect(h.engine.initializedLanguages, isEmpty);
      },
    );

    test('onInterrupted releases the recording session', () async {
      await h.record();

      await h.controller.onInterrupted();

      expect(h.engine.stopCalls, 1);
      expect(h.engine.hasListener, isFalse);
    });
  });
  group('cancel', () {
    void expectSessionDiscarded() {
      expect(h.controller.status, RecordingStatus.idle);
      expect(h.controller.transcriptText, _earlierText);
      expect(h.controller.captureText, '');
      expect(h.controller.partialPreview, isNull);
      expect(h.controller.error, isNull);
    }

    Future<void> enter(_ActiveState state) async {
      h.engine.finalText = 'spoken words';
      h.controller.transcriptText = _earlierText;
      await state.enter(h);
      expect(h.controller.status, state.status);
    }

    for (final state in _activeStates) {
      final name = state.status.name;

      test('from $name returns to idle with the text from before the '
          'session', () async {
        await enter(state);
        final atIdle = <(String, String)>[];
        h.controller.addListener(() {
          if (h.controller.status == RecordingStatus.idle && atIdle.isEmpty) {
            atIdle.add((h.controller.captureText, h.controller.transcriptText));
          }
        });

        await h.controller.cancel();

        expectSessionDiscarded();
        expect(atIdle, [('', _earlierText)]);
      });

      test('from $name ignores whatever the session delivers later', () async {
        await enter(state);
        final startCalls = h.engine.startCalls;

        await h.controller.cancel();
        state.release(h);
        await settle();

        expectSessionDiscarded();
        expect(h.engine.startCalls, startCalls);
        expect(h.engine.hasListener, isFalse);
      });

      test('from $name lets the next record start a new session', () async {
        await enter(state);
        final startCalls = h.engine.startCalls;

        await h.controller.cancel();
        state.release(h);
        await settle();
        await h.record();

        expect(h.controller.status, RecordingStatus.recording);
        expect(h.engine.startCalls, startCalls + 1);
        expect(h.controller.captureText, '');
        expect(h.controller.transcriptText, _earlierText);
      });
    }

    test('from recording cancels the engine without decoding', () async {
      await enter(_activeStates[2]);
      expect(h.controller.transcriptText, '$_earlierText spoken words');

      await h.controller.cancel();

      expectSessionDiscarded();
      expect(h.engine.cancelCalls, 1);
      expect(h.engine.stopCalls, 0);
    });

    test('from requestingPermission, loadingModel or processing does not '
        'cancel the engine', () async {
      for (final state in [
        _activeStates[0],
        _activeStates[1],
        _activeStates[3],
      ]) {
        await enter(state);
        await h.controller.cancel();
        state.release(h);
        await settle();
      }

      expect(h.engine.cancelCalls, 0);
    });

    test(
      'from processing drops the final the in-flight stop delivers',
      () async {
        h.engine.finalBeforeStop = true;
        await enter(_activeStates[3]);

        await h.controller.cancel();
        h.engine.stopGate!.complete();
        await settle();

        expectSessionDiscarded();
        expect(h.engine.stopCalls, 1);
      },
    );

    test('from processing ignores a stop error that arrives later', () async {
      h.engine.stopError = const EngineFailure('decode failed');
      await enter(_activeStates[3]);

      await h.controller.cancel();
      h.engine.stopGate!.complete();
      await settle();

      expectSessionDiscarded();
      expect(h.controller.status, isNot(RecordingStatus.error));
    });

    test('from processing keeps a new session recording when the old decode '
        'finishes during it', () async {
      await enter(_activeStates[3]);
      final oldStopGate = h.engine.stopGate!;
      h.engine.stopGate = null;

      await h.controller.cancel();
      await h.record();
      expect(h.controller.status, RecordingStatus.recording);

      oldStopGate.complete();
      await settle();

      expect(h.controller.status, RecordingStatus.recording);
      expect(h.controller.captureText, '');
      expect(h.controller.transcriptText, _earlierText);
      expect(h.engine.hasListener, isTrue);
    });

    test('while idle changes nothing', () async {
      h.controller.transcriptText = _earlierText;
      h.statuses.clear();

      await h.controller.cancel();

      expect(h.controller.status, RecordingStatus.idle);
      expect(h.controller.transcriptText, _earlierText);
      expect(h.statuses, isEmpty);
      expect(h.engine.cancelCalls, 0);
    });

    test('while in error keeps the error and its message', () async {
      h.permission.result = MicrophonePermissionResult.denied;
      await h.record();

      await h.controller.cancel();

      expect(h.controller.status, RecordingStatus.error);
      expect(h.controller.error, RecordingError.permissionDenied);
    });

    test('twice in a row cancels the engine once', () async {
      await h.record();

      await h.controller.cancel();
      await h.controller.cancel();

      expect(h.controller.status, RecordingStatus.idle);
      expect(h.engine.cancelCalls, 1);
    });

    test('after dispose does nothing and does not throw', () async {
      await h.record();
      h.controller.dispose();

      await expectLater(h.controller.cancel(), completes);
      expect(h.engine.cancelCalls, 0);
    });
  });
}
