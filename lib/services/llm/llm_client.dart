import 'package:http/http.dart' as http;
import 'package:quill_fb2/services/llm/json_util.dart';

enum LlmVendor { gemini, openai, anthropic }

/// A user-defined connection to an LLM service.
class Provider {
  final String id;
  final String name;
  final LlmVendor vendor;
  final String model;
  final String apiKey;

  /// Overrides the vendor's default endpoint (Ollama, OpenRouter, ...).
  final String? baseUrl;

  const Provider({
    required this.id,
    required this.name,
    required this.vendor,
    required this.model,
    required this.apiKey,
    this.baseUrl,
  });
}

class LlmRequest {
  final String system;
  final String user;
  const LlmRequest({required this.system, required this.user});
}

enum LlmFailure { invalidKey, rateLimited, network, badResponse }

class LlmException implements Exception {
  final LlmFailure failure;
  final String message;
  const LlmException(this.failure, this.message);
  @override
  String toString() => 'LlmException(${failure.name}): $message';
}

abstract class LlmClient {
  Future<String> complete(LlmRequest request);
}

/// Shared HTTP plumbing: maps transport and status errors to [LlmException].
abstract class HttpLlmClient implements LlmClient {
  final Provider provider;
  final http.Client httpClient;
  HttpLlmClient(this.provider, this.httpClient);

  Uri endpoint();
  Map<String, String> headers();
  Map<String, dynamic> body(LlmRequest request);
  String? extractText(Map<String, dynamic> json);

  @override
  Future<String> complete(LlmRequest request) async {
    final http.Response res;
    try {
      res = await httpClient.post(endpoint(),
          headers: {'content-type': 'application/json', ...headers()},
          body: encodeJson(body(request)));
    } catch (e) {
      throw LlmException(LlmFailure.network, '$e');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw LlmException(LlmFailure.invalidKey, 'HTTP ${res.statusCode}');
    }
    if (res.statusCode == 429) {
      throw const LlmException(LlmFailure.rateLimited, 'HTTP 429');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw LlmException(LlmFailure.badResponse, 'HTTP ${res.statusCode}');
    }
    try {
      final text = extractText(decodeJson(res.body));
      if (text != null && text.isNotEmpty) return text;
    } catch (_) {}
    throw const LlmException(LlmFailure.badResponse, 'no text in response');
  }
}
