import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quill_fb2/pages/names_check_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
import 'package:quill_fb2/services/name_check.dart';
import 'package:quill_fb2/services/name_check_ai.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';

import '../support/story_fixtures.dart';

List<String> _mentions(String name, int n) => [for (var i = 0; i < n; i++) '<p>Потом $name пришёл домой $i.</p>'];

late AppService _service;
late Map _settings;

Future<void> _open(WidgetTester tester, {http.Client Function()? http}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final book = (await tester.runAsync(() => storyBook([
        StorySection('a', 'Приезд', [..._mentions('Иван', 4), ..._mentions('Ivan', 2)]),
        StorySection('b', 'Письмо', [..._mentions('Артур', 12), ..._mentions('Артор', 1)]),
      ])))!;
  await tester.pumpWidget(MaterialApp(
      home: NamesCheckPage(_service, book, checker: (s) async => checkNames(s), httpFactory: http)));
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
      ..nameCheckStore = NameCheckStore(getSettings: () => _settings, setSettings: (m) async => _settings.addAll(m));
  });

  testWidgets('lists the names written two ways, with where they stand', (tester) async {
    await _open(tester);
    expect(find.text('Иван  ·  Ivan'), findsOneWidget);
    expect(find.text('Same name, two scripts'), findsOneWidget);
    expect(find.text('Артур  ·  Артор'), findsOneWidget);
    expect(find.text('Possibly the same name'), findsOneWidget);
    expect(find.textContaining('Приезд · ¶1'), findsWidgets);
    expect(find.text('Ask AI (1)'), findsOneWidget); // only the unclear pair is worth asking about
  });

  testWidgets('dismissing a finding removes it and keeps it removed', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Dismiss').first);
    await tester.pumpAndSettle();
    expect(find.text('Иван  ·  Ivan'), findsNothing);
    await _open(tester);
    expect(find.text('Иван  ·  Ivan'), findsNothing);
    expect(find.text('Артур  ·  Артор'), findsOneWidget);
  });

  testWidgets('asks the AI only after the user agrees to what is sent', (tester) async {
    await _service.providerStore
        .save(const Provider(id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));
    final sent = <String>[];
    await _open(tester, http: () => MockClient((r) async {
          sent.add(r.body);
          return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '## 1\nverdict: same\ncanonical: Артур\nreason: A slip of the pen.'}
                  }
                ]
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    await tester.tap(find.text('Ask AI (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 request(s)'), findsOneWidget);
    expect(sent, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);

    await tester.tap(find.text('Ask AI (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(sent.length, 1);
    expect(sent.single, contains('## 1'));
    expect(sent.single, isNot(contains('Иван'))); // the certain finding is not sent
    expect(find.text('AI: same name'), findsOneWidget);
    expect(find.text('A slip of the pen.'), findsOneWidget);
    expect(find.text('Suggested spelling: Артур'), findsOneWidget);
    expect(find.textContaining('Ask AI'), findsNothing);
  });

  testWidgets('a pair the AI calls different is hidden, and says so', (tester) async {
    await _service.providerStore
        .save(const Provider(id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));
    await _open(
        tester,
        http: () => MockClient((r) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '## 1\nverdict: different\nreason: Two people.'}
                }
              ]
            }),
            200)));
    await tester.tap(find.text('Ask AI (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Артур  ·  Артор'), findsNothing);
    expect(find.textContaining('1 pair(s) hidden'), findsOneWidget);
  });

  testWidgets('without a provider it says what to do and sends nothing', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Ask AI (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connect an AI provider'), findsOneWidget);
  });

  testWidgets('a provider failure is shown and the findings stay', (tester) async {
    await _service.providerStore
        .save(const Provider(id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));
    await _open(tester, http: () => MockClient((r) async => http.Response('', 401)));
    await tester.tap(find.text('Ask AI (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('The provider rejected the API key'), findsOneWidget);
    expect(find.text('Артур  ·  Артор'), findsOneWidget);
  });
}
