import 'dart:async';
import 'dart:io';

import 'install_failure.dart';

/// A response body that holds the file's bytes from [offset] onwards.
final class FetchedBody {
  const FetchedBody({required this.offset, required this.bytes});

  /// 0 when the server sent the whole file, otherwise the requested offset.
  final int offset;

  /// Fails with [NetworkFailure]. Cancelling the subscription aborts the
  /// transfer.
  final Stream<List<int>> bytes;
}

/// Fetches a file over HTTPS only. Every redirect hop is followed here, so a
/// hop to any other scheme is refused instead of followed.
class HttpsFileFetcher {
  HttpsFileFetcher({HttpClient? client}) : _client = client ?? HttpClient();

  static const maxRedirects = 5;

  final HttpClient _client;

  /// Requests [url] from byte [from] onwards. Pass the original URL on every
  /// attempt: the signed address it redirects to expires.
  Future<FetchedBody> fetch(Uri url, {int from = 0}) async {
    try {
      var target = url;
      for (var hop = 0; hop <= maxRedirects; hop++) {
        if (target.scheme != 'https') throw const NetworkFailure();
        final request = await _client.getUrl(target);
        request.followRedirects = false;
        if (from > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
        }
        final response = await request.close();

        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) throw const NetworkFailure();
          target = target.resolve(location);
          continue;
        }
        return await _body(response, from);
      }
      throw const NetworkFailure();
    } on IOException {
      throw const NetworkFailure();
    }
  }

  Future<FetchedBody> _body(HttpClientResponse response, int from) async {
    final status = response.statusCode;
    final resumed =
        from > 0 &&
        status == HttpStatus.partialContent &&
        _contentRangeStartsAt(response, from);
    if (status != HttpStatus.ok && !resumed) {
      await response.drain<void>().catchError((Object _) {});
      throw const NetworkFailure();
    }
    return FetchedBody(
      offset: resumed ? from : 0,
      bytes: response.handleError(
        (Object _) => throw const NetworkFailure(),
        test: (error) => error is IOException,
      ),
    );
  }

  bool _contentRangeStartsAt(HttpClientResponse response, int from) =>
      response.headers
          .value(HttpHeaders.contentRangeHeader)
          ?.startsWith('bytes $from-') ??
      false;
}
