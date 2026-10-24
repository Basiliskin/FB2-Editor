import 'dart:async';

import 'package:quill_fb2/services/voice/recognition_result.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/speech_recognition.dart';

class FakeSpeechRecognition implements SpeechRecognition {
  Object? initializeError;
  Object? stopError;
  String finalText = '';

  /// The language the engine reports on the final result; null reports none.
  String? finalLang;

  /// When true, [stop] emits the final result on the stream before it
  /// returns; when false the test delivers it later with [emitLateFinal].
  bool finalBeforeStop = true;

  /// When set, [initialize] or [stop] waits for the test to complete it.
  Completer<void>? initializeGate;
  Completer<void>? stopGate;

  final List<SpeechLanguageChoice> initializedChoices = [];
  final List<SpeechLanguage?> startedLanguages = [];

  List<SpeechLanguage> get initializedLanguages => [
        for (final choice in initializedChoices)
          if (choice.language != null) choice.language!,
      ];
  int maxConcurrentInitializations = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;

  StreamController<RecognitionResult>? _results;
  SpeechLanguage? _loadedLanguage;
  int _initializing = 0;

  bool get hasListener => _results?.hasListener ?? false;

  @override
  Future<void> initialize(SpeechLanguageChoice choice) async {
    initializedChoices.add(choice);
    _loadedLanguage = null;
    _initializing++;
    if (_initializing > maxConcurrentInitializations) {
      maxConcurrentInitializations = _initializing;
    }
    try {
      await initializeGate?.future;
      final error = initializeError;
      if (error != null) throw error;
      _loadedLanguage = choice.language;
    } finally {
      _initializing--;
    }
  }

  @override
  Stream<RecognitionResult> start() {
    startCalls++;
    startedLanguages.add(_loadedLanguage);
    _results = StreamController<RecognitionResult>(sync: true);
    return _results!.stream;
  }

  void emitPartial(String text) =>
      _results!.add(RecognitionResult(text: text, isFinal: false));

  void emitError(Object error) => _results!.addError(error);

  void emitLateFinal() => _results!.add(
        RecognitionResult(text: finalText, isFinal: true, lang: finalLang),
      );

  @override
  Future<String> stop() async {
    stopCalls++;
    final results = _results;
    await stopGate?.future;
    final error = stopError;
    if (error != null) throw error;
    if (finalBeforeStop && results != null && !results.isClosed) {
      results.add(
        RecognitionResult(text: finalText, isFinal: true, lang: finalLang),
      );
    }
    return finalText;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final results = _results;
    _results = null;
    unawaited(results?.close());
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
