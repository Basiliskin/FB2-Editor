import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'audio_capture.dart';
import 'file_system_model_installer.dart';
import 'model_installation_controller.dart';
import 'recording_controller.dart';
import 'sherpa_onnx_speech_recognition.dart';
import 'voice_input.dart';
import 'whisper_model_files.dart';

/// The real thing: Whisper on the phone, the microphone, and the model folder
/// in the app's private storage.
Future<VoiceInput> createDeviceVoiceInput() async {
  final support = await getApplicationSupportDirectory();
  final modelDirectory = Directory('${support.path}/speech_model');
  final capture = MicrophoneCapture();
  final engine = SherpaOnnxSpeechRecognition(
    modelFiles: (language) async =>
        WhisperModelFiles.inDirectory(modelDirectory.path, language),
    audioSource: capture.chunks,
  );
  return VoiceInput(
    installation: ModelInstallationController(
      installer: FileSystemModelInstaller(modelDirectory: modelDirectory),
    ),
    recording: RecordingController(engine: engine, permission: capture),
  );
}
