import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/microphone_permission.dart';
import 'package:quill_fb2/services/voice/recognition_result.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';

import '../../support/voice/fake_microphone_permission.dart';
import '../../support/voice/fake_model_installer.dart';
import '../../support/voice/fake_speech_recognition.dart';

void main() {
  test('FakeSpeechRecognition delivers partials and one final result',
      () async {
    final engine = FakeSpeechRecognition()
      ..finalText = 'hello'
      ..finalLang = 'en';
    await engine.initialize(SpeechLanguageChoice.auto);
    final results = <RecognitionResult>[];
    final sub = engine.start().listen(results.add);

    engine.emitPartial('hel');
    expect(await engine.stop(), 'hello');
    await sub.cancel();

    expect(results, const [
      RecognitionResult(text: 'hel', isFinal: false),
      RecognitionResult(text: 'hello', isFinal: true, lang: 'en'),
    ]);
    expect(engine.initializedChoices, [SpeechLanguageChoice.auto]);
    expect(engine.stopCalls, 1);
  });

  test('FakeSpeechRecognition cancel closes the stream with no result',
      () async {
    final engine = FakeSpeechRecognition();
    await engine.initialize(SpeechLanguageChoice.of(SpeechLanguage.hebrew));
    var done = false;
    engine.start().listen((_) {}, onDone: () => done = true);

    await engine.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(done, isTrue);
    expect(engine.startedLanguages, [SpeechLanguage.hebrew]);
    expect(engine.cancelCalls, 1);
  });

  test('FakeMicrophonePermission answers or waits on its gate', () async {
    final mic = FakeMicrophonePermission(MicrophonePermissionResult.denied);
    expect(await mic.request(), MicrophonePermissionResult.denied);
    expect(mic.requestCalls, 1);
  });

  test('FakeModelInstaller reports progress and becomes installed', () async {
    final installer = FakeModelInstaller();
    expect(await installer.isInstalled(), isFalse);
    final progress = <int>[];
    final done = installer.download().listen(progress.add).asFuture<void>();

    installer.emitProgress(5);
    expect(installer.isTransferring, isTrue);
    await installer.finish();
    await done;

    expect(progress, [5]);
    expect(await installer.isInstalled(), isTrue);
  });
}
