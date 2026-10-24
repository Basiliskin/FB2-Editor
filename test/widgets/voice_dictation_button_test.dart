import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/voice/dictation_limits.dart';
import 'package:quill_fb2/services/voice/dictation_target.dart';
import 'package:quill_fb2/services/voice/install_failure.dart';
import 'package:quill_fb2/services/voice/microphone_permission.dart';
import 'package:quill_fb2/services/voice/model_installation_controller.dart';
import 'package:quill_fb2/services/voice/recording_controller.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition_failure.dart';
import 'package:quill_fb2/services/voice/voice_input.dart';
import 'package:quill_fb2/widgets/voice/dictation_button.dart';

import '../support/form_harness.dart';
import '../support/voice/fake_microphone_permission.dart';
import '../support/voice/fake_model_installer.dart';
import '../support/voice/fake_speech_recognition.dart';

class _Clock implements Stopwatch {
  Duration now = Duration.zero;
  bool running = false;

  @override
  Duration get elapsed => now;
  @override
  int get elapsedMicroseconds => now.inMicroseconds;
  @override
  int get elapsedMilliseconds => now.inMilliseconds;
  @override
  int get elapsedTicks => now.inMicroseconds;
  @override
  int get frequency => 1000000;
  @override
  bool get isRunning => running;
  @override
  void reset() => now = Duration.zero;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
}

void main() {
  late AppService service;
  late FakeModelInstaller installer;
  late FakeSpeechRecognition engine;
  late FakeMicrophonePermission permission;
  late TextEditingController text;
  late List<bool> busy;
  late _Clock clock;
  var factoryCalls = 0;

  setUp(() {
    mockDocumentsDir();
    service = AppService();
    service.getSettings()['voice-input'] = true;
    installer = FakeModelInstaller()..installed = true;
    engine = FakeSpeechRecognition();
    permission = FakeMicrophonePermission();
    text = TextEditingController(text: 'one three')
      ..selection = const TextSelection.collapsed(offset: 3);
    busy = [];
    clock = _Clock();
    factoryCalls = 0;
    service.voiceInputFactory = () async {
      factoryCalls++;
      return VoiceInput(
        installation: ModelInstallationController(installer: installer),
        recording: RecordingController(
          engine: engine,
          permission: permission,
          debounce: Duration.zero,
        ),
      );
    };
  });

  Future<void> pump(WidgetTester tester,
      {SpeechLanguageChoice choice = SpeechLanguageChoice.auto}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      DictationButton(
        service: service,
        target: TextFieldDictationTarget(text),
        choice: choice,
        onBusyChanged: busy.add,
        stopwatch: clock,
      ),
      TextField(controller: text),
    ]))));
    await tester.pump();
  }

  // The controller finishes on real async time, so alternate a short real
  // delay with a pump. Bounded: pumpAndSettle never ends while a spinner is up.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapMic(WidgetTester tester) async {
    await tester.tap(find.byType(DictationButton));
    await settle(tester);
  }

  Future<void> removeButton(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  }

  testWidgets('is absent while Voice input is off', (tester) async {
    service.getSettings()['voice-input'] = false;
    await pump(tester);

    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(factoryCalls, 0);
  });

  testWidgets('is absent off Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(tester);
      expect(find.byIcon(Icons.mic_none), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('dictates at the cursor saved when recording started',
      (tester) async {
    engine.finalText = 'two';
    await pump(tester);
    await tapMic(tester);
    expect(find.text('Stop'), findsOneWidget);
    expect(engine.startedLanguages, [null]);

    text.selection = const TextSelection.collapsed(offset: 9);
    await tester.tap(find.text('Stop'));
    await settle(tester);

    expect(text.text, 'one two three');
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(busy, [true, false]);
  });

  testWidgets('starts from the language it was given', (tester) async {
    await pump(tester,
        choice: SpeechLanguageChoice.of(SpeechLanguage.hebrew));
    await tapMic(tester);

    expect(engine.initializedChoices,
        [SpeechLanguageChoice.of(SpeechLanguage.hebrew)]);
    await removeButton(tester);
  });

  testWidgets('shows a spinner while the text is being worked out',
      (tester) async {
    engine.finalText = 'two';
    engine.stopGate = Completer<void>();
    await pump(tester);
    await tapMic(tester);
    await tester.tap(find.text('Stop'));
    await settle(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(busy, [true]);

    engine.stopGate!.complete();
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(busy, [true, false]);
  });

  testWidgets('says so when nothing was heard and inserts nothing',
      (tester) async {
    engine.finalText = '';
    await pump(tester);
    await tapMic(tester);
    await tester.tap(find.text('Stop'));
    await settle(tester);

    expect(text.text, 'one three');
    expect(find.text('Nothing was heard.'), findsOneWidget);
  });

  testWidgets('says so in Russian', (tester) async {
    service.getSettings()['language'] = 'ru';
    engine.finalText = '';
    await pump(tester);
    await tapMic(tester);
    await tester.tap(find.text('Стоп'));
    await settle(tester);

    expect(find.text('Ничего не расслышал.'), findsOneWidget);
  });

  testWidgets('a denied microphone explains how to allow it', (tester) async {
    permission.result = MicrophonePermissionResult.denied;
    await pump(tester);
    await tapMic(tester);
    await settle(tester);

    expect(find.textContaining('needs the microphone'), findsOneWidget);
    expect(text.text, 'one three');
    expect(busy.last, isFalse);
  });

  testWidgets('an engine failure is reported', (tester) async {
    engine.initializeError = const EngineFailure('x');
    await pump(tester);
    await tapMic(tester);
    await settle(tester);

    expect(find.text('Dictation failed. Try again.'), findsOneWidget);
  });

  testWidgets('a model gone missing sends the user back to the download',
      (tester) async {
    engine.initializeError =
        const ModelNotInstalled(SpeechLanguage.english);
    await pump(tester);
    await tapMic(tester);
    await settle(tester);

    expect(find.textContaining('model is missing'), findsOneWidget);
  });

  testWidgets('at the length limit the text still lands, with a note',
      (tester) async {
    engine.finalText = 'long speech';
    await pump(tester);
    await tapMic(tester);

    engine.emitError(const AudioTooLong(Duration(seconds: 30)));
    await settle(tester);

    expect(text.text, 'one long speech three');
    expect(find.textContaining('Tap the mic to carry on'), findsOneWidget);
  });

  testWidgets('at the length limit with only silence says nothing was heard',
      (tester) async {
    engine.finalText = '';
    await pump(tester);
    await tapMic(tester);

    engine.emitError(const AudioTooLong(Duration(seconds: 30)));
    await settle(tester);

    expect(text.text, 'one three');
    expect(find.text('Nothing was heard.'), findsOneWidget);
    expect(find.textContaining('too long'), findsNothing);
  });

  testWidgets('counts down the last five seconds', (tester) async {
    await pump(tester);
    await tapMic(tester);
    expect(find.text('Stop'), findsOneWidget);

    clock.now = dictationMaxDuration - const Duration(milliseconds: 3500);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.text('4'));
    await settle(tester);
  });

  testWidgets('the countdown never goes below zero', (tester) async {
    await pump(tester);
    await tapMic(tester);

    clock.now = dictationMaxDuration + const Duration(seconds: 1);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.text('0'));
    await settle(tester);
  });

  testWidgets('leaving the app mid-recording throws the recording away',
      (tester) async {
    engine.finalText = 'never lands';
    await pump(tester);
    await tapMic(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    expect(engine.cancelCalls, 0, reason: 'a shade or dialog keeps recording');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await settle(tester);
    expect(engine.cancelCalls, 1);
    expect(text.text, 'one three');

    // Frames stop while the app is hidden, so the note shows on return.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.text('Recording stopped.'), findsOneWidget);
  });

  testWidgets('removing the button mid-recording cancels it', (tester) async {
    await pump(tester);
    await tapMic(tester);

    await removeButton(tester);

    expect(engine.cancelCalls, 1);
    expect(text.text, 'one three');
  });

  testWidgets('does nothing while a recording is being started or decoded',
      (tester) async {
    permission.gate = Completer<MicrophonePermissionResult>();
    await pump(tester);
    await tapMic(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    await settle(tester);

    expect(permission.requestCalls, 1);
    permission.gate!.complete(MicrophonePermissionResult.granted);
    await settle(tester);
    await tester.tap(find.text('Stop'));
    await settle(tester);
  });

  testWidgets('says so when the voice stack cannot be built', (tester) async {
    service.voiceInputFactory = () => Future.error(StateError('no'));
    await pump(tester);
    await tester.tap(find.byType(DictationButton));
    await settle(tester);

    expect(find.text('Dictation is not available right now.'),
        findsOneWidget);
  });

  testWidgets('a second mic waits, disabled, while another one records',
      (tester) async {
    final other = TextEditingController(text: 'second');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      DictationButton(
          service: service, target: TextFieldDictationTarget(text)),
      DictationButton(
          service: service, target: TextFieldDictationTarget(other)),
    ]))));
    await settle(tester);

    await tester.tap(find.byType(DictationButton).first);
    await settle(tester);

    expect(find.text('Stop'), findsOneWidget);
    final waiting = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .where((b) => b.onPressed == null);
    expect(waiting, hasLength(1));

    await tester.tap(find.text('Stop'));
    await settle(tester);
    expect(find.byIcon(Icons.mic_none), findsNWidgets(2));
    expect(other.text, 'second');
  });

  group('without the Speech Model', () {
    setUp(() => installer.installed = false);

    testWidgets('asks before downloading, and "Not now" downloads nothing',
        (tester) async {
      await pump(tester);
      await tapMic(tester);
      await settle(tester);

      expect(find.text('Download the speech model?'), findsOneWidget);
      expect(find.textContaining('375 MB'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await settle(tester);

      expect(installer.downloadCalls, 0);
      expect(engine.startCalls, 0);
    });

    testWidgets('downloads on request, shows progress, then says it is ready',
        (tester) async {
      await pump(tester);
      await tapMic(tester);
      await settle(tester);
      await tester.tap(find.text('Download'));
      await settle(tester);

      expect(installer.downloadCalls, 1);
      installer.emitProgress(187742663);
      await settle(tester);
      expect(find.text('188 / 375 MB'), findsOneWidget);

      unawaited(installer.finish());
      await settle(tester);
      await settle(tester);
      await settle(tester);

      expect(find.text('Speech model ready. Tap the mic to dictate.'),
          findsOneWidget);
      expect(engine.startCalls, 0);
    });

    testWidgets('a failed download offers to try again', (tester) async {
      await pump(tester);
      await tapMic(tester);
      await settle(tester);
      await tester.tap(find.text('Download'));
      await settle(tester);

      installer.fail(const NetworkFailure());
      await settle(tester);
      expect(find.textContaining('download failed'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(installer.downloadCalls, 2);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });

    testWidgets('Close after a failed download leaves the mic ready',
        (tester) async {
      await pump(tester);
      await tapMic(tester);
      await settle(tester);
      await tester.tap(find.text('Download'));
      await settle(tester);
      installer.fail(const NetworkFailure());
      await settle(tester);

      await tester.tap(find.text('Close'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.textContaining('Speech model ready'), findsNothing);
    });

    testWidgets('failure texts cover every kind, in both languages',
        (tester) async {
      service.getSettings()['language'] = 'ru';
      await pump(tester);
      await tapMic(tester);
      await settle(tester);
      await tester.tap(find.text('Загрузить'));
      await settle(tester);

      for (final (failure, snippet) in <(InstallFailure, String)>[
        (const FingerprintMismatch(), 'повреждён'),
        (const StorageFailure(), 'Не хватает места'),
      ]) {
        installer.fail(failure);
        await settle(tester);
        expect(find.textContaining(snippet), findsOneWidget);
        await tester.tap(find.text('Повторить'));
        await settle(tester);
      }
      await tester.tap(find.text('Отмена'));
      await settle(tester);
    });

    testWidgets('cancelling the download stops the transfer', (tester) async {
      await pump(tester);
      await tapMic(tester);
      await settle(tester);
      await tester.tap(find.text('Download'));
      await settle(tester);

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(installer.isTransferring, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a second mic joins a download that is already running',
        (tester) async {
      await pump(tester);
      final voice = (await tester.runAsync(() => service.voiceInput()))!;
      voice.installation.startDownload();
      installer.emitProgress(1048576);

      await tapMic(tester);
      await settle(tester);

      expect(find.text('Download the speech model?'), findsNothing);
      expect(find.textContaining('1 / 375 MB'), findsOneWidget);
      expect(installer.downloadCalls, 1);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });
  });
}
