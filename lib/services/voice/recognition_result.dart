class RecognitionResult {
  const RecognitionResult({
    required this.text,
    required this.isFinal,
    this.lang,
  });

  final String text;
  final bool isFinal;

  /// The engine's own language guess for a final result; null when unknown.
  final String? lang;

  @override
  bool operator ==(Object other) =>
      other is RecognitionResult &&
      other.text == text &&
      other.isFinal == isFinal &&
      other.lang == lang;

  @override
  int get hashCode => Object.hash(text, isFinal, lang);
}
