import 'package:flutter/foundation.dart';

/// Voice input runs the Speech Model on the phone, so it is Android only.
bool get voiceInputSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Whether Dictation is on: supported here and switched on in Settings.
bool voiceInputEnabled(Map settings) {
  final raw = settings['voice-input'];
  return voiceInputSupported && (raw == true || raw == 'true');
}
