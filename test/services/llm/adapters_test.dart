import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';

Provider _p(LlmVendor v, {String? baseUrl}) => Provider(
    id: '1', name: 'p', vendor: v, model: 'm', apiKey: 'KEY', baseUrl: baseUrl);

const _req = LlmRequest(system: 'sys', user: 'usr');

void main() {
  test('OpenAI maps request and response', () async {
    late http.Request seen;
    final client = createLlmClient(_p(LlmVendor.openai), MockClient((r) async {
      seen = r;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'hello'}
              }
            ]
          }),
          200);
    }));
    expect(await client.complete(_req), 'hello');
    expect(seen.url.toString(), 'https://api.openai.com/v1/chat/completions');
    expect(seen.headers['authorization'], 'Bearer KEY');
    final b = jsonDecode(seen.body);
    expect(b['model'], 'm');
    expect(b['messages'][1]['content'], 'usr');
  });

  test('custom base URL replaces the vendor endpoint', () async {
    late Uri url;
    final client = createLlmClient(
        _p(LlmVendor.openai, baseUrl: 'http://localhost:11434/v1/'),
        MockClient((r) async {
      url = r.url;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'x'}
              }
            ]
          }),
          200);
    }));
    await client.complete(_req);
    expect(url.toString(), 'http://localhost:11434/v1/chat/completions');
  });

  test('Anthropic maps request and response', () async {
    late http.Request seen;
    final client =
        createLlmClient(_p(LlmVendor.anthropic), MockClient((r) async {
      seen = r;
      return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'a'},
              {'type': 'text', 'text': 'b'}
            ]
          }),
          200);
    }));
    expect(await client.complete(_req), 'ab');
    expect(seen.headers['x-api-key'], 'KEY');
    expect(seen.headers['anthropic-version'], isNotEmpty);
    expect(jsonDecode(seen.body)['system'], 'sys');
  });

  test('Gemini maps request and response', () async {
    late http.Request seen;
    final client = createLlmClient(_p(LlmVendor.gemini), MockClient((r) async {
      seen = r;
      return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'g'}
                  ]
                }
              }
            ]
          }),
          200);
    }));
    expect(await client.complete(_req), 'g');
    expect(seen.url.path, endsWith('/models/m:generateContent'));
    expect(seen.headers['x-goog-api-key'], 'KEY');
    expect(
        jsonDecode(seen.body)['systemInstruction']['parts'][0]['text'], 'sys');
  });

  Future<LlmFailure> failure(http.Client c) async {
    try {
      await createLlmClient(_p(LlmVendor.openai), c).complete(_req);
    } on LlmException catch (e) {
      return e.failure;
    }
    fail('expected LlmException');
  }

  test('errors are classified', () async {
    expect(await failure(MockClient((_) async => http.Response('', 401))),
        LlmFailure.invalidKey);
    expect(await failure(MockClient((_) async => http.Response('', 429))),
        LlmFailure.rateLimited);
    expect(await failure(MockClient((_) async => http.Response('', 500))),
        LlmFailure.badResponse);
    expect(await failure(MockClient((_) async => http.Response('{}', 200))),
        LlmFailure.badResponse);
    expect(await failure(MockClient((_) async => throw Exception('down'))),
        LlmFailure.network);
  });
}
