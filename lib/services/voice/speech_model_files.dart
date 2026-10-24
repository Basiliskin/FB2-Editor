const _downloadBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/'
    '8f3c18b358db4d1f2fc1eae49d75cd20989e4309';

/// One of the three files that make up the Speech Model. The Speech Model
/// counts as installed only when every file is present with exactly these
/// bytes.
final class SpeechModelFile {
  const SpeechModelFile._(
    this.name, {
    required this.sizeInBytes,
    required this.sha256,
  }) : downloadUrl = '$_downloadBase/$name';

  static const encoder = SpeechModelFile._(
    'small-encoder.int8.onnx',
    sizeInBytes: 112442483,
    sha256: '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
  );

  static const decoder = SpeechModelFile._(
    'small-decoder.int8.onnx',
    sizeInBytes: 262226114,
    sha256: 'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
  );

  static const tokens = SpeechModelFile._(
    'small-tokens.txt',
    sizeInBytes: 816730,
    sha256: 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
  );

  static const all = [encoder, decoder, tokens];

  /// The sum of every file's size, shown to the user as 375 MB.
  static const totalBytes = 375485327;

  final String name;
  final int sizeInBytes;

  /// Lowercase hex SHA-256 of the file's bytes.
  final String sha256;

  /// Pinned to one upstream commit, so a later upstream push can never
  /// change what is downloaded.
  final String downloadUrl;
}
