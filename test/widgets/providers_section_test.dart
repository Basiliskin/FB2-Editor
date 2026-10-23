import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
import 'package:quill_fb2/widgets/forms/providers.section.dart';

const _p = Provider(
    id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k');

void main() {
  group('testConnection', () {
    test('returns null when the provider answers', () async {
      final r = await testConnection(
          _p,
          MockClient((_) async => http.Response(
              '{"choices":[{"message":{"content":"OK"}}]}', 200)));
      expect(r, isNull);
    });

    test('says why it failed', () async {
      expect((await testConnection(_p, MockClient((_) async => http.Response('', 401))))!.failure,
          LlmFailure.invalidKey);
      expect((await testConnection(_p, MockClient((_) async => http.Response('', 404))))!.failure,
          LlmFailure.badResponse);
      expect((await testConnection(_p, MockClient((_) async => throw Exception('x'))))!.failure,
          LlmFailure.network);
    });

    test('gives up when the server never answers', () async {
      final r = await testConnection(
          _p, MockClient((_) => Future.delayed(const Duration(seconds: 5), () => http.Response('', 200))),
          timeout: const Duration(milliseconds: 50));
      expect(r!.failure, LlmFailure.network);
    });
  });

  group('dialog', () {
    late AppService service;

    Future<void> openDialog(WidgetTester tester, http.Response Function() answer) async {
      final Map settings = {};
      service = AppService()
        ..providerStore = ProviderStore(
            getSettings: () => settings,
            setSettings: (m) async => settings.addAll(m),
            session: MemoryKeyVault(),
            persistent: MemoryKeyVault(),
            isWeb: false);
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListView(children: [
        ProvidersSection(service,
            httpFactory: () => MockClient((_) async => answer()))
      ]))));
      await tester.pump();
      await tester.tap(find.text('Add provider'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester) async {
      final f = find.byType(TextField);
      await tester.enterText(f.at(0), 'Work');
      await tester.enterText(f.at(2), 'KEY');
      await tester.pump();
    }

    testWidgets('is disabled until name, model and key are filled', (tester) async {
      await openDialog(tester, () => http.Response('', 200));
      expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
      await fill(tester);
      expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNotNull);
    });

    testWidgets('reports a working connection', (tester) async {
      await openDialog(tester,
          () => http.Response('{"choices":[{"message":{"content":"OK"}}]}', 200));
      await fill(tester);
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('reports a rejected key', (tester) async {
      await openDialog(tester, () => http.Response('', 401));
      await fill(tester);
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(find.text('The API key was rejected'), findsOneWidget);
    });
  });
}
