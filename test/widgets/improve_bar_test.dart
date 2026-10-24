import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
import 'package:quill_fb2/widgets/section_editor/improve_bar.dart';
import 'package:quill_fb2/services/llm/improvement.dart' show defaultPresets;
import 'package:quill_fb2/widgets/section_editor/improve_controller.dart';

// No real LLM is called: every request goes to a MockClient.
void main() {
  late Map settings;
  late List<String> sent;
  late ImproveController c;
  late AppService service;
  late int managed;
  late ProviderStore store;

  http.Response ok(String text) => http.Response(
      jsonEncode({
        'choices': [
          {'message': {'content': text}}
        ]
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'});

  Future<void> open(WidgetTester tester,
      {Future<http.Response> Function(http.Request)? answer, bool withProvider = true, bool second = false}) async {
    settings = {};
    sent = [];
    managed = 0;
    store = ProviderStore(
        getSettings: () => settings,
        setSettings: (m) async => settings.addAll(m),
        session: MemoryKeyVault(),
        persistent: MemoryKeyVault(),
        isWeb: false);
    if (withProvider) await store.save(const Provider(id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));
    if (second) await store.save(const Provider(id: 'q', name: 'Q', vendor: LlmVendor.openai, model: 'm2', apiKey: 'k'));
    service = AppService()..providerStore = store;
    final section = Section({
      'p': ['<p>one</p>', '<p>two</p>', '<p>three</p>'],
      'sectionId': 's'
    }, BinaryResources([]));
    c = ImproveController(
        store: store,
        section: section,
        bookId: 'book',
        bookInfo: () => (title: 'T', lang: 'en', genre: 'prose'),
        flush: () {},
        afterApply: () {},
        httpFactory: () => MockClient((r) {
              sent.add(r.body);
              return answer == null ? Future.value(ok('[1] ONE')) : answer(r);
            }));
    await c.toggle(0);
    tester.view.physicalSize = const Size(390 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ImproveBar(service: service, controller: c, onManageProviders: () => managed++))));
    await tester.pumpAndSettle();
  }

  Future<void> openTranslateDialog(WidgetTester tester) async {
    await tester.ensureVisible(find.textContaining('Translate'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Translate'));
    await tester.pumpAndSettle();
  }

  testWidgets('Translate with one paragraph chosen leaves "Whole Section" off and sends only that paragraph',
      (tester) async {
    await open(tester);
    await openTranslateDialog(tester);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send')); // first use of the provider asks
    await tester.pumpAndSettle();
    expect((c.start, c.end), (0, 0));
    expect(sent.single, contains('one'));
    expect(sent.single, isNot(contains('three')));
  });

  testWidgets('"Whole Section" widens the selection only when switched on', (tester) async {
    await open(tester);
    await openTranslateDialog(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect((c.start, c.end), (0, 2));
  });

  testWidgets('the switch is not offered when everything is already chosen', (tester) async {
    await open(tester);
    c.selectAll();
    await tester.pump();
    await openTranslateDialog(tester);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('the paragraph chip selects all, then clears, then selects all again', (tester) async {
    await open(tester);
    await tester.tap(find.text('Paragraph 1'));
    await tester.pump();
    expect(c.allSelected, isTrue);
    await tester.tap(find.text('Paragraphs 1-3'));
    await tester.pump();
    expect(c.noneSelected, isTrue);
    expect(find.text('No paragraphs (select all)'), findsOneWidget);
    await tester.tap(find.text('No paragraphs (select all)'));
    await tester.pump();
    expect(c.allSelected, isTrue);
  });

  /// The chip row is a horizontal scroller, so long-press is fired on its GestureDetector directly.
  Future<void> longPressChip(WidgetTester tester, String label) async {
    final g = find
        .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
        .evaluate()
        .map((e) => e.widget as GestureDetector)
        .firstWhere((d) => d.onLongPress != null);
    g.onLongPress!();
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets('a preset chip asks, shows the suggestion, and Accept applies it', (tester) async {
    await open(tester);
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(c.suggestions, {0: 'ONE'});
    expect(sent.single, contains('one'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      SuggestionCard(service: service, controller: c, index: 0, before: 'one'),
      ImproveBar(service: service, controller: c, onManageProviders: () {}),
    ]))));
    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    expect(c.suggestions, isEmpty);
  });

  testWidgets('SuggestionCard Reject drops the suggestion', (tester) async {
    await open(tester);
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await send(tester);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SuggestionCard(service: service, controller: c, index: 0, before: 'one'))));
    await tester.tap(find.byTooltip('Reject'));
    await tester.pumpAndSettle();
    expect(c.suggestions, isEmpty);
  });

  testWidgets('Accept all appears for several suggestions', (tester) async {
    await open(tester, answer: (r) async => ok('[1] ONE\n[2] TWO\n[3] THREE'));
    c.selectAll();
    await tester.pump();
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await send(tester);
    await tester.ensureVisible(find.text('Accept all'));
    await tester.tap(find.text('Accept all'));
    await tester.pumpAndSettle();
    expect(c.suggestions, isEmpty);
  });

  testWidgets('typing an instruction and submitting asks', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'make it rhyme');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await send(tester);
    expect(sent.single, contains('make it rhyme'));
  });

  testWidgets('an empty instruction is not sent', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsNothing);
    expect(sent, isEmpty);
  });

  testWidgets('a rejected key shows the error and a way to the provider settings', (tester) async {
    await open(tester, answer: (r) async => http.Response('', 401));
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(find.text('The provider rejected the API key'), findsOneWidget);
    await tester.tap(find.text('Edit provider'));
    expect(managed, 1);
  });

  testWidgets('a failure mid-way offers Retry, which carries on', (tester) async {
    var fail = true;
    await open(tester, answer: (r) async => fail ? http.Response('', 500) : ok('[1] ONE'));
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(c.suggestions, {0: 'ONE'});
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('while a request runs the bar shows progress, disables chips, and Cancel stops it', (tester) async {
    final gate = Completer<http.Response>();
    await open(tester, answer: (r) => gate.future);
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.busy, isTrue);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<ActionChip>(find.widgetWithText(ActionChip, 'Proofread')).onPressed, isNull);
    await tester.tap(find.descendant(of: find.byType(ImproveBar), matching: find.text('Cancel')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.busy, isFalse);
    gate.complete(ok('late'));
    await tester.pumpAndSettle();
    expect(c.suggestions, isEmpty);
  });

  testWidgets('without a provider the bar says so and offers to add one', (tester) async {
    await open(tester, withProvider: false);
    expect(find.textContaining('Connect an AI provider'), findsOneWidget);
    await tester.tap(find.text('Add provider'));
    expect(managed, 1);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(c.open, isFalse);
  });

  testWidgets('the provider chip lists providers; picking one switches, Manage opens the settings', (tester) async {
    await open(tester, second: true);
    await tester.tap(find.widgetWithText(ActionChip, 'P'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Q'));
    await tester.pumpAndSettle();
    expect(c.current?.id, 'q');
    await tester.tap(find.widgetWithText(ActionChip, 'Q'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Manage providers'));
    await tester.pumpAndSettle();
    expect(managed, 1);
  });

  testWidgets('the style note is saved from its dialog', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Style note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'keep the 19th-century tone');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.styleNote, 'keep the 19th-century tone');
    await tester.tap(find.byTooltip('Style note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.styleNote, 'keep the 19th-century tone');
  });

  testWidgets('a custom preset is created, offered as a chip, edited and deleted', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('New preset'));
    await tester.tap(find.text('New preset'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    final dialogFields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogFields.first, 'Pirate');
    await tester.enterText(dialogFields.last, 'Talk like a pirate');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pirate'), findsOneWidget);

    await longPressChip(tester, 'Pirate');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, 'Pirate 2');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pirate 2'), findsOneWidget);

    await longPressChip(tester, 'Pirate 2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Pirate 2'), findsNothing);
  });

  testWidgets('the Close button closes the bar', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(c.open, isFalse);
  });

  testWidgets('a translation shows its parts, the title offer, and Accept ready', (tester) async {
    await open(tester, answer: (r) async => ok('[1] ONE\n[2] TWO\n[3] THREE'));
    c.selectAll();
    await tester.pump();
    await tester.ensureVisible(find.textContaining('Translate'));
    await tester.tap(find.textContaining('Translate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(c.translating, isTrue);
    expect(find.byType(Chip), findsWidgets);
    await tester.ensureVisible(find.text('Accept ready'));
    await tester.tap(find.text('Accept ready'));
    await tester.pumpAndSettle();
    expect(c.suggestions, isEmpty);
  });

  Future<void> failWith(WidgetTester tester, Future<http.Response> Function(http.Request) answer, String text) async {
    await open(tester, answer: answer);
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(find.textContaining(text), findsOneWidget);
  }

  testWidgets('a rate limit says so', (tester) async {
    await failWith(tester, (r) async => http.Response('', 429), 'Rate limit reached');
  });

  testWidgets('an unreachable provider says so', (tester) async {
    await failWith(tester, (r) async => throw http.ClientException('down'), 'reach the provider');
  });

  testWidgets('an unusable answer says so', (tester) async {
    await failWith(tester, (r) async => http.Response('not json', 200), 'unusable answer');
  });

  testWidgets('a cut-off answer says so', (tester) async {
    await failWith(
        tester,
        (r) async => http.Response(
            jsonEncode({
              'choices': [
                {'message': {'content': '[1] ON'}, 'finish_reason': 'length'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'}),
        'cut off');
  });

  testWidgets('asking with nothing chosen says there is nothing to change', (tester) async {
    await open(tester);
    c.clearSelection();
    await tester.pump();
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to change in the chosen paragraphs'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('a paragraph too long for one request is refused before anything is sent', (tester) async {
    await open(tester);
    c.section.p[0] = '<p>${'слово ' * 20000}</p>';
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    expect(find.text('A single paragraph is too long to send'), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('a suggested title can be accepted or rejected from the bar', (tester) async {
    await open(tester);
    c.titleSuggestion = 'Новый заголовок';
    c.notifyListeners();
    await tester.pump();
    expect(find.text('Title: Новый заголовок'), findsOneWidget);
    await tester.tap(find.byTooltip('Reject title'));
    await tester.pump();
    expect(find.textContaining('Title:'), findsNothing);
    c.titleSuggestion = 'Другой';
    c.notifyListeners();
    await tester.pump();
    await tester.tap(find.byTooltip('Accept title'));
    await tester.pump();
    expect(c.titleSuggestion, isNull);
  });

  testWidgets('a multi-part request shows which part is running', (tester) async {
    final gate = Completer<http.Response>();
    await open(tester, answer: (r) => gate.future);
    c.chunks = 3;
    c.chunk = 2;
    c.busy = true;
    c.notifyListeners();
    await tester.pump();
    expect(find.text('Part 2 of 3'), findsOneWidget);
    c.busy = false;
    c.notifyListeners();
    await tester.pump();
  });

  group('translation pieces', () {
    Widget host(Widget w) => MaterialApp(home: Scaffold(body: w));

    testWidgets('PartHeader of a ready part accepts and rejects', (tester) async {
      await open(tester, answer: (r) async => ok('[1] ONE\n[2] TWO\n[3] THREE'));
      c.selectAll();
      await tester.pump();
      await tester.ensureVisible(find.textContaining('Translate'));
      await tester.tap(find.textContaining('Translate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
      await tester.pumpAndSettle();
      await send(tester);
      final part = c.parts.first;
      expect(part.status, PartStatus.ready);
      await tester.pumpWidget(host(PartHeader(service: service, controller: c, part: part)));
      expect(find.text('Part 1'), findsOneWidget);
      await tester.tap(find.text('Reject'));
      await tester.pump();
      expect(c.suggestions, isEmpty);
    });

    testWidgets('PartHeader of a ready part: Accept applies it', (tester) async {
      await open(tester, answer: (r) async => ok('[1] ONE\n[2] TWO\n[3] THREE'));
      c.selectAll();
      await tester.pump();
      await tester.ensureVisible(find.textContaining('Translate'));
      await tester.tap(find.textContaining('Translate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
      await tester.pumpAndSettle();
      await send(tester);
      await tester.pumpWidget(host(PartHeader(service: service, controller: c, part: c.parts.first)));
      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(c.suggestions, isEmpty);
    });

    testWidgets('PartHeader of a failed part shows the reason and Retry', (tester) async {
      var fail = true;
      await open(tester, answer: (r) async => fail ? http.Response('', 500) : ok('[1] ONE\n[2] TWO\n[3] THREE'));
      c.selectAll();
      await tester.pump();
      await tester.ensureVisible(find.textContaining('Translate'));
      await tester.tap(find.textContaining('Translate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
      await tester.pumpAndSettle();
      await send(tester);
      final part = c.parts.first;
      expect(part.status, PartStatus.failed);
      await tester.pumpWidget(host(PartHeader(service: service, controller: c, part: part)));
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(c.parts.first.status, PartStatus.ready);
    });

    testWidgets('TranslationPair puts the original beside the translation', (tester) async {
      await tester.pumpWidget(host(const TranslationPair(before: 'one', after: 'один', style: TextStyle())));
      expect(find.text('one'), findsOneWidget);
      expect(find.text('один'), findsOneWidget);
    });
  });

  testWidgets('Cancel on the send confirmation sends nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Proofread'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(c.busy, isFalse);
  });

  testWidgets('the preset dialog can be cancelled', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('New preset'));
    await tester.tap(find.text('New preset'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(c.presets.length, defaultPresets.length);
  });

  testWidgets('Translate: Cancel does nothing; "Other..." takes a language typed in English', (tester) async {
    await open(tester);
    await openTranslateDialog(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);

    await openTranslateDialog(tester);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other...').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Translate')).onPressed, isNull);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Latin');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pumpAndSettle();
    await send(tester);
    expect(sent.single, contains('Latin'));
  });

  testWidgets('a running part shows a spinner and a waiting part an hourglass', (tester) async {
    final gate = Completer<http.Response>();
    await open(tester, answer: (r) => gate.future);
    c.section.p[0] = '<p>${'слово ' * 3000}</p>';
    c.section.p[1] = '<p>${'слово ' * 3000}</p>';
    c.selectAll();
    await tester.pump();
    await tester.ensureVisible(find.textContaining('Translate'));
    await tester.tap(find.textContaining('Translate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pumpAndSettle();
    if (find.text('Send').evaluate().isNotEmpty) await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byIcon(Icons.hourglass_empty), findsWidgets);
    expect(find.descendant(of: find.byType(Chip), matching: find.byType(CircularProgressIndicator)), findsWidgets);
    c.cancel();
    gate.complete(http.Response('', 401));
    await tester.pumpAndSettle();
  });
}
