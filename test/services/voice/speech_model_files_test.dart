import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/speech_model_files.dart';

const _resolve =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/'
    '8f3c18b358db4d1f2fc1eae49d75cd20989e4309/';

void main() {
  test('lists the encoder, decoder and tokens in that order', () {
    expect(SpeechModelFile.all, [
      SpeechModelFile.encoder,
      SpeechModelFile.decoder,
      SpeechModelFile.tokens,
    ]);
  });

  test('pins each file name, size and fingerprint', () {
    expect(
      [
        for (final file in SpeechModelFile.all)
          (file.name, file.sizeInBytes, file.sha256),
      ],
      [
        (
          'small-encoder.int8.onnx',
          112442483,
          '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
        ),
        (
          'small-decoder.int8.onnx',
          262226114,
          'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
        ),
        (
          'small-tokens.txt',
          816730,
          'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
        ),
      ],
    );
  });

  test('downloads each file over HTTPS from the pinned commit', () {
    for (final file in SpeechModelFile.all) {
      expect(file.downloadUrl, '$_resolve${file.name}');
    }
  });

  test('the total is the sum of the file sizes', () {
    expect(SpeechModelFile.totalBytes, 375485327);
    expect(
      SpeechModelFile.totalBytes,
      SpeechModelFile.all.fold<int>(0, (sum, file) => sum + file.sizeInBytes),
    );
  });
}
