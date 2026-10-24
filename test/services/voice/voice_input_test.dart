import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/voice/file_system_model_installer.dart';
import 'package:quill_fb2/services/voice/install_failure.dart';
import 'package:quill_fb2/services/voice/model_installation_controller.dart';
import 'package:quill_fb2/services/voice/model_status.dart';
import 'package:quill_fb2/services/voice/recording_controller.dart';
import 'package:quill_fb2/services/voice/recording_error.dart';
import 'package:quill_fb2/services/voice/sherpa_onnx_speech_recognition.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition_failure.dart';
import 'package:quill_fb2/services/voice/voice_input.dart';
import 'package:quill_fb2/services/voice/voice_input_device.dart';
import 'package:quill_fb2/services/voice/whisper_model_files.dart';
import 'package:quill_fb2/widgets/voice/voice_texts.dart';

import '../../support/form_harness.dart';
import '../../support/voice/fake_microphone_permission.dart';
import '../../support/voice/fake_model_installer.dart';
import '../../support/voice/fake_speech_recognition.dart';

VoiceInput _fakeVoice(FakeSpeechRecognition engine) => VoiceInput(
      installation: ModelInstallationController(installer: FakeModelInstaller()),
      recording: RecordingController(
          engine: engine, permission: FakeMicrophonePermission()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceInput', () {
    test('dispose releases the engine and stops both controllers', () async {
      final engine = FakeSpeechRecognition();
      final voice = _fakeVoice(engine);

      voice.dispose();

      expect(engine.disposeCalls, 1);
      await voice.recording.record();
      expect(engine.startCalls, 0);
    });
  });

  group('AppService.voiceInput', () {
    late AppService service;
    var builds = 0;

    setUp(() {
      mockDocumentsDir();
      service = AppService();
      builds = 0;
    });

    test('builds the voice stack once, however many ask at the same time',
        () async {
      service.voiceInputFactory = () async {
        builds++;
        return _fakeVoice(FakeSpeechRecognition());
      };

      final both = await Future.wait([service.voiceInput(), service.voiceInput()]);
      final later = await service.voiceInput();

      expect(builds, 1);
      expect(identical(both[0], both[1]), isTrue);
      expect(identical(both[0], later), isTrue);
    });

    test('a failed build is reported and tried again next time', () async {
      service.voiceInputFactory = () async {
        builds++;
        if (builds == 1) throw StateError('no microphone');
        return _fakeVoice(FakeSpeechRecognition());
      };

      await expectLater(service.voiceInput(), throwsStateError);
      final voice = await service.voiceInput();

      expect(builds, 2);
      expect(voice, isNotNull);
    });
  });

  group('createDeviceVoiceInput', () {
    test('keeps the Speech Model in the app\'s private folder, not yet there',
        () async {
      final dir = mockDocumentsDir();

      final voice = await createDeviceVoiceInput();
      await voice.installation.refresh();

      expect(voice.installation.status, const NotInstalled());
      expect(Directory('${dir.path}/speech_model').existsSync(), isFalse);
      voice.dispose();
    });
  });

  group('FileSystemModelInstaller defaults', () {
    test('looks for the three pinned Speech Model files', () async {
      final dir = Directory.systemTemp.createTempSync('model_dir');
      addTearDown(() => dir.deleteSync(recursive: true));

      final installer = FileSystemModelInstaller(modelDirectory: dir);

      expect(await installer.isInstalled(), isFalse);
    });
  });

  test('the engine reports a worker that will not start as EngineFailure',
      () async {
    final engine = SherpaOnnxSpeechRecognition(
      modelFiles: (language) async =>
          const WhisperModelFiles(encoder: 'e', decoder: 'd', tokens: 't'),
      audioSource: () => const Stream.empty(),
      decoderFactory: () => throw IsolateSpawnException('no isolate'),
    );

    await expectLater(
      engine.initialize(SpeechLanguageChoice.auto),
      throwsA(isA<EngineFailure>()
          .having((e) => e.reason, 'reason', contains('IsolateSpawnException'))),
    );
  });

  group('voice texts', () {
    late AppService en;
    late AppService ru;

    setUp(() {
      mockDocumentsDir();
      en = AppService();
      ru = AppService()..getSettings()['language'] = 'ru';
    });

    test('every recording error has a message in both languages', () {
      for (final error in RecordingError.values) {
        final a = recordingErrorText(en, error);
        final b = recordingErrorText(ru, error);
        expect(a, isNotEmpty, reason: '$error');
        expect(b, isNotEmpty, reason: '$error');
        expect(a, isNot(b), reason: '$error');
      }
      expect(recordingErrorText(en, RecordingError.audioTooLong),
          contains('too long'));
    });

    test('every download failure has a message in both languages', () {
      for (final failure in <InstallFailure>[
        const NetworkFailure(),
        const FingerprintMismatch(),
        const StorageFailure(),
        const InstallCancelled(),
      ]) {
        expect(modelFailureText(en, failure), isNotEmpty, reason: '$failure');
        expect(modelFailureText(en, failure),
            isNot(modelFailureText(ru, failure)),
            reason: '$failure');
      }
    });
  });
}
