import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dictation_text.dart';
import 'microphone_permission.dart';
import 'recognition_result.dart';
import 'recording_error.dart';
import 'recording_status.dart';
import 'speech_language.dart';
import 'speech_recognition.dart';
import 'speech_recognition_failure.dart';

enum _Command { record, stop }

enum WarmUpState { idle, warmingUp, ready }

class _ModelLoad {
  _ModelLoad(this.choice) {
    settled = _done.future.then<void>((_) {}, onError: (Object _) {});
  }

  final SpeechLanguageChoice choice;
  final _done = Completer<void>();
  late final Future<void> settled;
  bool _failed = false;

  Future<void> get done => _done.future;
  bool get failed => _failed;

  void succeed() => _done.complete();

  void fail(Object error, StackTrace stackTrace) {
    _failed = true;
    _done.completeError(error, stackTrace);
  }
}

/// Runs one Recording session at a time through a small state machine. Error messages are fixed strings so no transcript or engine
/// detail can leak into the UI or a log.
class RecordingController extends ChangeNotifier {
  RecordingController({
    required SpeechRecognition engine,
    required MicrophonePermission permission,
    Duration debounce = const Duration(milliseconds: 300),
    DateTime Function()? clock,
  })  : _engine = engine,
        _permission = permission,
        _debounce = debounce,
        _clock = clock ?? DateTime.now;

  final SpeechRecognition _engine;
  final MicrophonePermission _permission;
  final Duration _debounce;
  final DateTime Function() _clock;

  final Map<_Command, DateTime> _lastTap = {};
  RecordingStatus _status = RecordingStatus.idle;
  SpeechLanguageChoice _choice = const SpeechLanguageChoice.of(
    SpeechLanguage.russian,
  );
  SpeechLanguage _fallback = SpeechLanguage.russian;
  SpeechLanguage? _detectedLanguage;
  _ModelLoad? _modelLoad;
  WarmUpState _warmUpState = WarmUpState.idle;
  String _transcriptText = '';
  String _sessionStartTranscript = '';
  String _captureText = '';
  String? _partialPreview;
  RecordingError? _error;
  bool _hitLengthLimit = false;

  StreamSubscription<RecognitionResult>? _subscription;
  int _session = 0;
  bool _finalApplied = false;
  bool _disposed = false;

  RecordingStatus get status => _status;
  SpeechLanguageChoice get choice => _choice;

  /// The concrete language of the current choice, or the fallback under Auto.
  SpeechLanguage get language => _choice.language ?? _fallback;

  /// The language of the last finished Recording under Auto, resolved to
  /// ru/he/en; null before one finishes and when the Recording failed.
  SpeechLanguage? get detectedLanguage => _detectedLanguage;
  String get transcriptText => _transcriptText;

  /// The final text of the most recent session only, without the editor's
  /// earlier text and never a partial.
  String get captureText => _captureText;
  String? get partialPreview => _partialPreview;
  RecordingError? get error => _error;

  /// Whether the last session stopped itself at the engine's length limit.
  /// Its text was still applied.
  bool get hitLengthLimit => _hitLengthLimit;
  WarmUpState get warmUpState => _warmUpState;

  set transcriptText(String text) {
    if (text == _transcriptText) return;
    _transcriptText = text;
    _notify();
  }

  /// Loads the model for [language] ahead of the first recording. A failure
  /// only returns [warmUpState] to idle; record() reports it if it recurs.
  /// Ignored for another language while a session is running, because loading
  /// replaces the model the session is using.
  Future<void> warmUp(SpeechLanguage language) =>
      warmUpChoice(SpeechLanguageChoice.of(language));

  Future<void> warmUpChoice(SpeechLanguageChoice choice) {
    if (_disposed) return Future.value();
    final sessionRunning =
        _status != RecordingStatus.idle && _status != RecordingStatus.error;
    if (sessionRunning && _modelLoad?.choice != choice) {
      return Future.value();
    }
    return _loadModel(choice).settled;
  }

  /// The language reported when the engine's guess is not ru/he/en.
  void setFallbackLanguage(SpeechLanguage language) {
    _fallback = language;
  }

  Future<void> record() async {
    if (_disposed || _isDebounced(_Command.record)) return;
    if (_status == RecordingStatus.error) _recoverToIdle();
    if (_status != RecordingStatus.idle) return;

    final session = ++_session;
    final choice = _choice;
    _detectedLanguage = null;
    _sessionStartTranscript = _transcriptText;
    _captureText = '';
    _error = null;
    _hitLengthLimit = false;
    _setStatus(RecordingStatus.requestingPermission);

    final permission = await _permission.request();
    if (session != _session) return;
    switch (permission) {
      case MicrophonePermissionResult.granted:
        break;
      case MicrophonePermissionResult.denied:
        return _fail(RecordingError.permissionDenied);
      case MicrophonePermissionResult.permanentlyDenied:
        return _fail(RecordingError.permissionBlocked);
    }

    _setStatus(RecordingStatus.loadingModel);
    if (!_isLoaded(choice)) {
      try {
        await _loadModel(choice).done;
      } on ModelNotInstalled {
        if (session == _session) _fail(RecordingError.modelMissing);
        return;
      } catch (_) {
        if (session == _session) _fail(RecordingError.engineFailed);
        return;
      }
      if (session != _session) return;
    }

    _finalApplied = false;
    try {
      _subscription = _engine.start().listen(
        _onResult,
        onError: (Object error) => _onStreamError(error, session),
      );
    } catch (_) {
      return _fail(RecordingError.engineFailed);
    }
    _setStatus(RecordingStatus.recording);
  }

  Future<void> stop() async {
    if (_disposed || _isDebounced(_Command.stop)) return;
    if (_status != RecordingStatus.recording) return;
    await _finishSession(_session);
  }

  Future<void> setLanguage(SpeechLanguage language) =>
      setChoice(SpeechLanguageChoice.of(language));

  Future<void> setChoice(SpeechLanguageChoice choice) async {
    if (_disposed) return;
    if (_status == RecordingStatus.error) _recoverToIdle();
    final wasRecording = _status == RecordingStatus.recording;
    _choice = choice;
    _notify();
    if (wasRecording) await _finishSession(_session);
  }

  Future<void> onInterrupted() async {
    if (_disposed) return;
    switch (_status) {
      case RecordingStatus.recording:
        await _finishSession(_session);
      case RecordingStatus.requestingPermission || RecordingStatus.loadingModel:
        _session++;
        _setStatus(RecordingStatus.idle);
      case RecordingStatus.idle ||
          RecordingStatus.processing ||
          RecordingStatus.error:
        break;
    }
  }

  /// Throws the running session away: nothing it heard is applied, and the
  /// transcript returns to what it was when the session started.
  Future<void> cancel() async {
    if (_disposed) return;
    switch (_status) {
      case RecordingStatus.recording:
        _discardSession();
        await _engine.cancel();
      case RecordingStatus.requestingPermission ||
          RecordingStatus.loadingModel ||
          RecordingStatus.processing:
        _discardSession();
      case RecordingStatus.idle || RecordingStatus.error:
        break;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_engine.dispose());
    super.dispose();
  }

  bool _isLoaded(SpeechLanguageChoice choice) =>
      _modelLoad?.choice == choice && _warmUpState == WarmUpState.ready;

  /// Shares one load per choice and starts a load for another choice
  /// only after the previous one settles, because each initialize replaces
  /// the model in the decoder.
  _ModelLoad _loadModel(SpeechLanguageChoice choice) {
    final previous = _modelLoad;
    if (previous != null && previous.choice == choice && !previous.failed) {
      return previous;
    }
    final load = _ModelLoad(choice);
    _modelLoad = load;
    _setWarmUpState(WarmUpState.warmingUp);
    unawaited(_runLoad(load, previous));
    return load;
  }

  Future<void> _runLoad(_ModelLoad load, _ModelLoad? previous) async {
    await previous?.settled;
    try {
      await _engine.initialize(load.choice);
    } catch (error, stackTrace) {
      load.fail(error, stackTrace);
      if (identical(_modelLoad, load)) _setWarmUpState(WarmUpState.idle);
      return;
    }
    if (identical(_modelLoad, load)) _setWarmUpState(WarmUpState.ready);
    load.succeed();
  }

  void _setWarmUpState(WarmUpState state) {
    if (state == _warmUpState) return;
    _warmUpState = state;
    _notify();
  }

  bool _isDebounced(_Command command) {
    final now = _clock();
    final last = _lastTap[command];
    if (last != null && now.difference(last) < _debounce) return true;
    _lastTap[command] = now;
    return false;
  }

  void _onResult(RecognitionResult result) {
    if (result.isFinal) {
      _applyFinal(result.text, lang: result.lang);
    } else if (!_finalApplied) {
      _partialPreview = result.text;
      _notify();
    }
  }

  void _onStreamError(Object error, int session) {
    if (session != _session || _status != RecordingStatus.recording) return;
    if (error is AudioTooLong) {
      _hitLengthLimit = true;
      unawaited(_finishSession(session, afterAudioTooLong: true));
    } else {
      unawaited(_subscription?.cancel());
      _subscription = null;
      unawaited(_engine.stop().then<void>((_) {}, onError: (Object _) {}));
      _fail(RecordingError.engineFailed);
    }
  }

  Future<void> _finishSession(
    int session, {
    bool afterAudioTooLong = false,
  }) async {
    _setStatus(RecordingStatus.processing);
    final String text;
    try {
      text = await _engine.stop();
    } on AudioTooLong {
      if (session == _session) _fail(RecordingError.audioTooLong);
      return;
    } catch (_) {
      if (session == _session) {
        _fail(
          afterAudioTooLong
              ? RecordingError.audioTooLong
              : RecordingError.engineFailed,
        );
      }
      return;
    }
    // stop() hands over the text before the stream delivers the final result
    // that carries the detected language; let that result land first.
    await Future<void>.delayed(Duration.zero);
    if (session != _session) return;

    _applyFinal(text);
    await _endSession();
    _setStatus(RecordingStatus.idle);
  }

  void _applyFinal(String text, {String? lang}) {
    if (_finalApplied) return;
    _finalApplied = true;
    _detectedLanguage = resolveDetectedLanguage(lang, _fallback);
    _partialPreview = null;
    final finalText = stripSoundLabels(text);
    _captureText = finalText;
    if (finalText.isNotEmpty) {
      final current = _transcriptText;
      final needsSeparator =
          current.trim().isNotEmpty && current.trimRight() == current;
      _transcriptText = needsSeparator
          ? '$current $finalText'
          : '$current$finalText';
    }
    _notify();
  }

  Future<void> _endSession() async {
    final subscription = _subscription;
    _subscription = null;
    _partialPreview = null;
    await subscription?.cancel();
  }

  void _discardSession() {
    _session++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _partialPreview = null;
    _captureText = '';
    _transcriptText = _sessionStartTranscript;
    _setStatus(RecordingStatus.idle);
  }

  void _fail(RecordingError error) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _partialPreview = null;
    _error = error;
    _setStatus(RecordingStatus.error);
  }

  void _recoverToIdle() {
    _error = null;
    _setStatus(RecordingStatus.idle);
  }

  void _setStatus(RecordingStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
