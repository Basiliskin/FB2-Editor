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
    {http.Client Function()? http, Provider? provider = _provider, int? chunk, List<StorySection>? story}) async {
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
