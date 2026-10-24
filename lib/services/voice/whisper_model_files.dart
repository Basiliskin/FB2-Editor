import 'dart:io';

import 'speech_language.dart';
import 'speech_recognition_failure.dart';

class WhisperModelFiles {
  const WhisperModelFiles({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  /// Finds the int8 Whisper model files in [directory].
  ///
  /// Throws [ModelNotInstalled] for [language] when the encoder, decoder or
  /// tokens file is missing.
  factory WhisperModelFiles.inDirectory(
    String directory,
    SpeechLanguage language,
  ) {
    final dir = Directory(directory);
    final paths = dir.existsSync()
        ? (dir.listSync().whereType<File>().map((file) => file.path).toList()
            ..sort())
        : <String>[];

    String find(String suffix) => paths.firstWhere(
      (path) => path.endsWith(suffix),
      orElse: () => throw ModelNotInstalled(language),
    );

    return WhisperModelFiles(
      encoder: find('-encoder.int8.onnx'),
      decoder: find('-decoder.int8.onnx'),
      tokens: find('-tokens.txt'),
    );
  }

  final String encoder;
  final String decoder;
  final String tokens;
}
