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

/// Where to cut [samples] between [from] and [to]: the middle of the quietest
/// [window] samples in a row there, so the cut falls in a pause between words.
/// Returns [to] when the range is shorter than a window.
int quietestCut(Float32List samples, int from, int to, {int window = 1600}) {
  final start = math.max(0, from);
  final end = math.min(to, samples.length);
  if (end - start < window) return end;
  double sum = 0;
  for (var i = start; i < start + window; i++) {
    sum += samples[i] * samples[i];
  }
  var quietest = sum;
  var at = start;
  for (var i = start + window; i < end; i++) {
    sum += samples[i] * samples[i] - samples[i - window] * samples[i - window];
    if (sum < quietest) {
      quietest = sum;
      at = i - window + 1;
    }
  }
  return at + window ~/ 2;
}

/// [SpeechRecognition] backed by a multilingual Whisper model in sherpa-onnx.
///
/// Whisper decodes at most 30 s at a time, so a session is cut into pieces of
/// up to [segmentSamples], each ending at the quietest moment of its last
/// [cutSearchSamples]. A piece is decoded as soon as it is cut, while capture
/// goes on, and [stop] decodes the rest and joins the texts in order. At
/// [maxDuration] capture stops, the stream reports [AudioTooLong], and [stop]
/// still transcribes everything heard so nothing the user said is lost. The
/// decode itself runs in a [WhisperDecoderIsolate].
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
  static final maxSamples = maxDuration.inSeconds * sampleRate;
  static final segmentSamples = dictationSegment.inSeconds * sampleRate;
  static final cutSearchSamples = dictationCutSearch.inSeconds * sampleRate;
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
        if (session.tooLong) return;
        final room = maxSamples - session.totalSamples;
        final kept = chunk.length <= room ? chunk : chunk.sublist(0, room);
        session
          ..append(kept)
          ..totalSamples += kept.length;
        while (session.sampleCount >= segmentSamples) {
          _cutSegment(session);
        }
        if (chunk.length > room) {
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

    _queueDecode(session, session.takeSamples());
    await session.decoding;
    try {
      final failure = session.failure;
      if (failure != null) throw failure;
      final decoded = joinDecodedTexts(session.texts);
      session.results.add(
        RecognitionResult(
          text: decoded.text,
          isFinal: true,
          lang: decoded.lang,
        ),
      );
      return decoded.text;
    } finally {
      unawaited(session.results.close());
    }
  }

  /// Sends the first piece of the buffered audio to the decoder and keeps the
  /// rest buffered.
  void _cutSegment(_Session session) {
    final samples = session.takeSamples();
    final cut = quietestCut(
      samples,
      segmentSamples - cutSearchSamples,
      segmentSamples,
    );
    session.append(samples.sublist(cut));
    _queueDecode(session, samples.sublist(0, cut));
  }

  /// Decodes [samples] after the session's earlier pieces. The first failure
  /// is reported on the stream at once and skips the pieces after it.
  void _queueDecode(_Session session, Float32List samples) {
    session.decoding = session.decoding.then((_) async {
      if (session.cancelled || session.failure != null) return;
      try {
        session.texts.add(await _decode(samples));
      } catch (error) {
        if (session.cancelled) return;
        final failure = error is EngineFailure
            ? error
            : const EngineFailure('Decoding failed');
        session.failure = failure;
        session.results.addError(failure);
      }
    });
  }

  Future<DecodedText> _decode(Float32List samples) async {
    if (samples.isEmpty) return const DecodedText('');
    if (loudestWindowRms(samples) < dictationMinLoudness) {
      return const DecodedText('');
    }
    final decoder = _decoder;
    if (decoder == null) throw const EngineFailure('The decoder is gone');
    try {
      return await decoder.decode(samples);
    } on DecoderFailure catch (failure) {
      throw EngineFailure(failure.message);
    }
  }

  @override
  Future<void> cancel() async {
    final session = _session;
    if (session == null) return;
    _session = null;
    session.cancelled = true;
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

/// The pieces' texts as one: trimmed, the empty ones dropped, joined by
/// spaces. The language is the first one Whisper reported for a piece that
/// had words.
DecodedText joinDecodedTexts(List<DecodedText> pieces) {
  final spoken = [
    for (final piece in pieces)
      if (piece.text.trim().isNotEmpty) piece,
  ];
  return DecodedText(
    spoken.map((piece) => piece.text.trim()).join(' '),
    lang: spoken
        .map((piece) => piece.lang)
        .firstWhere((lang) => lang.isNotEmpty, orElse: () => ''),
  );
}

class _Session {
  final results = StreamController<RecognitionResult>();
  final _chunks = <Float32List>[];
  StreamSubscription<Float32List>? subscription;

  /// Samples buffered since the last cut.
  int sampleCount = 0;

  /// Samples captured in the whole session.
  int totalSamples = 0;
  bool tooLong = false;
  bool cancelled = false;
  Future<void> decoding = Future.value();
  final texts = <DecodedText>[];
  EngineFailure? failure;

  void append(Float32List chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(chunk);
    sampleCount += chunk.length;
  }

  /// Joins the buffered chunks and empties the buffer.
  Float32List takeSamples() {
    final samples = Float32List(sampleCount);
    var offset = 0;
    for (final chunk in _chunks) {
      samples.setAll(offset, chunk);
      offset += chunk.length;
    }
    discardSamples();
    return samples;
  }

  void discardSamples() {
    _chunks.clear();
    sampleCount = 0;
  }
}
