import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:quill_fb2/services/llm/llm_client.dart';

String _base(Provider p, String fallback) {
  final b = (p.baseUrl ?? '').trim();
  return (b.isEmpty ? fallback : b).replaceAll(RegExp(r'/+$'), '');
}

/// OpenAI chat completions; also serves OpenAI-compatible servers.
class OpenAiClient extends HttpLlmClient {
  OpenAiClient(super.provider, super.httpClient);

  @override
  Uri endpoint() => Uri.parse(
      '${_base(provider, 'https://api.openai.com/v1')}/chat/completions');

  @override
  Map<String, String> headers() =>
      {'authorization': 'Bearer ${provider.apiKey}'};

  @override
  Map<String, dynamic> body(LlmRequest r) => {
        'model': provider.model,
        'messages': [
          {'role': 'system', 'content': r.system},
          {'role': 'user', 'content': r.user},
        ],
      };

  @override
  String? extractText(Map<String, dynamic> json) =>
      json['choices'][0]['message']['content'] as String?;
}

class AnthropicClient extends HttpLlmClient {
  AnthropicClient(super.provider, super.httpClient);

  @override
  Uri endpoint() =>
      Uri.parse('${_base(provider, 'https://api.anthropic.com/v1')}/messages');

  @override
  Map<String, String> headers() => {
        'x-api-key': provider.apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      };

  @override
  Map<String, dynamic> body(LlmRequest r) => {
        'model': provider.model,
        'max_tokens': 4096,
        'system': r.system,
        'messages': [
          {'role': 'user', 'content': r.user},
        ],
      };

  @override
  String? extractText(Map<String, dynamic> json) => (json['content'] as List)
      .where((b) => b['type'] == 'text')
      .map((b) => b['text'] as String)
      .join();
}

class GeminiClient extends HttpLlmClient {
  GeminiClient(super.provider, super.httpClient);

  @override
  Uri endpoint() => Uri.parse(
      '${_base(provider, 'https://generativelanguage.googleapis.com/v1beta')}'
      '/models/${provider.model}:generateContent');

  @override
  Map<String, String> headers() => {'x-goog-api-key': provider.apiKey};

  @override
  Map<String, dynamic> body(LlmRequest r) => {
        'systemInstruction': {
          'parts': [
            {'text': r.system}
          ]
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': r.user}
            ]
          }
        ],
      };

  @override
  String? extractText(Map<String, dynamic> json) =>
      (json['candidates'][0]['content']['parts'] as List)
          .map((p) => p['text'] as String)
          .join();
}

/// Sends a one-word request to see whether [provider] is usable. Returns null
/// when it answered, otherwise why it did not.
Future<LlmException?> testConnection(Provider provider, http.Client client,
    {Duration timeout = const Duration(seconds: 20)}) async {
  try {
    await createLlmClient(provider, client)
        .complete(const LlmRequest(
            system: 'Answer with the single word OK.', user: 'Say OK.'))
        .timeout(timeout);
    return null;
  } on LlmException catch (e) {
    return e;
  } on TimeoutException {
    return const LlmException(LlmFailure.network, 'timed out');
  } finally {
    client.close();
  }
}

LlmClient createLlmClient(Provider provider, http.Client httpClient) {
  switch (provider.vendor) {
    case LlmVendor.openai:
      return OpenAiClient(provider, httpClient);
    case LlmVendor.anthropic:
      return AnthropicClient(provider, httpClient);
    case LlmVendor.gemini:
      return GeminiClient(provider, httpClient);
  }
}
