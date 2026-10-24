import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/pages/ask_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
import 'package:quill_fb2/services/voice/model_installation_controller.dart';
import 'package:quill_fb2/services/voice/recording_controller.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/voice_input.dart';
import 'package:quill_fb2/widgets/find_replace_dialog.dart';
import 'package:quill_fb2/widgets/forms/book_form.dart';

import '../support/form_harness.dart';
import '../support/voice/fake_microphone_permission.dart';
import '../support/voice/fake_model_installer.dart';
import '../support/voice/fake_speech_recognition.dart';

void main() {
  late AppService service;
  late FakeSpeechRecognition engine;
  late ProjectModel book;

  setUp(() {
    mockDocumentsDir();
    service = AppService();
    service.getSettings()['voice-input'] = true;
    engine = FakeSpeechRecognition();
    service.voiceInputFactory = () async => VoiceInput(
          installation: ModelInstallationController(
              installer: FakeModelInstaller()..installed = true),
          recording: RecordingController(
            engine: engine,
            permission: FakeMicrophonePermission(),
            debounce: Duration.zero,
          ),
        );
    book = ProjectModel.fromJson({'title': 'B', 'section': []});
    book.addSection('Ch').p = ['<p>one cat</p>', '<p>cat two</p>'];
  });

  // The controller finishes on real async time, so alternate a short real
  // delay with a pump. Bounded: pumpAndSettle never ends under a spinner.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // Taps the n-th mic, lets the dictation finish.
  Future<void> dictate(WidgetTester tester, int mic, String words) async {
    engine.finalText = words;
    await tester.tap(find.byIcon(Icons.mic_none).at(mic));
    await settle(tester);
    await tester.tap(find.text('Stop'));
    await settle(tester);
  }

  group('Book info', () {
    late StreamController<void> save;

    Future<void> open(WidgetTester tester) async {
      bigScreen(tester);
      save = StreamController<void>.broadcast();
      addTearDown(save.close);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: BookComponent(service, book, save.stream))));
      await tester.pump();
    }

    testWidgets('has a mic on the title, author names, keywords and annotation',
        (tester) async {
      await open(tester);

      // title, first/middle/last name, keywords, annotation
      expect(find.byIcon(Icons.mic_none), findsNWidgets(6));
    });

    testWidgets('has no mic while Voice input is off', (tester) async {
      service.getSettings()['voice-input'] = false;
      await open(tester);

      expect(find.byIcon(Icons.mic_none), findsNothing);
    });

    testWidgets('a dictated title is typed into the field and saved',
        (tester) async {
      await open(tester);

      await dictate(tester, 0, 'War and Peace');

      expect(find.widgetWithText(TextField, 'War and Peace'), findsOneWidget);
      save.add(null);
      await settle(tester);
      expect(book.bookTitle, 'War and Peace');
    });

    testWidgets('the book language is not forced on the recognizer', (tester) async {
      book.lang = 'ru';
      await open(tester);

      await dictate(tester, 0, 'слово');

      expect(engine.initializedChoices, [SpeechLanguageChoice.auto]);
    });

    testWidgets('a dictated annotation is added with the Add button',
        (tester) async {
      await open(tester);

      await dictate(tester, 5, 'A long story.');
      await tester.tap(find.text('Add'));
      await settle(tester);

      expect(find.text('A long story.'), findsOneWidget);
    });
  });

  group('Find and replace', () {
    Future<void> open(WidgetTester tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (c) => TextButton(
                  onPressed: () => showFindReplace(c, service, book),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('a dictated search word is searched at once', (tester) async {
      await open(tester);

      await dictate(tester, 0, 'cat');

      expect(find.widgetWithText(TextField, 'cat'), findsOneWidget);
      expect(find.text('Found: 2 in 2 places'), findsOneWidget);
    });

    testWidgets('a dictated replacement fills the Replace field',
        (tester) async {
      await open(tester);

      await dictate(tester, 1, 'dog');

      expect(find.widgetWithText(TextField, 'dog'), findsOneWidget);
      expect(find.textContaining('Found:'), findsNothing);
    });
  });

  group('Ask about the book', () {
    Future<void> open(WidgetTester tester) async {
      bigScreen(tester);
      service.providerStore = ProviderStore(
          getSettings: () => service.getSettings(),
          setSettings: (m) => service.setSettings(m),
          session: MemoryKeyVault(),
          persistent: MemoryKeyVault(),
          isWeb: false);
      await tester.runAsync(() => service.providerStore.save(const Provider(
          id: 'p',
          name: 'P',
          vendor: LlmVendor.openai,
          model: 'm',
          apiKey: 'k')));
      await tester.pumpWidget(MaterialApp(home: AskPage(service, book)));
      await settle(tester);
      await tester.tap(find.text('Ask').first);
      await settle(tester);
    }

    testWidgets('a dictated question fills the box and enables Ask',
        (tester) async {
      await open(tester);
      expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
          isNull);

      await dictate(tester, 0, 'Who is the cat?');

      expect(find.widgetWithText(TextField, 'Who is the cat?'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
          isNotNull);
    });
  });
}
