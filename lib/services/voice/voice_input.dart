import 'model_installation_controller.dart';
import 'recording_controller.dart';

/// What the mic buttons share: whether the Speech Model is installed, and the
/// one Recording that is running. There is one of these per app.
class VoiceInput {
  VoiceInput({required this.installation, required this.recording});

  final ModelInstallationController installation;
  final RecordingController recording;

  void dispose() {
    installation.dispose();
    recording.dispose();
  }
}
