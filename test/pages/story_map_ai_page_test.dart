import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart' show StorySection;
import 'package:quill_fb2/pages/story_map_ai_page.dart';
import 'package:quill_fb2/pages/story_map_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';

import '../support/story_fixtures.dart';

late AppService _service;
late Map _settings;
late int _changes;

http.Client _answering(String text, [List<String>? sent]) => MockClient((r) async {
      sent?.add(r.body);
      return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': text}}
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

/// The AI page on a sample book; returns the map it edits.
Future<(ProjectModel, StoryMap)> _open(WidgetTester tester, {http.Client Function()? http, bool pick = true}) async {
  tester.view.physicalSize = const Size(390 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final book = (await tester.runAsync(() => storyBook()))!;
  final map = (await tester.runAsync(() => book.loadStoryMap()))!;
  await tester.pumpWidget(const MaterialApp(home: Scaffold()));
  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.push(MaterialPageRoute(builder: (_) => StoryMapAiPage(_service, book, map, () => _changes++, httpFactory: http)));
  await tester.pumpAndSettle();
  if (pick && find.text('Select all').evaluate().isNotEmpty) {
    await tester.tap(find.text('Select all'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }
  return (book, map);
}

const _answer = '## entity\nname: библиотека\nkind: place\nnote: Where the ships come in.\n\n'
    '## entity\nname: Атлантида\nkind: place\nnote: Made up.\n\n'
    '## tie\na: Артур Рэйм\nb: библиотека\nlabel: works at';

void main() {
  setUp(() {
    _changes = 0;
    _settings = {};
    _service = AppService()
      ..providerStore = ProviderStore(
          getSettings: () => _settings,
          setSettings: (m) async => _settings.addAll(m),
          session: MemoryKeyVault(),
          persistent: MemoryKeyVault(),
          isWeb: false);
  });

  Future<void> provider() => _service.providerStore
      .save(const Provider(id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));

  testWidgets('without a provider it says what to do and sends nothing', (tester) async {
    await _open(tester);
    expect(find.textContaining('Connect an AI provider'), findsOneWidget);
  });

  testWidgets('no section is chosen at first, and nothing can go until one is', (tester) async {
    await provider();
    await _open(tester, pick: false);
    expect(find.text('Nothing selected'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.textContaining('1 section(s)'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNotNull);
  });

  testWidgets('shows the size first; Cancel sends nothing and goes back to the choice', (tester) async {
    await provider();
    final sent = <String>[];
    await _open(tester, http: () => _answering(_answer, sent));
    expect(find.textContaining('will be sent to P'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('the model is asked to write in the language of the book', (tester) async {
    await provider();
    final sent = <String>[];
    await _open(tester, http: () => _answering(_answer, sent));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent.single, contains('English')); // the sample book is lang "en"
  });

  testWidgets('leaving while the request runs asks first', (tester) async {
    await provider();
    final gate = Completer<http.Response>();
    await _open(tester, http: () => MockClient((r) => gate.future));
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump();
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500)); // the progress bar never settles
    expect(find.text('Stop the running request?'), findsOneWidget);
    await tester.tap(find.text('Keep waiting'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StoryMapAiPage), findsOneWidget);
    gate.complete(http.Response('', 401));
    await tester.pumpAndSettle();
  });

  testWidgets('proposals the text does not support never show; accepting one changes the map', (tester) async {
    await provider();
    final sent = <String>[];
    final (_, map) = await _open(tester, http: () => _answering(_answer, sent));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent.single, contains('## S1: Приезд'));
    expect(sent.single, contains('Артур Рэйм (person)'));
    expect(find.text('библиотека'), findsOneWidget);
    expect(find.text('Атлантида'), findsNothing);
    expect(find.text('Артур Рэйм — библиотека'), findsOneWidget);

    final before = map.cast.length;
    await tester.tap(find.byTooltip('Accept').first); // the entity
    await tester.pumpAndSettle();
    expect(map.cast.length, before + 1);
    expect(map.cast.last.kind, EntityKind.place);
    expect(_changes, 1);

    await tester.tap(find.byTooltip('Accept').first); // the tie, now resolvable
    await tester.pumpAndSettle();
    expect(map.tieBetween(0, map.cast.length - 1)!.label, 'works at');
    expect(find.text('Nothing more to propose.'), findsOneWidget);
  });

  testWidgets('a proposal can be edited before it is accepted; ties follow a rename', (tester) async {
    await provider();
    final (_, map) = await _open(tester, http: () => _answering(_answer));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first); // the place
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Старая библиотека');
    await tester.enterText(find.byType(TextField).last, 'My note');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('библиотека'), findsNothing);
    expect(find.text('Артур Рэйм — Старая библиотека'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit').at(1)); // the tie
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'reads in');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Accept').at(1));
    await tester.pumpAndSettle();
    final e = map.cast.last;
    expect((e.name, e.note), ('Старая библиотека', 'My note'));
    expect(map.tieBetween(0, map.cast.length - 1)!.label, 'reads in');
  });

  testWidgets('Reject drops a proposal without touching the map', (tester) async {
    await provider();
    final (_, map) = await _open(tester, http: () => _answering(_answer));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    final before = map.cast.length;
    await tester.tap(find.byTooltip('Reject').first);
    await tester.pumpAndSettle();
    expect(find.text('библиотека'), findsNothing);
    expect(map.cast.length, before);
    expect(_changes, 0);
  });

  testWidgets('accepting a tie also adds the place it names', (tester) async {
    await provider();
    final (_, map) = await _open(tester, http: () => _answering(_answer));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    final before = map.cast.length;
    await tester.tap(find.byTooltip('Accept').at(1)); // the tie under the place
    await tester.pumpAndSettle();
    expect(map.cast.length, before + 1);
    expect(map.tieBetween(0, map.cast.length - 1)!.label, 'works at');
    expect(find.text('библиотека'), findsNothing);
  });

  testWidgets('rejecting a place takes its ties along', (tester) async {
    await provider();
    await _open(tester, http: () => _answering(_answer));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Артур Рэйм — библиотека'), findsOneWidget);
    await tester.tap(find.byTooltip('Reject').first);
    await tester.pumpAndSettle();
    expect(find.text('Артур Рэйм — библиотека'), findsNothing);
    expect(find.text('Nothing more to propose.'), findsOneWidget);
  });

  testWidgets('filter chips narrow the list, and Accept all applies only to what shows', (tester) async {
    await provider();
    const two = '## entity\nname: библиотека\nkind: place\nnote: Books.\n\n'
        '## entity\nname: гостиная\nkind: event\nnote: A party.\n\n'
        '## tie\na: Артур Рэйм\nb: библиотека\nlabel: works at';
    final (_, map) = await _open(tester, http: () => _answering(two));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Accept all (3)'), findsOneWidget);
    await tester.tap(find.text('Events 1'));
    await tester.pumpAndSettle();
    expect(find.text('гостиная'), findsNothing);
    expect(find.text('Accept all (2)'), findsOneWidget);
    await tester.tap(find.text('Ties 1'));
    await tester.pumpAndSettle();
    expect(find.text('Артур Рэйм — библиотека'), findsNothing);
    expect(find.text('Accept all (1)'), findsNothing); // a single row has its own ✓
    await tester.tap(find.byTooltip('Accept').first);
    await tester.pumpAndSettle();
    expect(map.cast.any((e) => e.name == 'библиотека'), isTrue);
    expect(map.cast.any((e) => e.name == 'гостиная'), isFalse); // filtered out, so left alone
    expect(map.ties.any((t) => t.label == 'works at'), isFalse);
  });

  testWidgets('Accept all adds the entity and then labels the tie', (tester) async {
    await provider();
    final (_, map) = await _open(tester, http: () => _answering(_answer));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Accept all'));
    await tester.pumpAndSettle();
    expect(map.cast.any((e) => e.name == 'библиотека'), isTrue);
    expect(map.ties.any((t) => t.label == 'works at'), isTrue);
  });

  testWidgets('a provider failure is shown, and the choice stays', (tester) async {
    await provider();
    await _open(tester, http: () => MockClient((r) async => http.Response('', 401)));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('The provider rejected the API key'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget); // back at the choice, to try again
  });

  testWidgets('a book without text says so instead of offering a choice', (tester) async {
    await provider();
    tester.view.physicalSize = const Size(390 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final book = (await tester.runAsync(() => storyBook([StorySection('a', 'Пусто', [])])))!;
    final map = (await tester.runAsync(() => book.loadStoryMap()))!;
    await tester.pumpWidget(MaterialApp(home: StoryMapAiPage(_service, book, map, () {})));
    await tester.pumpAndSettle();
    expect(find.text('The book has no text yet'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('Select all and Clear change what is ticked; a Section without a title gets a number', (tester) async {
    await provider();
    tester.view.physicalSize = const Size(390 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final book = (await tester.runAsync(() => storyBook([
          StorySection('a', '', ['<p>Артур приехал.</p>']),
          StorySection('b', 'Письмо', ['<p>Эвелин написала.</p>']),
        ])))!;
    final map = (await tester.runAsync(() => book.loadStoryMap()))!;
    await tester.pumpWidget(MaterialApp(home: StoryMapAiPage(_service, book, map, () {})));
    await tester.pumpAndSettle();
    expect(find.text('Section 1'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.textContaining('2 section(s)'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('Nothing selected'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).first); // ticking again unticks
    await tester.pump();
    expect(find.text('Nothing selected'), findsOneWidget);
  });

  testWidgets('only the chosen Sections are sent', (tester) async {
    await provider();
    final sent = <String>[];
    await _open(tester, http: () => _answering(_answer, sent), pick: false);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent.single, contains('## S1: Приезд'));
    expect(sent.single, isNot(contains('## S2')));
  });

  for (final (status, text) in [(429, 'Rate limit reached'), (500, 'unusable answer')]) {
    testWidgets('a $status answer is explained', (tester) async {
      await provider();
      await _open(tester, http: () => MockClient((r) async => http.Response('', status)));
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.textContaining(text), findsOneWidget);
    });
  }

  testWidgets('an unreachable provider is explained', (tester) async {
    await provider();
    await _open(tester, http: () => MockClient((r) async => throw http.ClientException('down')));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('No connection to the provider'), findsOneWidget);
  });

  testWidgets('Cancel while running asks, Keep waiting continues, Stop returns to the choice', (tester) async {
    await provider();
    final gate = Completer<http.Response>();
    await _open(tester, http: () => MockClient((r) => gate.future));
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Reading the book…'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(StoryMapAiPage), matching: find.text('Cancel')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Keep waiting'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Reading the book…'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(StoryMapAiPage), matching: find.text('Cancel')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsOneWidget);
    gate.complete(http.Response('', 401));
    await tester.pumpAndSettle();
    expect(find.text('The provider rejected the API key'), findsNothing); // the stopped run is ignored
  });

  testWidgets('Stop on Back leaves the page', (tester) async {
    await provider();
    final gate = Completer<http.Response>();
    await _open(tester, http: () => MockClient((r) => gate.future));
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryMapAiPage), findsNothing);
    gate.complete(http.Response('', 401));
  });

  testWidgets('a long book shows Request n of m while it runs', (tester) async {
    await provider();
    await _service.providerStore.save(const Provider(
        id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k', chunkChars: 2000));
    final gate = Completer<http.Response>();
    var n = 0;
    await _open(tester, http: () => MockClient((r) => ++n == 1 ? Future.value(http.Response(
        jsonEncode({'choices': [{'message': {'content': _answer}}]}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'})) : gate.future));
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(RegExp(r'Request \d+ of \d+')), findsOneWidget);
    gate.complete(http.Response('', 401));
    await tester.pumpAndSettle();
  });

  testWidgets('editing: Cancel and an empty name change nothing; a tie label can be edited', (tester) async {
    await provider();
    await _open(tester, http: () => _answering(_answer));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('библиотека'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('библиотека'), findsOneWidget); // an empty name is ignored

    await tester.tap(find.text('Артур Рэйм — библиотека')); // tapping the row edits too
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('библиотека'));
    await tester.pumpAndSettle();
    expect(find.text('Edit proposal'), findsOneWidget);
  });

  testWidgets('a proposed piece of lore is labelled as one', (tester) async {
    await provider();
    await _open(tester, http: () => _answering('## entity\nname: библиотека\nkind: lore\nnote: Old.'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lore ·'), findsOneWidget);
  });

  testWidgets('a proposed event is labelled as one', (tester) async {
    await provider();
    await _open(tester, http: () => _answering('## entity\nname: библиотека\nkind: event\nnote: A party.'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Event'), findsWidgets);
  });

  testWidgets('the story map menu opens it', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final book = (await tester.runAsync(() => storyBook()))!;
    await tester.runAsync(() => book.loadStoryMap());
    await tester.pumpWidget(MaterialApp(home: StoryMapPage(_service, book)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Improve with AI'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryMapAiPage), findsOneWidget);
  });
}
