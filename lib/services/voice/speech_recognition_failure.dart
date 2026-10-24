import 'speech_language.dart';

/// Failures carry no transcript text or audio, so they are safe to log.
sealed class SpeechRecognitionFailure implements Exception {
  const SpeechRecognitionFailure();
}

final class ModelNotInstalled extends SpeechRecognitionFailure {
  const ModelNotInstalled(this.language);

  final SpeechLanguage language;

  @override
  String toString() =>
      'ModelNotInstalled: no speech model installed for ${language.name} '
      '(${language.code})';
}

final class EngineFailure extends SpeechRecognitionFailure {
  const EngineFailure(this.reason);

  final String reason;

  @override
  String toString() => 'EngineFailure: $reason';
}

final class AudioTooLong extends SpeechRecognitionFailure {
  const AudioTooLong(this.limit);

  final Duration limit;

  @override
  String toString() =>
      'AudioTooLong: recording exceeded the ${limit.inSeconds} s limit';
}
