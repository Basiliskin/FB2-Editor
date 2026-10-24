import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/recognition_result.dart';
import 'package:quill_fb2/services/voice/sherpa_onnx_speech_recognition.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition_failure.dart';
import 'package:quill_fb2/services/voice/whisper_decoder_isolate.dart';
import 'package:quill_fb2/services/voice/whisper_model_files.dart';

class _FakeDecoder implements WhisperDecoder {
  Object? initError;
  Object? decodeError;
  DecodedText reply = const DecodedText('hello', lang: 'en');

  /// Replies for successive decodes; [reply] once they run out.
  List<DecodedText> replies = [];

  /// Holds every decode until it completes.
  Completer<void>? gate;
  final List<InitDecoder> inits = [];
  final List<Float32List> decoded = [];
  bool disposed = false;

  @override
  Future<void> init(InitDecoder request) async {
    inits.add(request);
    final error = initError;
    if (error != null) throw error;
  }

  @override
  Future<DecodedText> decode(Float32List samples) async {
    decoded.add(samples);
    await gate?.future;
    final error = decodeError;
    if (error != null) throw error;
    final index = decoded.length - 1;
    return index < replies.length ? replies[index] : reply;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

Float32List _chunk(int length, [double value = 0.1]) =>
    Float32List.fromList(List.filled(length, value));

/// Completes when [stream] closes; unlike asFuture it survives stream errors.
Future<void> _closed(
  Stream<RecognitionResult> stream,
  void Function(RecognitionResult) onData,
  void Function(Object) onError,
) {
  final closed = Completer<void>();
  stream.listen(onData, onError: onError, onDone: closed.complete);
  return closed.future;
}

void main() {
  late _FakeDecoder decoder;
  late StreamController<Float32List> audio;
  late int audioStarts;
  late SherpaOnnxSpeechRecognition engine;

  setUp(() {
    decoder = _FakeDecoder();
    audioStarts = 0;
    engine = SherpaOnnxSpeechRecognition(
      modelFiles: (language) async =>
          const WhisperModelFiles(encoder: 'e', decoder: 'd', tokens: 't'),
      audioSource: () {
        audioStarts++;
        audio = StreamController<Float32List>(sync: true);
        return audio.stream;
      },
      decoderFactory: () async => decoder,
    );
  });

  tearDown(() async {
    await engine.dispose();
    // close() only completes once someone listens, so don't await it.
    if (audioStarts > 0) unawaited(audio.close());
  });

  test('initialize hands the model files and language code to the decoder',
      () async {
    await engine.initialize(SpeechLanguageChoice.of(SpeechLanguage.hebrew));
    await engine.initialize(SpeechLanguageChoice.auto);

    expect(decoder.inits.map((i) => i.languageCode), ['he', '']);
    expect(decoder.inits.first.encoder, 'e');
    expect(decoder.inits.first.numThreads, 2);
  });

  test('a missing model file becomes ModelNotInstalled', () async {
    decoder.initError =
        const DecoderFailure(DecoderFailureKind.modelMissing, 'missing');
    expect(
      engine.initialize(SpeechLanguageChoice.of(SpeechLanguage.russian)),
      throwsA(isA<ModelNotInstalled>()
          .having((e) => e.language, 'language', SpeechLanguage.russian)),
    );
  });

  test('Auto reports the English model slot when it is missing', () async {
    decoder.initError =
        const DecoderFailure(DecoderFailureKind.modelMissing, 'missing');
    expect(
      engine.initialize(SpeechLanguageChoice.auto),
      throwsA(isA<ModelNotInstalled>()
          .having((e) => e.language, 'language', SpeechLanguage.english)),
    );
  });

  test('an engine problem becomes EngineFailure', () async {
    decoder.initError =
        const DecoderFailure(DecoderFailureKind.engine, 'could not load');
    expect(engine.initialize(SpeechLanguageChoice.auto),
        throwsA(isA<EngineFailure>()));
  });

  test('start needs initialize first and allows one session at a time',
      () async {
    expect(engine.start, throwsStateError);
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});
    expect(engine.start, throwsStateError);
  });

  test('a failed initialize leaves the engine unusable', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    decoder.initError = const DecoderFailure(DecoderFailureKind.engine, 'x');
    await expectLater(engine.initialize(SpeechLanguageChoice.auto),
        throwsA(isA<EngineFailure>()));
    expect(engine.start, throwsStateError);
  });

  test('stop decodes the buffered audio and emits one final result', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final results = <RecognitionResult>[];
    final done = engine.start().listen(results.add).asFuture<void>();

    audio
      ..add(_chunk(1600))
      ..add(_chunk(800, 0.5));
    final text = await engine.stop();
    await done;

    expect(text, 'hello');
    expect(results,
        const [RecognitionResult(text: 'hello', isFinal: true, lang: 'en')]);
    expect(decoder.decoded.single.length, 2400);
    expect(decoder.decoded.single[0], closeTo(0.1, 1e-6));
    expect(decoder.decoded.single[2399], closeTo(0.5, 1e-6));
  });

  test('stop on a silent recording returns empty text and does not decode',
      () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final results = <RecognitionResult>[];
    final done = engine.start().listen(results.add).asFuture<void>();

    audio.add(_chunk(48000, 0.01));
    final text = await engine.stop();
    await done;

    expect(text, '');
    expect(decoder.decoded, isEmpty);
    expect(results.single.text, '');
    expect(results.single.isFinal, isTrue);
  });

  test('a short loud burst in quiet audio is still transcribed', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    audio
      ..add(_chunk(32000, 0.002))
      ..add(_chunk(3200, 0.3))
      ..add(_chunk(32000, 0.002));

    expect(await engine.stop(), 'hello');
    expect(decoder.decoded, hasLength(1));
  });

  group('loudestWindowRms', () {
    test('is zero for no samples and for silence', () {
      expect(loudestWindowRms(Float32List(0)), 0);
      expect(loudestWindowRms(Float32List(5000)), 0);
    });

    test('is the level of a steady signal', () {
      expect(loudestWindowRms(_chunk(8000, 0.2)), closeTo(0.2, 1e-6));
    });

    test('finds the loudest window, not the average', () {
      final samples = Float32List(16000)..fillRange(8000, 9600, 0.5);
      expect(loudestWindowRms(samples), closeTo(0.5, 1e-6));
    });

    test('uses the whole signal when it is shorter than a window', () {
      expect(loudestWindowRms(_chunk(100, 0.4)), closeTo(0.4, 1e-6));
    });
  });

  test('stop without audio returns empty text and does not decode', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    expect(await engine.stop(), '');
    expect(decoder.decoded, isEmpty);
  });

  test('stop without a session is a StateError', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    expect(engine.stop(), throwsStateError);
  });

  const second = SherpaOnnxSpeechRecognition.sampleRate;

  /// Feeds [seconds] of audio in 100 ms chunks of [level], with a 100 ms
  /// silence starting at each second listed in [pausesAt].
  void speak(int seconds, {double level = 0.2, Set<int> pausesAt = const {}}) {
    for (var tenth = 0; tenth < seconds * 10; tenth++) {
      final quiet = pausesAt.contains(tenth ~/ 10) && tenth % 10 == 0;
      audio.add(_chunk(second ~/ 10, quiet ? 0.0 : level));
    }
  }

  test(
      'at the length limit capture stops, the stream reports AudioTooLong '
      'once, and stop transcribes everything up to the limit', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final results = <RecognitionResult>[];
    final done = _closed(engine.start(), results.add, errors.add);

    final limit = SherpaOnnxSpeechRecognition.maxDuration.inSeconds;
    speak(limit);
    expect(errors, isEmpty);
    audio.add(_chunk(second, 0.9));
    await Future<void>.delayed(Duration.zero);
    expect(audio.hasListener, isFalse);

    await engine.stop();
    await done;

    expect(errors, [isA<AudioTooLong>()]);
    expect(results.single.isFinal, isTrue);
    final heard = decoder.decoded.fold<int>(0, (n, s) => n + s.length);
    expect(heard, SherpaOnnxSpeechRecognition.maxSamples);
    expect(decoder.decoded.every((s) => s.every((v) => v < 0.5)), isTrue);
  });

  test('a chunk that crosses the limit is kept up to the limit', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final done = _closed(engine.start(), (_) {}, errors.add);

    final limit = SherpaOnnxSpeechRecognition.maxDuration.inSeconds;
    speak(limit - 1);
    audio.add(_chunk(second + 800));
    audio.add(_chunk(800));
    await engine.stop();
    await done;

    expect(errors, [isA<AudioTooLong>()]);
    final heard = decoder.decoded.fold<int>(0, (n, s) => n + s.length);
    expect(heard, SherpaOnnxSpeechRecognition.maxSamples);
  });

  test('exactly the limit is not too long', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final done = _closed(engine.start(), (_) {}, errors.add);

    speak(SherpaOnnxSpeechRecognition.maxDuration.inSeconds);
    await engine.stop();
    await done;

    expect(errors, isEmpty);
  });

  test('a long recording is decoded in pieces while it is still recording',
      () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    speak(29);
    await pumpEventQueue();
    expect(decoder.decoded, isEmpty);

    speak(1);
    await pumpEventQueue();
    expect(decoder.decoded, hasLength(1));
    expect(audio.hasListener, isTrue);

    speak(40);
    await pumpEventQueue();
    expect(decoder.decoded, hasLength(2));

    await engine.stop();
    expect(decoder.decoded, hasLength(3));
    final heard = decoder.decoded.fold<int>(0, (n, s) => n + s.length);
    expect(heard, 70 * second);
    for (final piece in decoder.decoded) {
      expect(piece.length,
          lessThanOrEqualTo(SherpaOnnxSpeechRecognition.segmentSamples));
    }
  });

  test('a piece ends in the pause closest to its end', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    speak(30, pausesAt: {10, 27});
    await engine.stop();

    // The pause at 10 s is too early; the one at 27 s, 27.0 to 27.1 s, is cut
    // in the middle.
    expect(decoder.decoded.first.length, 27 * second + 800);
    expect(decoder.decoded.first.last, 0.0);
    expect(decoder.decoded.last.first, 0.0);
  });

  test('with no pause a piece is cut no later than 30 s', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    speak(31);
    await engine.stop();

    expect(decoder.decoded, hasLength(2));
    expect(decoder.decoded.first.length,
        lessThanOrEqualTo(SherpaOnnxSpeechRecognition.segmentSamples));
    expect(decoder.decoded.first.length,
        greaterThanOrEqualTo(25 * second));
  });

  test('the pieces\' texts are joined in order with the first language',
      () async {
    final replies = [
      const DecodedText(' one ', lang: 'ru'),
      const DecodedText('two', lang: 'en'),
      const DecodedText('three', lang: 'en'),
    ];
    decoder.replies = replies;
    await engine.initialize(SpeechLanguageChoice.auto);
    final results = <RecognitionResult>[];
    final done = engine.start().listen(results.add).asFuture<void>();

    speak(65);
    final text = await engine.stop();
    await done;

    expect(text, 'one two three');
    expect(results.single,
        const RecognitionResult(text: 'one two three', isFinal: true, lang: 'ru'));
  });

  test('a silent piece in a long recording adds nothing', () async {
    decoder.replies = [const DecodedText('one'), const DecodedText('three')];
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    speak(25);
    speak(60, level: 0.001);
    speak(10);

    expect(await engine.stop(), 'one three');
    expect(decoder.decoded, hasLength(2));
  });

  test('stop waits for a piece still being decoded', () async {
    final gate = Completer<void>();
    decoder.gate = gate;
    decoder.replies = [const DecodedText('first'), const DecodedText('last')];
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    speak(35);
    var stopped = false;
    final text = engine.stop().then((t) {
      stopped = true;
      return t;
    });
    await pumpEventQueue();
    expect(stopped, isFalse);

    gate.complete();
    expect(await text, 'first last');
  });

  test('a failed piece is reported at once and skips the rest', () async {
    decoder.decodeError =
        const DecoderFailure(DecoderFailureKind.engine, 'Decoding failed');
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final done = _closed(engine.start(), (_) {}, errors.add);

    speak(30);
    await pumpEventQueue();
    expect(errors, [isA<EngineFailure>()]);

    speak(30);
    await expectLater(engine.stop(), throwsA(isA<EngineFailure>()));
    await done;
    expect(errors, hasLength(1));
    expect(decoder.decoded, hasLength(1));
  });

  test('an unexpected decode error becomes EngineFailure', () async {
    decoder.decodeError = StateError('boom');
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final done = _closed(engine.start(), (_) {}, errors.add);

    audio.add(_chunk(1600));
    await expectLater(engine.stop(), throwsA(isA<EngineFailure>()));
    await done;
    expect(errors, [isA<EngineFailure>()]);
  });

  test('cancel drops the pieces still waiting to be decoded', () async {
    final gate = Completer<void>();
    decoder.gate = gate;
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final done = _closed(engine.start(), (_) {}, errors.add);

    speak(60);
    await pumpEventQueue();
    expect(decoder.decoded, hasLength(1));

    await engine.cancel();
    decoder.decodeError =
        const DecoderFailure(DecoderFailureKind.engine, 'gone');
    gate.complete();
    await done;
    await pumpEventQueue();

    expect(decoder.decoded, hasLength(1));
    expect(errors, isEmpty);
  });

  test('a decode after dispose fails as EngineFailure', () async {
    final gate = Completer<void>();
    decoder.gate = gate;
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final done = _closed(engine.start(), (_) {}, errors.add);

    speak(31);
    final stopped = engine.stop();
    await pumpEventQueue();
    await engine.dispose();
    gate.complete();

    await expectLater(stopped, throwsA(isA<EngineFailure>()));
    await done;
    expect(errors, [isA<EngineFailure>()]);
  });

  group('quietestCut', () {
    test('cuts in the middle of the quietest window', () {
      final samples = _chunk(16000, 0.3)..fillRange(4000, 5600, 0.0);
      expect(quietestCut(samples, 0, 16000), 4800);
    });

    test('only looks between from and to', () {
      final samples = _chunk(16000, 0.3)
        ..fillRange(1000, 2600, 0.0)
        ..fillRange(9000, 10600, 0.1);
      expect(quietestCut(samples, 8000, 16000), 9800);
    });

    test('returns to when the range is shorter than a window', () {
      expect(quietestCut(_chunk(16000), 15000, 16000), 16000);
      expect(quietestCut(_chunk(1000), 0, 4000), 1000);
    });
  });

  group('joinDecodedTexts', () {
    test('is empty with no language for no pieces', () {
      expect(joinDecodedTexts(const []), const DecodedText(''));
    });

    test('skips blank pieces and their language', () {
      expect(
        joinDecodedTexts(const [
          DecodedText(' ', lang: 'he'),
          DecodedText('a', lang: ''),
          DecodedText('b', lang: 'en'),
        ]),
        const DecodedText('a b', lang: 'en'),
      );
    });
  });

  test('a decode failure reaches the stream and stop', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    decoder.decodeError =
        const DecoderFailure(DecoderFailureKind.engine, 'Decoding failed');
    final errors = <Object>[];
    final done = _closed(engine.start(), (_) {}, errors.add);

    audio.add(_chunk(1600));
    await expectLater(engine.stop(), throwsA(isA<EngineFailure>()));
    await done;

    expect(errors, [isA<EngineFailure>()]);
  });

  test('an audio source error reaches the stream as EngineFailure', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    engine.start().listen((_) {}, onError: errors.add);

    audio.addError(StateError('mic gone'));
    await Future<void>.delayed(Duration.zero);

    expect(errors, [isA<EngineFailure>()]);
  });

  test('cancel closes the stream with no result and allows a new session',
      () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final results = <RecognitionResult>[];
    final done = engine.start().listen(results.add).asFuture<void>();
    audio.add(_chunk(1600));

    await engine.cancel();
    await done;

    expect(results, isEmpty);
    expect(decoder.decoded, isEmpty);
    expect(audio.hasListener, isFalse);

    engine.start().listen((_) {});
    expect(audioStarts, 2);
    audio.add(_chunk(800));
    await engine.stop();
    expect(decoder.decoded.single.length, 800);
  });

  test('cancel with no session does nothing', () async {
    await engine.cancel();
    expect(decoder.disposed, isFalse);
  });

  test('dispose ends the session and releases the decoder', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    engine.start().listen((_) {});

    await engine.dispose();

    expect(decoder.disposed, isTrue);
    expect(audio.hasListener, isFalse);
    expect(engine.start, throwsStateError);
  });

  test('whisper language code is empty for Auto', () {
    expect(whisperLanguageCode(SpeechLanguageChoice.auto), '');
    expect(whisperLanguageCode(SpeechLanguageChoice.of(SpeechLanguage.hebrew)),
        'he');
  });
}
