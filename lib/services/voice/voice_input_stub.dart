import 'voice_input.dart';

/// Voice input is Android only; the mic is never offered where this runs.
Future<VoiceInput> createDeviceVoiceInput() =>
    Future.error(UnsupportedError('Voice input needs the Android app'));
