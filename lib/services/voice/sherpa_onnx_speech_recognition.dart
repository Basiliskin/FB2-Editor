import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dictation_limits.dart';
import 'recognition_result.dart';
import 'speech_language.dart';
import 'speech_recognition.dart';
import 'speech_recognition_failure.dart';
import 'whisper_decoder_isolate.dart';
import 'whisper_model_files.dart';

/// Whisper detects the language itself when given an empty code.
String whisperLanguageCode(SpeechLanguageChoice choice) =>
    choice.language?.code ?? '';

/// The RMS level, on a scale of 0 to 1, of the loudest [window] samples in a
/// row. A short click scores low; speech holds a level for a while.
double loudestWindowRms(Float32List samples, {int window = 1600}) {
  if (samples.isEmpty) return 0;
  final size = math.min(window, samples.length);
  double sum = 0;
  for (var i = 0; i < size; i++) {
    sum += samples[i] * samples[i];
  }
  var loudest = sum;
  for (var i = size; i < samples.length; i++) {
    sum += samples[i] * samples[i] - samples[i - size] * samples[i - size];
    if (sum > loudest) loudest = sum;
  }
  return math.sqrt(math.max(loudest, 0) / size);
}

/// [SpeechRecognition] backed by a multilingual Whisper model in sherpa-onnx.
///
/// Audio is buffered in memory while a session runs and decoded in one pass
/// on [stop], so a session is limited to Whisper's 30 s decode window. At the
/// limit capture stops, the stream reports [AudioTooLong], and [stop] still
/// decodes the first 30 s so nothing the user said is lost. The decode itself
/// runs in a [WhisperDecoderIsolate].
class SherpaOnnxSpeechRecognition implements SpeechRecognition {
  SherpaOnnxSpeechRecognition({
    required Future<WhisperModelFiles> Function(SpeechLanguage language)
        modelFiles,
    required Stream<Float32List> Function() audioSource,
    Future<WhisperDecoder> Function()? decoderFactory,
    int numThreads = 2,
  })  : _modelFiles = modelFiles,
        _audioSource = audioSource,
        _decoderFactory = decoderFactory ?? WhisperDecoderIsolate.spawn,
        _numThreads = numThreads;

  static const sampleRate = 16000;
  static const maxDuration = dictationMaxDuration;
  static const maxSamples = 30 * sampleRate;
  // One Whisper model directory serves every language.
  static const _autoModelLanguage = SpeechLanguage.english;

  final Future<WhisperModelFiles> Function(SpeechLanguage language) _modelFiles;
  final Stream<Float32List> Function() _audioSource;
  final Future<WhisperDecoder> Function() _decoderFactory;
  final int _numThreads;

  WhisperDecoder? _decoder;
  bool _initialized = false;
  _Session? _session;

  @override
  Future<void> initialize(SpeechLanguageChoice choice) async {
    _initialized = false;
    final language = choice.language ?? _autoModelLanguage;
    try {
      final files = await _modelFiles(language);
      final decoder = _decoder ??= await _decoderFactory();
      await decoder.init(
        InitDecoder(
          encoder: files.encoder,
          decoder: files.decoder,
          tokens: files.tokens,
          languageCode: whisperLanguageCode(choice),
          numThreads: _numThreads,
        ),
      );
      _initialized = true;
    } on DecoderFailure catch (failure) {
      throw switch (failure.kind) {
        DecoderFailureKind.modelMissing => ModelNotInstalled(language),
        DecoderFailureKind.engine => EngineFailure(failure.message),
      };
    } on IsolateSpawnException catch (error) {
      throw EngineFailure(
        'Could not start the decoder isolate (${error.runtimeType})',
      );
    }
  }

  @override
  Stream<RecognitionResult> start() {
    if (!_initialized) {
      throw StateError('initialize() must complete before start()');
    }
    if (_session != null) {
      throw StateError('A recognition session is already running');
    }
    final session = _Session();
    _session = session;
    session.subscription = _audioSource().listen(
      (chunk) {
        session.append(chunk);
        if (session.sampleCount > maxSamples && !session.tooLong) {
          session.tooLong = true;
          session.results.addError(const AudioTooLong(maxDuration));
          unawaited(session.subscription?.cancel());
        }
      },
      onError: (Object _) => session.results.addError(
        const EngineFailure('The audio source failed'),
      ),
    );
    return session.results.stream;
  }

  @override
  Future<String> stop() async {
    final session = _session;
    if (session == null) {
      throw StateError('stop() called without a running session');
    }
    _session = null;
    await session.subscription?.cancel();

    try {
      final decoded = await _decode(session.takeSamples(maxSamples));
      session.results.add(
        RecognitionResult(
          text: decoded.text,
          isFinal: true,
          lang: decoded.lang,
        ),
      );
      return decoded.text;
    } on EngineFailure catch (failure) {
      session.results.addError(failure);
      rethrow;
    } finally {
      unawaited(session.results.close());
    }
  }

  Future<DecodedText> _decode(Float32List samples) async {
    if (samples.isEmpty) return const DecodedText('');
    if (loudestWindowRms(samples) < dictationMinLoudness) {
      return const DecodedText('');
    }
    try {
      return await _decoder!.decode(samples);
    } on DecoderFailure catch (failure) {
      throw EngineFailure(failure.message);
    }
  }

  @override
  Future<void> cancel() async {
    final session = _session;
    if (session == null) return;
    _session = null;
    await session.subscription?.cancel();
    session.discardSamples();
    unawaited(session.results.close());
  }

  @override
  Future<void> dispose() async {
    await cancel();
    final decoder = _decoder;
    _decoder = null;
    _initialized = false;
    await decoder?.dispose();
  }
}

class _Session {
  final results = StreamController<RecognitionResult>();
  final _chunks = <Float32List>[];
  StreamSubscription<Float32List>? subscription;
  int sampleCount = 0;
  bool tooLong = false;

  void append(Float32List chunk) {
    _chunks.add(chunk);
    sampleCount += chunk.length;
  }

  /// Joins the buffered chunks, keeping at most [limit] samples.
  Float32List takeSamples(int limit) {
    final samples = Float32List(sampleCount < limit ? sampleCount : limit);
    var offset = 0;
    for (final chunk in _chunks) {
      final room = samples.length - offset;
      if (room <= 0) break;
      samples.setAll(
          offset, chunk.length <= room ? chunk : chunk.sublist(0, room));
      offset += chunk.length < room ? chunk.length : room;
    }
    _chunks.clear();
    sampleCount = 0;
    return samples;
  }

  void discardSamples() {
    _chunks.clear();
    sampleCount = 0;
  }
}
