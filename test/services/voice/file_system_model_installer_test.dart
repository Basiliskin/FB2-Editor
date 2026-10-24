import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/https_file_fetcher.dart';
import 'package:quill_fb2/services/voice/file_system_model_installer.dart';
import 'package:quill_fb2/services/voice/sha256_file.dart';
import 'package:quill_fb2/services/voice/install_failure.dart';

const _tlsDir = 'test/services/voice/test_tls';

List<int> _bytes(int length, int seed) =>
    List.generate(length, (i) => (i * 31 + seed) & 0xff);

final _served = {
  'encoder.onnx': _bytes(200000, 1),
  'decoder.onnx': _bytes(50000, 2),
  'tokens.txt': _bytes(1000, 3),
};

typedef _Request = ({String path, String? range});

/// Serves [_served] over TLS: `/resolve/<name>` redirects to `/cdn/<name>`,
/// which honours `Range: bytes=<n>-`.
class _ModelServer {
  late final HttpServer _server;
  final requests = <_Request>[];

  bool ignoreRange = false;
  final statusFor = <String, int>{};
  final redirectFor = <String, String>{};

  /// One-shot: sends this many bytes of the named file, then drops the
  /// connection.
  ({String name, int bytes})? cut;

  /// One-shot: sends this many bytes of the named file, then holds the
  /// connection open until [releaseStall].
  ({String name, int bytes})? stall;
  final _stallRelease = Completer<void>();

  int get port => _server.port;

  Uri resolveUrl(String name) =>
      Uri.parse('https://127.0.0.1:$port/resolve/$name');

  Iterable<_Request> requestsFor(String path) =>
      requests.where((request) => request.path == path);

  Future<void> start() async {
    final context = SecurityContext()
      ..useCertificateChain('$_tlsDir/server_cert.pem')
      ..usePrivateKey('$_tlsDir/server_key.pem');
    _server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    _server.listen(_handle);
  }

  void releaseStall() {
    if (!_stallRelease.isCompleted) _stallRelease.complete();
  }

  Future<void> close() async {
    releaseStall();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    requests.add((path: path, range: range));
    final response = request.response;

    if (path == '/loop') {
      await _redirect(response, '/loop');
      return;
    }
    final name = path.split('/').last;
    if (path.startsWith('/resolve/')) {
      await _redirect(
        response,
        redirectFor[name] ?? 'https://127.0.0.1:$port/cdn/$name',
      );
      return;
    }

    final status = statusFor[name];
    final bytes = _served[name];
    if (status != null || bytes == null) {
      response.statusCode = status ?? HttpStatus.notFound;
      await response.close();
      return;
    }

    var from = 0;
    if (range != null && !ignoreRange) {
      from = int.parse(range.substring('bytes='.length, range.length - 1));
    }
    final body = bytes.sublist(from);

    final cutNow = cut;
    if (cutNow != null && cutNow.name == name) {
      cut = null;
      final socket = await response.detachSocket(writeHeaders: false);
      socket.add(
        'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\n\r\n'.codeUnits,
      );
      socket.add(body.sublist(0, cutNow.bytes));
      await socket.flush();
      socket.destroy();
      return;
    }

    if (from > 0) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $from-${bytes.length - 1}/${bytes.length}',
      );
    }
    response.contentLength = body.length;

    final stallNow = stall;
    if (stallNow != null && stallNow.name == name) {
      stall = null;
      response.add(body.sublist(0, stallNow.bytes));
      await response.flush();
      await _stallRelease.future;
      return;
    }

    response.add(body);
    await response.close();
  }

  Future<void> _redirect(HttpResponse response, String location) async {
    response.statusCode = HttpStatus.found;
    response.headers.set(HttpHeaders.locationHeader, location);
    await response.close();
  }
}

Future<Object?> _failureOf(Stream<int> download) async {
  try {
    await download.drain<void>();
    return null;
  } catch (error) {
    return error;
  }
}

void main() {
  late Directory root;
  late Directory modelDirectory;
  late Directory staging;
  late _ModelServer server;
  late List<PinnedModelFile> files;

  HttpClient trustingTestCertificate() => HttpClient(
    context: SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('$_tlsDir/server_cert.pem'),
  );

  List<PinnedModelFile> pinned(Map<String, String> sha256Overrides) => [
    for (final MapEntry(key: name, value: bytes) in _served.entries)
      (
        name: name,
        sizeInBytes: bytes.length,
        sha256: sha256Overrides[name] ?? sha256.convert(bytes).toString(),
        url: server.resolveUrl(name),
      ),
  ];

  FileSystemModelInstaller installer({List<PinnedModelFile>? override}) =>
      FileSystemModelInstaller(
        modelDirectory: modelDirectory,
        fetcher: HttpsFileFetcher(client: trustingTestCertificate()),
        files: override ?? files,
      );

  File part(String name) => File('${staging.path}/$name.part');
  File installed(String name) => File('${modelDirectory.path}/$name');

  List<String> modelDirectoryContents() => modelDirectory.existsSync()
      ? modelDirectory.listSync().map((entry) => entry.path).toList()
      : const [];

  void expectFullyInstalled() {
    for (final MapEntry(key: name, value: bytes) in _served.entries) {
      expect(installed(name).readAsBytesSync(), bytes, reason: name);
    }
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('model_installer_test');
    modelDirectory = Directory('${root.path}/models/whisper-small');
    staging = Directory('${root.path}/models/whisper-small.staging');
    server = _ModelServer();
    await server.start();
    files = pinned(const {});
  });

  tearDown(() async {
    await server.close();
    root.deleteSync(recursive: true);
  });

  test('the test certificate has not expired yet', () async {
    final request = await trustingTestCertificate().getUrl(
      server.resolveUrl('tokens.txt'),
    );
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();

    final expires = response.certificate!.endValidity;
    expect(
      expires.isAfter(DateTime.now().add(const Duration(days: 60))),
      isTrue,
      reason: 'run $_tlsDir/regenerate.sh; it expires on $expires',
    );
  });

  group('isInstalled', () {
    test('is false when the model directory does not exist', () async {
      expect(await installer().isInstalled(), isFalse);
    });

    test('is false when a file has the wrong size', () async {
      modelDirectory.createSync(recursive: true);
      for (final MapEntry(key: name, value: bytes) in _served.entries) {
        installed(name).writeAsBytesSync(bytes);
      }
      installed('decoder.onnx').writeAsBytesSync(_bytes(49999, 2));

      expect(await installer().isInstalled(), isFalse);
    });

    test('is true for three exact-size files, without any request', () async {
      modelDirectory.createSync(recursive: true);
      for (final MapEntry(key: name, value: bytes) in _served.entries) {
        installed(name).writeAsBytesSync(List.filled(bytes.length, 0));
      }

      expect(await installer().isInstalled(), isTrue);
      expect(server.requests, isEmpty);
    });
  });

  group('download', () {
    test('fetches every file over HTTPS and installs them', () async {
      final progress = await installer().download().toList();

      expectFullyInstalled();
      expect(staging.existsSync(), isFalse);
      expect(await installer().isInstalled(), isTrue);
      expect(progress.last, 251000);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      expect(server.requestsFor('/resolve/encoder.onnx').single.range, isNull);
    });

    test('never starts over a good installed model', () async {
      await installer().download().drain<void>();
      server.requests.clear();

      expect(await installer().download().toList(), isEmpty);
      expect(server.requests, isEmpty);
    });

    test('resumes a cut file with an HTTP Range request', () async {
      server.cut = (name: 'encoder.onnx', bytes: 120000);

      expect(await _failureOf(installer().download()), isA<NetworkFailure>());
      expect(part('encoder.onnx').lengthSync(), 120000);
      expect(modelDirectoryContents(), isEmpty);

      await installer().download().drain<void>();

      expectFullyInstalled();
      final encoderRequests = server.requestsFor('/cdn/encoder.onnx').toList();
      expect(encoderRequests.last.range, 'bytes=120000-');
      expect(server.requestsFor('/resolve/encoder.onnx'), hasLength(2));
      expect(
        server.requestsFor('/resolve/encoder.onnx').last.range,
        'bytes=120000-',
      );
    });

    test('starts the file over when the server ignores Range', () async {
      staging.createSync(recursive: true);
      part('encoder.onnx')
          .writeAsBytesSync(_served['encoder.onnx']!.sublist(0, 100000));
      server.ignoreRange = true;

      await installer().download().drain<void>();

      expectFullyInstalled();
      expect(
        server.requestsFor('/cdn/encoder.onnx').single.range,
        'bytes=100000-',
      );
    });

    test('skips the fetch for a .part that is already full length', () async {
      staging.createSync(recursive: true);
      part('encoder.onnx').writeAsBytesSync(_served['encoder.onnx']!);

      await installer().download().drain<void>();

      expectFullyInstalled();
      expect(server.requestsFor('/resolve/encoder.onnx'), isEmpty);
      expect(server.requestsFor('/cdn/encoder.onnx'), isEmpty);
    });

    test('keeps the .part on cancel and resumes from it', () async {
      server.stall = (name: 'encoder.onnx', bytes: 64000);
      final firstChunk = Completer<void>();
      final subscription = installer().download().listen((_) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      });
      await firstChunk.future;
      await subscription.cancel();
      server.releaseStall();

      final kept = part('encoder.onnx').lengthSync();
      expect(kept, greaterThan(0));
      expect(kept, lessThanOrEqualTo(64000));
      expect(modelDirectoryContents(), isEmpty);

      await installer().download().drain<void>();

      expectFullyInstalled();
      expect(
        server.requestsFor('/cdn/encoder.onnx').last.range,
        'bytes=$kept-',
      );
    });

    test('rejects a fingerprint mismatch and never installs it', () async {
      final damaged = pinned({'decoder.onnx': '0' * 64});

      expect(
        await _failureOf(installer(override: damaged).download()),
        isA<FingerprintMismatch>(),
      );
      expect(part('decoder.onnx').existsSync(), isFalse);
      expect(modelDirectoryContents(), isEmpty);
    });

    test('installs nothing when only two of three files arrived', () async {
      server.statusFor['tokens.txt'] = HttpStatus.notFound;

      expect(await _failureOf(installer().download()), isA<NetworkFailure>());
      expect(part('encoder.onnx').lengthSync(), 200000);
      expect(part('decoder.onnx').lengthSync(), 50000);
      expect(modelDirectoryContents(), isEmpty);
    });

    test('maps a server error to the network failure', () async {
      server.statusFor['encoder.onnx'] = HttpStatus.internalServerError;

      expect(await _failureOf(installer().download()), isA<NetworkFailure>());
    });

    test('maps a write failure to the storage failure', () async {
      modelDirectory.parent.createSync(recursive: true);
      File(staging.path).writeAsStringSync('not a directory');

      expect(await _failureOf(installer().download()), isA<StorageFailure>());
      expect(modelDirectoryContents(), isEmpty);
    });

    test('refuses a redirect to a non-HTTPS address', () async {
      final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var plainRequests = 0;
      plain.listen((request) {
        plainRequests++;
        request.response.close();
      });
      addTearDown(() => plain.close(force: true));
      server.redirectFor['encoder.onnx'] =
          'http://127.0.0.1:${plain.port}/cdn/encoder.onnx';

      expect(await _failureOf(installer().download()), isA<NetworkFailure>());
      expect(plainRequests, 0);
      expect(modelDirectoryContents(), isEmpty);
    });

    test('stops following redirects at a fixed cap', () async {
      final looping = [
        (
          name: 'encoder.onnx',
          sizeInBytes: 200000,
          sha256: files.first.sha256,
          url: Uri.parse('https://127.0.0.1:${server.port}/loop'),
        ),
      ];

      expect(
        await _failureOf(installer(override: looping).download()),
        isA<NetworkFailure>(),
      );
      expect(
        server.requestsFor('/loop'),
        hasLength(HttpsFileFetcher.maxRedirects + 1),
      );
    });
  });

  group('sha256OfFile', () {
    test('matches the known digest of "abc"', () async {
      final file = File('${root.path}/abc.txt')..writeAsStringSync('abc');

      expect(
        await sha256OfFile(file.path),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('matches a one-shot digest across many chunks', () async {
      final bytes = _bytes(300000, 7);
      final file = File('${root.path}/big.bin')..writeAsBytesSync(bytes);

      expect(await sha256OfFile(file.path), sha256.convert(bytes).toString());
    });
  });
}
