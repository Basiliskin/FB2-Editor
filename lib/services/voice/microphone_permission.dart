enum MicrophonePermissionResult { granted, denied, permanentlyDenied }

/// Asks the platform for microphone access.
abstract interface class MicrophonePermission {
  /// Requests access at the point of use, when the user taps the mic. Never
  /// call it at app start.
  Future<MicrophonePermissionResult> request();
}
