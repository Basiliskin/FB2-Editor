import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/voice/model_installation_controller.dart';
import 'package:quill_fb2/services/voice/recording_controller.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/voice_input.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';

import '../support/form_harness.dart';
import '../support/voice/fake_microphone_permission.dart';
import '../support/voice/fake_model_installer.dart';
import '../support/voice/fake_speech_recognition.dart';

void main() {
  late AppService service;
  late ProjectModel book;
  late FakeSpeechRecognition engine;

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
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final section = book.addSection('S');
    section.p = [for (var i = 0; i < 4; i++) '<p>para $i lorem</p>'];
    await tester.pumpWidget(MaterialApp(home: SectionEditor(service, book, section)));
    await tester.pump();
  }

  // The format bar slides in over a few frames; wait for it to settle.
  Future<void> openParagraph(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  String editorText(WidgetTester tester) => tester
      .widget<QuillEditor>(find.byType(QuillEditor))
      .controller
      .document
      .toPlainText();

  testWidgets('no mic in the format bar while Voice input is off',
      (tester) async {
    service.getSettings()['voice-input'] = false;
    await pump(tester);
    await openParagraph(tester, 'para 1 lorem');

    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
    await finish(tester);
  });

  testWidgets('the mic shows only while a paragraph is being edited',
      (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.mic_none), findsNothing);

    await openParagraph(tester, 'para 1 lorem');
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    await finish(tester);
  });

  testWidgets('dictation goes into the open paragraph at the cursor',
      (tester) async {
    engine.finalText = 'and more';
    await pump(tester);
    await openParagraph(tester, 'para 1 lorem');

    await tester.tap(find.byIcon(Icons.mic_none));
    await settle(tester);
    await tester.tap(find.text('Stop'));
    await settle(tester);

    expect(editorText(tester), 'para 1 lorem and more\n');
    await finish(tester);
  });

  testWidgets('the paragraph is locked while dictating, then free again',
      (tester) async {
    engine.finalText = 'x';
    await pump(tester);
    await openParagraph(tester, 'para 1 lorem');
    await tester.tap(find.byIcon(Icons.mic_none));
    await settle(tester);

    final locked = tester.widget<QuillEditor>(find.byType(QuillEditor));
    expect(locked.controller.readOnly, isTrue);

    await tester.tap(find.text('para 3 lorem'));
    await tester.pump();
    expect(editorText(tester), 'para 1 lorem\n');
    expect(find.text('para 3 lorem'), findsOneWidget);

    await tester.tap(find.text('Add paragraph'));
    await tester.pump();
    expect(book.section.first.p.length, 4);

    await tester.tap(find.text('Stop'));
    await settle(tester);
    expect(tester.widget<QuillEditor>(find.byType(QuillEditor)).controller.readOnly,
        isFalse);

    await tester.tap(find.text('para 3 lorem'));
    await tester.pump();
    expect(editorText(tester), 'para 3 lorem\n');
    await finish(tester);
  });

  testWidgets('listens in Auto whatever the book language is', (tester) async {
    book.lang = 'he';
    await pump(tester);
    await openParagraph(tester, 'para 1 lorem');

    await tester.tap(find.byIcon(Icons.mic_none));
    await settle(tester);

    expect(engine.initializedChoices, [SpeechLanguageChoice.auto]);
    await tester.tap(find.text('Stop'));
    await settle(tester);
    await finish(tester);
  });
}
