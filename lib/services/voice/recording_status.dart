enum RecordingStatus {
  /// No Recording session is running; the user can tap Record.
  idle,

  /// Record was tapped and the microphone permission prompt is pending.
  requestingPermission,

  /// Permission was granted and the Speech model is loading.
  loadingModel,

  /// The microphone is capturing audio for the Recording session.
  recording,

  /// Capture has ended and the engine is decoding the final transcript.
  processing,

  /// The Recording session failed; the next command returns to [idle].
  error,
}
