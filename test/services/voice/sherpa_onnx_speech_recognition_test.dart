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
    final error = decodeError;
    if (error != null) throw error;
    return reply;
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

  test(
      'past 30 s capture stops, the stream reports AudioTooLong once, and '
      'stop decodes the first 30 s', () async {
    await engine.initialize(SpeechLanguageChoice.auto);
    final errors = <Object>[];
    final results = <RecognitionResult>[];
    final done = _closed(engine.start(), results.add, errors.add);

    const second = SherpaOnnxSpeechRecognition.sampleRate;
    for (var i = 0; i < 30; i++) {
      audio.add(_chunk(second, 0.2));
    }
    expect(errors, isEmpty);
    audio.add(_chunk(second, 0.9));
    await Future<void>.delayed(Duration.zero);
    expect(audio.hasListener, isFalse);

    expect(await engine.stop(), 'hello');
    await done;

    expect(errors, [isA<AudioTooLong>()]);
    expect(results.single.text, 'hello');
    final samples = decoder.decoded.single;
    expect(samples.length, SherpaOnnxSpeechRecognition.maxSamples);
    expect(samples.last, closeTo(0.2, 1e-6));
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
