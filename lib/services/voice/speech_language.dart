enum SpeechLanguage {
  russian('ru'),
  hebrew('he'),
  english('en');

  const SpeechLanguage(this.code);

  final String code;

  static SpeechLanguage fromCode(String code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    throw ArgumentError.value(code, 'code', 'Unsupported speech language code');
  }
}

/// What the user asked Whisper to listen for: one [SpeechLanguage], or [auto]
/// to let the engine guess.
final class SpeechLanguageChoice {
  const SpeechLanguageChoice._(this.language);

  static const auto = SpeechLanguageChoice._(null);

  const SpeechLanguageChoice.of(SpeechLanguage this.language);

  /// Null for [auto].
  final SpeechLanguage? language;

  bool get isAuto => language == null;

  String get code => language?.code ?? 'auto';

  static SpeechLanguageChoice fromCode(String code) => code == 'auto'
      ? auto
      : SpeechLanguageChoice.of(SpeechLanguage.fromCode(code));

  @override
  bool operator ==(Object other) =>
      other is SpeechLanguageChoice && other.language == language;

  @override
  int get hashCode => language.hashCode;
}

/// Maps the engine's language guess to a [SpeechLanguage], or [fallback] when
/// the guess is missing or not ru/he/en.
SpeechLanguage resolveDetectedLanguage(String? lang, SpeechLanguage fallback) {
  final code = lang?.trim().toLowerCase();
  for (final language in SpeechLanguage.values) {
    if (language.code == code) return language;
  }
  return fallback;
}
