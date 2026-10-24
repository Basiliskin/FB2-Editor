import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// The lowercase hex SHA-256 of the file at [path], computed in a background
/// isolate so hundreds of megabytes never stall the UI.
Future<String> sha256OfFile(String path) => Isolate.run(() => _hash(path));

Future<String> _hash(String path) async {
  final digest = _DigestSink();
  final input = sha256.startChunkedConversion(digest);
  await for (final chunk in File(path).openRead()) {
    input.add(chunk);
  }
  input.close();
  return digest.value.toString();
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
