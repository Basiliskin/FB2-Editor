import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quill_fb2/pages/ask_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/book_ask.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';

import '../support/story_fixtures.dart';

late AppService _service;
late Map _settings;

http.Response _answer(String text) => http.Response(
    jsonEncode({
      'choices': [
        {'message': {'content': text}}
      ]
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _provider = Provider(id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k');

Future<void> _open(WidgetTester tester,
    {http.Client Function()? http,
    Provider? provider = _provider,
    int? chunk,
    List<StorySection>? story,
    String? lang}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (provider != null) {
    await _service.providerStore.save(Provider(
        id: provider.id,
        name: provider.name,
        vendor: provider.vendor,
        model: provider.model,
        apiKey: provider.apiKey,
        chunkChars: chunk ?? defaultChunkChars));
  }
  final book = (await tester.runAsync(() => storyBook(story ?? [
        StorySection('a', 'Приезд', ['<p>Артур приехал в порт на рассвете.</p>']),
        StorySection('b', 'Письмо', ['<p>Эвелин написала письмо Гидеону.</p>']),
      ])))!;
  if (lang != null) book.lang = lang;
  await tester.pumpWidget(MaterialApp(home: AskPage(_service, book, httpFactory: http)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _settings = {};
    _service = AppService()
      ..providerStore = ProviderStore(
          getSettings: () => _settings,
          setSettings: (m) async => _settings.addAll(m),
          session: MemoryKeyVault(),
          persistent: MemoryKeyVault(),
          isWeb: false)
      ..digestStore = DigestStore(getSettings: () => _settings, setSettings: (m) async => _settings.addAll(m));
  });

  testWidgets('without a provider it says what to do and cannot run', (tester) async {
    await _open(tester, provider: null);
    expect(find.textContaining('Connect an AI provider'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('shows the size of a request that fits', (tester) async {
    await _open(tester);
    expect(find.textContaining('1 request. The model reads the text itself.'), findsOneWidget);
  });

  testWidgets('summarises after the user confirms what is sent, and shows the answer', (tester) async {
    final sent = <String>[];
    await _open(tester, http: () => MockClient((r) async {
          sent.add(r.body);
          return _answer('## Answer\nАртур приехал [S1], Эвелин написала [S2, S9].');
        }));
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 section(s)'), findsOneWidget);
    expect(sent, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent.length, 1);
    expect(sent.single, contains('Артур приехал в порт'));
    expect(find.textContaining('Эвелин написала [S2].'), findsOneWidget); // S9 is outside the range
    expect(find.textContaining('S1 = 1. Приезд'), findsOneWidget);
    expect(_settings['llm-consented'], ['p']);
  });

  testWidgets('a question needs text, and quotes are marked found or not found', (tester) async {
    await _open(tester, http: () => MockClient((r) async => _answer(
        '## Answer\nВ порт [S1].\n## Evidence\n- S1: "Артур приехал в порт"\n- S2: "Артур уехал"')));
    await tester.tap(find.text('Ask').first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Куда приехал Артур?');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('S1: «Артур приехал в порт»'), findsOneWidget);
    expect(find.textContaining('Not found in the text: S2'), findsOneWidget);
  });

  testWidgets('a range too long for one request is summarised piece by piece and says so', (tester) async {
    final sent = <String>[];
    var n = 0;
    await _open(tester,
        chunk: 2000,
        story: [
          StorySection('a', 'Приезд', ['<p>${'Артур приехал в порт. ' * 55}</p>']),
          StorySection('b', 'Письмо', ['<p>${'Эвелин писала письмо. ' * 55}</p>']),
        ],
        http: () => MockClient((r) async {
              sent.add(r.body);
              return _answer(++n <= 2 ? 'дайджест $n' : '## Answer\nВсё [S1, S2].');
            }));
    expect(find.textContaining('3 requests'), findsOneWidget);
    expect(find.textContaining('short summaries of each section'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('summaries already made are reused'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent.length, 3);
    expect(sent.last, allOf(contains('дайджест 1'), contains('дайджест 2')));
    expect(find.textContaining('less detailed than the text'), findsOneWidget);

    // asking again reuses the digests: one request instead of three
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 request. Too long'), findsOneWidget);
    expect(find.textContaining('1 request(s)'), findsOneWidget);
  });

  testWidgets('a provider failure is shown and nothing is claimed', (tester) async {
    await _open(tester, http: () => MockClient((r) async => http.Response('', 401)));
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('The provider rejected the API key'), findsOneWidget);
    expect(find.textContaining('S1 ='), findsNothing);
  });

  testWidgets('a cut-off answer says so', (tester) async {
    await _open(tester, http: () => MockClient((r) async => http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': '## Answer\nПол пред'}, 'finish_reason': 'length'}
          ]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The answer was cut off'), findsOneWidget);
  });

  testWidgets('a title that already starts with a number is not numbered twice', (tester) async {
    await _open(tester, story: [
      StorySection('a', '1. ПРЕИСПОДНЯЯ', ['<p>Один.</p>']),
      StorySection('b', 'Письмо', ['<p>Два.</p>']),
    ]);
    expect(find.text('1. ПРЕИСПОДНЯЯ'), findsOneWidget);
    expect(find.text('1. 1. ПРЕИСПОДНЯЯ'), findsNothing);
    expect(find.text('2. Письмо'), findsOneWidget);
  });

  testWidgets('the pickers are full width and do not touch the question field', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Ask').first);
    await tester.pumpAndSettle();
    final from = tester.getRect(find.widgetWithText(DropdownButtonFormField<int>, 'From'));
    final to = tester.getRect(find.widgetWithText(DropdownButtonFormField<int>, 'To'));
    final question = tester.getRect(find.byType(TextField));
    expect(from.width, greaterThan(300));
    expect(to.top - from.bottom, greaterThanOrEqualTo(8));
    expect(question.top - to.bottom, greaterThanOrEqualTo(8));
  });

  testWidgets('the model is told to write in the language of the book, not of the app', (tester) async {
    final sent = <String>[];
    await _open(tester, lang: 'ru', http: () => MockClient((r) async {
          sent.add(r.body);
          return _answer('## Answer\nok');
        }));
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent.single, contains('Russian'));
    expect(sent.single, isNot(contains('English')));
  });

  testWidgets('one Section cut into several requests asks first, and progress keeps its total', (tester) async {
    final gate = Completer<http.Response>();
    var n = 0;
    await _open(tester,
        chunk: 2000,
        story: [
          StorySection('a', 'Приезд', ['<p>${'Артур приехал в порт. ' * 120}</p>']),
        ],
        http: () => MockClient((r) => ++n < 3 ? Future.value(_answer('дайджест $n')) : gate.future));
    expect(find.textContaining('requests'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('request(s)'), findsOneWidget); // the dialog shows although it is one Section
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final shown = find.textContaining(RegExp(r'Request \d+ of \d+'));
    final total = RegExp(r'of (\d+)').firstMatch((tester.widget<Text>(shown).data)!)!.group(1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(RegExp(r'of (\d+)').firstMatch((tester.widget<Text>(shown).data)!)!.group(1), total);
    gate.complete(_answer('## Answer\nготово'));
    await tester.pumpAndSettle();
  });

  testWidgets('leaving while it runs asks first; Keep waiting stays, Stop leaves', (tester) async {
    final gate = Completer<http.Response>();
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _service.providerStore.save(_provider);
    final book = (await tester.runAsync(() => storyBook()))!;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(builder: (_) => AskPage(_service, book, httpFactory: () => MockClient((r) => gate.future))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stop the running request?'), findsOneWidget);
    await tester.tap(find.text('Keep waiting'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AskPage), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.byType(AskPage), findsNothing);
    gate.complete(_answer('late'));
  });

  for (final (status, text) in [(429, 'Rate limit reached'), (500, 'unusable answer')]) {
    testWidgets('a $status answer is explained', (tester) async {
      await _open(tester, http: () => MockClient((r) async => http.Response('', status)));
      await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.textContaining(text), findsOneWidget);
    });
  }

  testWidgets('an unreachable provider is explained', (tester) async {
    await _open(tester, http: () => MockClient((r) async => throw http.ClientException('down')));
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('No connection to the provider'), findsOneWidget);
  });

  testWidgets('moving From past To drags To along, and To before From drags From back', (tester) async {
    await _open(tester, story: [
      StorySection('a', 'Раз', ['<p>Один.</p>']),
      StorySection('b', 'Два', ['<p>Два.</p>']),
      StorySection('c', 'Три', ['<p>Три.</p>']),
    ]);
    Future<void> pick(String label, String item) async {
      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    await pick('To', '2. Два');
    await pick('From', '2. Два');
    await pick('To', '2. Два');
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 section(s)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await pick('From', '3. Три'); // From beyond To moves To up with it
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 section(s)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await pick('To', '1. Раз'); // To before From moves From down with it
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 section(s)'), findsOneWidget);
  });

  testWidgets('an answer with no text says the model gave none', (tester) async {
    await _open(tester, http: () => MockClient((r) async => _answer('## Answer\n')));
    await tester.tap(find.widgetWithText(FilledButton, 'Summarise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('The model gave no answer.'), findsOneWidget);
  });

  test('languageName knows codes, regions and unknown codes; bookLanguageOf falls back to the app language',
      () async {
    expect(languageName('ru'), 'Russian');
    expect(languageName('ru-RU'), 'Russian');
    expect(languageName('UK'), 'Ukrainian');
    expect(languageName('xx'), 'xx');
    expect(languageName(''), 'English');
    final book = await storyBook();
    book.lang = '';
    expect(bookLanguageOf(_service, book), 'en');
    _service.workspace['workspaceSettings'] = {'language': 'ru'};
    expect(bookLanguageOf(_service, book), 'ru');
    book.lang = 'de';
    expect(bookLanguageOf(_service, book), 'de');
  });

  test('askSectionsOf numbers Sections by their place and reads their plain text', () async {
    final book = await storyBook([
      StorySection('a', 'One', ['<p>Hello <strong>there</strong>.</p>']),
      StorySection('b', 'Two', ['<p>Bye.</p>']),
    ]);
    final s = askSectionsOf(book);
    expect([for (final x in s) x.number], [1, 2]);
    expect(s.first.paragraphs, ['Hello there.']);
    expect(s.last.title, 'Two');
  });
}
