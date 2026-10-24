import 'recognition_result.dart';
import 'speech_language.dart';
import 'speech_recognition_failure.dart';

/// An on-device speech recognition engine.
///
/// The lifecycle is [initialize] → [start] → [stop], repeatable for further
/// sessions, then [dispose] once. Implementations must not expose
/// engine-specific types through this interface; every engine error surfaces
/// as a [SpeechRecognitionFailure].
abstract interface class SpeechRecognition {
  /// Loads the model for [choice]; [SpeechLanguageChoice.auto] lets the engine
  /// guess the language per session. Must complete before [start] is called;
  /// calling it again switches choice.
  ///
  /// Throws [ModelNotInstalled] if no model for [choice] is on the device,
  /// or [EngineFailure] if the model cannot be loaded.
  Future<void> initialize(SpeechLanguageChoice choice);

  /// Begins a recognition session.
  ///
  /// The stream may emit any number of partial results (`isFinal` false)
  /// and emits at most one final result (`isFinal` true), after which it
  /// closes. Errors arrive on the stream as [EngineFailure], or as
  /// [AudioTooLong] when the session reaches the engine's length limit.
  ///
  /// Throws [StateError] if [initialize] has not completed, or if a session
  /// is already running.
  Stream<RecognitionResult> start();

  /// Ends the session and returns the final transcript, which may be empty.
  ///
  /// The returned text is exactly the text of the final result emitted on
  /// the [start] stream, so callers can use either without duplicating it.
  ///
  /// Throws [EngineFailure] if decoding fails, or [StateError] if no session
  /// was started.
  Future<String> stop();

  /// Ends the session without decoding: the [start] stream closes with no
  /// final result and the buffered audio is discarded. A new session can be
  /// started afterwards.
  ///
  /// Unlike [stop], does nothing and never throws when no session is running.
  Future<void> cancel();

  /// Releases the engine's native resources. The instance cannot be used
  /// afterwards. Never throws a [SpeechRecognitionFailure].
  Future<void> dispose();
}
