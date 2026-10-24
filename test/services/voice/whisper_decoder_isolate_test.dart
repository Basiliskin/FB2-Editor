import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/sherpa_onnx_speech_recognition.dart';
import 'package:quill_fb2/services/voice/whisper_decoder_isolate.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';

void main() {
  Future<Object?> echo(Object message) => Isolate.run(() => message);

  group('decoder messages cross an isolate boundary', () {
    test('InitDecoder', () async {
      const message = InitDecoder(
        encoder: '/m/small-encoder.int8.onnx',
        decoder: '/m/small-decoder.int8.onnx',
        tokens: '/m/small-tokens.txt',
        languageCode: 'ru',
        numThreads: 2,
      );
      expect(await echo(message), message);
    });

    test('DecodeSamples keeps the samples', () async {
      final samples = Float32List.fromList([0.25, -0.5, 1]);
      final received = await Isolate.run(() => DecodeSamples(samples));
      expect(received.materialize(), samples);
    });

    test('DisposeDecoder and the replies', () async {
      expect(await echo(const DisposeDecoder()), isA<DisposeDecoder>());
      expect(await echo(const DecoderReady()), isA<DecoderReady>());
      expect(await echo(const DecoderDisposed()), isA<DecoderDisposed>());
      expect(
        await echo(const DecodedText('hello')),
        const DecodedText('hello'),
      );
      expect(
        await echo(const DecodedText('shalom', lang: 'he')),
        const DecodedText('shalom', lang: 'he'),
      );
      const failure = DecoderFailure(
        DecoderFailureKind.engine,
        'Decoding failed',
      );
      expect(await echo(failure), failure);
    });
  });

  test('Auto starts Whisper with an empty language code', () {
    expect(whisperLanguageCode(SpeechLanguageChoice.auto), '');
    for (final language in SpeechLanguage.values) {
      expect(
        whisperLanguageCode(SpeechLanguageChoice.of(language)),
        language.code,
      );
    }
  });

  test('a failure built from an error carries only its type', () {
    final failure = DecoderFailure.fromError(
      DecoderFailureKind.engine,
      'Decoding failed',
      StateError('LEAKED-TEXT /data/models/whisper-small'),
    );

    expect(failure.message, 'Decoding failed (StateError)');
    expect(failure.toString(), isNot(contains('LEAKED-TEXT')));
    expect(failure.toString(), isNot(contains('/data/models')));
  });
}
