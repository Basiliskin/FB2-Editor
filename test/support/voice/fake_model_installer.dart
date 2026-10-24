import 'dart:async';

import 'package:quill_fb2/services/voice/model_installer.dart';

class FakeModelInstaller implements ModelInstaller {
  bool installed = false;

  /// When set, [isInstalled] waits for the test to complete it.
  Completer<void>? isInstalledGate;

  int isInstalledCalls = 0;
  int downloadCalls = 0;

  StreamController<int>? _progress;

  /// True while a Model Download has a listener that has not cancelled it.
  bool get isTransferring => _progress?.hasListener ?? false;

  @override
  Future<bool> isInstalled() async {
    isInstalledCalls++;
    await isInstalledGate?.future;
    return installed;
  }

  @override
  Stream<int> download() {
    downloadCalls++;
    _progress = StreamController<int>(sync: true);
    return _progress!.stream;
  }

  void emitProgress(int receivedBytes) => _progress!.add(receivedBytes);

  void fail(Object error) => _progress!.addError(error);

  Future<void> finish() {
    installed = true;
    return _progress!.close();
  }
}
