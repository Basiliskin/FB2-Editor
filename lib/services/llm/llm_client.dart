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

  /// Most characters of paragraph text sent in one request.
  final int chunkChars;

  const Provider({
    required this.id,
    required this.name,
    required this.vendor,
    required this.model,
    required this.apiKey,
    this.baseUrl,
    this.chunkChars = defaultChunkChars,
  });
}

/// Default [Provider.chunkChars]; the form accepts [minChunkChars]..[maxChunkChars].
const defaultChunkChars = 24000;
const minChunkChars = 2000;
const maxChunkChars = 200000;

/// Most tokens we ask a model to write back; older models accept no more.
const maxOutputTokensCap = 16384;

class LlmRequest {
  final String system;
  final String user;

  /// Room the answer may take. Rewriting returns about as much text as it got.
  final int maxOutputTokens;
  const LlmRequest(
      {required this.system, required this.user, this.maxOutputTokens = 1024});

  /// A request whose answer budget follows the size of [user] (about two
  /// characters per token, which holds for Cyrillic) plus a margin.
  factory LlmRequest.sized(
      {required String system, required String user, int inputChars = 0}) {
    final tokens = (inputChars / 2).ceil() + 1024;
    return LlmRequest(
        system: system,
        user: user,
        maxOutputTokens: tokens > maxOutputTokensCap ? maxOutputTokensCap : tokens);
  }
}

/// A model's answer, and whether it stopped because it ran out of room.
class LlmResponse {
  final String text;
  final bool truncated;
  const LlmResponse(this.text, {this.truncated = false});
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
  Future<LlmResponse> complete(LlmRequest request);
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

  /// Whether the answer in [json] was cut off at the output limit.
  bool wasTruncated(Map<String, dynamic> json);

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
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
      final json = decodeJson(res.body);
      final text = extractText(json);
      if (text != null && text.isNotEmpty) {
        return LlmResponse(text, truncated: wasTruncated(json));
      }
    } catch (_) {}
    throw const LlmException(LlmFailure.badResponse, 'no text in response');
  }
}
