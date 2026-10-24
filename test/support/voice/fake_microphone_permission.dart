import 'dart:async';

import 'package:quill_fb2/services/voice/microphone_permission.dart';

class FakeMicrophonePermission implements MicrophonePermission {
  FakeMicrophonePermission([this.result = MicrophonePermissionResult.granted]);

  MicrophonePermissionResult result;

  /// When set, [request] waits for the test to complete it.
  Completer<MicrophonePermissionResult>? gate;

  int requestCalls = 0;

  @override
  Future<MicrophonePermissionResult> request() {
    requestCalls++;
    return gate?.future ?? Future.value(result);
  }
}
