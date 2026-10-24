import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/whisper_model_files.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition_failure.dart';

const _encoder = 'tiny-encoder.int8.onnx';
const _decoder = 'tiny-decoder.int8.onnx';
const _tokens = 'tiny-tokens.txt';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('whisper_model_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void createFiles(List<String> names) {
    for (final name in names) {
      File('${dir.path}/$name').writeAsStringSync('');
    }
  }

  Matcher throwsModelNotInstalledFor(SpeechLanguage language) => throwsA(
    isA<ModelNotInstalled>().having(
      (failure) => failure.language,
      'language',
      language,
    ),
  );

  test('returns the encoder, decoder and tokens paths', () {
    createFiles([_encoder, _decoder, _tokens, 'tiny-encoder.onnx']);

    final files = WhisperModelFiles.inDirectory(
      dir.path,
      SpeechLanguage.english,
    );

    expect(files.encoder, '${dir.path}/$_encoder');
    expect(files.decoder, '${dir.path}/$_decoder');
    expect(files.tokens, '${dir.path}/$_tokens');
  });

  for (final (missing, present) in [
    ('encoder', [_decoder, _tokens]),
    ('decoder', [_encoder, _tokens]),
    ('tokens', [_encoder, _decoder]),
  ]) {
    test('throws ModelNotInstalled when the $missing file is missing', () {
      createFiles(present);

      expect(
        () => WhisperModelFiles.inDirectory(dir.path, SpeechLanguage.hebrew),
        throwsModelNotInstalledFor(SpeechLanguage.hebrew),
      );
    });
  }

  test('throws ModelNotInstalled when the directory does not exist', () {
    expect(
      () => WhisperModelFiles.inDirectory(
        '${dir.path}/absent',
        SpeechLanguage.russian,
      ),
      throwsModelNotInstalledFor(SpeechLanguage.russian),
    );
  });
}
