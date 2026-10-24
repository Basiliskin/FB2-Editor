import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

sealed class DecoderRequest {
  const DecoderRequest();
}

final class InitDecoder extends DecoderRequest {
  const InitDecoder({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.languageCode,
    required this.numThreads,
  });

  final String encoder;
  final String decoder;
  final String tokens;
  final String languageCode;
  final int numThreads;

  @override
  bool operator ==(Object other) =>
      other is InitDecoder &&
      other.encoder == encoder &&
      other.decoder == decoder &&
      other.tokens == tokens &&
      other.languageCode == languageCode &&
      other.numThreads == numThreads;

  @override
  int get hashCode =>
      Object.hash(encoder, decoder, tokens, languageCode, numThreads);
}

final class DecodeSamples extends DecoderRequest {
  DecodeSamples(Float32List samples)
    : samples = TransferableTypedData.fromList([samples]);

  /// Can be materialized exactly once, by the receiving isolate.
  final TransferableTypedData samples;

  Float32List materialize() => samples.materialize().asFloat32List();
}

final class DisposeDecoder extends DecoderRequest {
  const DisposeDecoder();
}

sealed class DecoderReply {
  const DecoderReply();
}

final class DecoderReady extends DecoderReply {
  const DecoderReady();
}

final class DecodedText extends DecoderReply {
  const DecodedText(this.text, {this.lang = ''});

  final String text;

  /// The language Whisper reported for the decode; empty when it reported none.
  final String lang;

  @override
  bool operator ==(Object other) =>
      other is DecodedText && other.text == text && other.lang == lang;

  @override
  int get hashCode => Object.hash(text, lang);
}

final class DecoderDisposed extends DecoderReply {
  const DecoderDisposed();
}

enum DecoderFailureKind { modelMissing, engine }

/// Carries a fixed description and the error's type only: sherpa-onnx error
/// messages can contain model paths and partial transcripts.
final class DecoderFailure extends DecoderReply implements Exception {
  const DecoderFailure(this.kind, this.message);

  DecoderFailure.fromError(this.kind, String context, Object error)
    : message = '$context (${error.runtimeType})';

  final DecoderFailureKind kind;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is DecoderFailure && other.kind == kind && other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'DecoderFailure(${kind.name}): $message';
}

/// The part of the decoder the engine needs, so tests can swap in a fake.
abstract interface class WhisperDecoder {
  Future<void> init(InitDecoder request);

  Future<DecodedText> decode(Float32List samples);

  Future<void> dispose();
}

/// A long-lived worker isolate that owns the native Whisper recognizer, so the
/// blocking decode never runs on the UI isolate.
class WhisperDecoderIsolate implements WhisperDecoder {
  WhisperDecoderIsolate._(this._isolate, this._replies) {
    _replies.listen(_onReply);
  }

  static const disposeTimeout = Duration(seconds: 5);

  static Future<WhisperDecoderIsolate> spawn() async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(
      _decoderMain,
      replies.sendPort,
      onExit: replies.sendPort,
      debugName: 'whisper-decoder',
    );
    final decoder = WhisperDecoderIsolate._(isolate, replies);
    await decoder._started.future;
    return decoder;
  }

  final Isolate _isolate;
  final ReceivePort _replies;
  final _started = Completer<void>();
  late final SendPort _requests;
  final _pending = Queue<Completer<DecoderReply>>();
  bool _exited = false;

  @override
  Future<void> init(InitDecoder request) async {
    await _send(request);
  }

  @override
  Future<DecodedText> decode(Float32List samples) async {
    final reply = await _send(DecodeSamples(samples));
    return reply as DecodedText;
  }

  @override
  Future<void> dispose() async {
    if (_exited) return;
    try {
      await _send(const DisposeDecoder()).timeout(disposeTimeout);
    } on Object {
      // The worker is killed below either way.
    }
    _isolate.kill(priority: Isolate.immediate);
  }

  Future<DecoderReply> _send(DecoderRequest request) {
    if (_exited) {
      return Future.error(
        const DecoderFailure(
          DecoderFailureKind.engine,
          'The decoder isolate is not running',
        ),
      );
    }
    final reply = Completer<DecoderReply>();
    _pending.add(reply);
    _requests.send(request);
    return reply.future.then(
      (value) => switch (value) {
        DecoderFailure() => throw value,
        _ => value,
      },
    );
  }

  void _onReply(Object? message) {
    if (message is SendPort) {
      _requests = message;
      _started.complete();
      return;
    }
    if (message is DecoderReply) {
      if (_pending.isNotEmpty) _pending.removeFirst().complete(message);
      return;
    }
    _exited = true;
    _replies.close();
    if (!_started.isCompleted) {
      _started.completeError(
        const DecoderFailure(
          DecoderFailureKind.engine,
          'The decoder isolate did not start',
        ),
      );
    }
    while (_pending.isNotEmpty) {
      _pending.removeFirst().complete(
        const DecoderFailure(
          DecoderFailureKind.engine,
          'The decoder isolate exited',
        ),
      );
    }
  }
}

void _decoderMain(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);

  var bindingsInitialized = false;
  sherpa.OfflineRecognizer? recognizer;

  void freeRecognizer() {
    recognizer?.free();
    recognizer = null;
  }

  DecoderReply init(InitDecoder request) {
    freeRecognizer();
    final files = [request.encoder, request.decoder, request.tokens];
    if (!files.every((path) => File(path).existsSync())) {
      return const DecoderFailure(
        DecoderFailureKind.modelMissing,
        'A Whisper model file is missing',
      );
    }
    try {
      if (!bindingsInitialized) {
        sherpa.initBindings();
        bindingsInitialized = true;
      }
      recognizer = sherpa.OfflineRecognizer(_configFor(request));
      return const DecoderReady();
    } catch (error) {
      return DecoderFailure.fromError(
        DecoderFailureKind.engine,
        'Could not load the Whisper model',
        error,
      );
    }
  }

  DecoderReply decode(DecodeSamples request) {
    final active = recognizer;
    if (active == null) {
      return const DecoderFailure(
        DecoderFailureKind.engine,
        'The decoder was not initialized',
      );
    }
    final sherpa.OfflineStream stream;
    try {
      stream = active.createStream();
    } catch (error) {
      return DecoderFailure.fromError(
        DecoderFailureKind.engine,
        'Could not create a decoding stream',
        error,
      );
    }
    try {
      stream.acceptWaveform(
        samples: request.materialize(),
        sampleRate: _sampleRate,
      );
      active.decode(stream);
      final result = active.getResult(stream);
      return DecodedText(result.text.trim(), lang: result.lang);
    } catch (error) {
      return DecoderFailure.fromError(
        DecoderFailureKind.engine,
        'Decoding failed',
        error,
      );
    } finally {
      stream.free();
    }
  }

  requests.listen((message) {
    switch (message) {
      case InitDecoder():
        replies.send(init(message));
      case DecodeSamples():
        replies.send(decode(message));
      case DisposeDecoder():
        freeRecognizer();
        requests.close();
        Isolate.exit(replies, const DecoderDisposed());
    }
  });
}

const _sampleRate = 16000;

sherpa.OfflineRecognizerConfig _configFor(InitDecoder request) =>
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: request.encoder,
          decoder: request.decoder,
          language: request.languageCode,
          task: 'transcribe',
        ),
        tokens: request.tokens,
        modelType: 'whisper',
        numThreads: request.numThreads,
        // The native library prints decoded text to logcat in debug mode.
        debug: false,
      ),
    );
