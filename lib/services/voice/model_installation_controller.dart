import 'dart:async';

import 'package:flutter/foundation.dart';

import 'install_failure.dart';
import 'model_installer.dart';
import 'model_status.dart';
import 'speech_model_files.dart';

/// Tells the app whether the Speech Model is installed and runs one Model
/// Download at a time.
class ModelInstallationController extends ChangeNotifier {
  ModelInstallationController({required ModelInstaller installer})
      : _installer = installer;

  final ModelInstaller _installer;

  ModelStatus _status = const Checking();
  StreamSubscription<int>? _transfer;
  bool _disposed = false;

  ModelStatus get status => _status;

  Future<void> refresh() async {
    if (_disposed || _transfer != null) return;
    _setStatus(const Checking());
    final installed = await _installer.isInstalled();
    if (_disposed || _transfer != null) return;
    _setStatus(installed ? const Installed() : const NotInstalled());
  }

  void startDownload() {
    if (_disposed || _transfer != null || _status is Installed) return;
    _setStatus(
      const Installing(
        receivedBytes: 0,
        totalBytes: SpeechModelFile.totalBytes,
      ),
    );
    _transfer = _installer.download().listen(
      (receivedBytes) => _setStatus(
        Installing(
          receivedBytes: receivedBytes,
          totalBytes: SpeechModelFile.totalBytes,
        ),
      ),
      onError: (Object error) {
        _transfer = null;
        _setStatus(
          InstallFailed(
            error is InstallFailure ? error : const NetworkFailure(),
          ),
        );
      },
      onDone: () {
        _transfer = null;
        _setStatus(const Installed());
      },
      cancelOnError: true,
    );
  }

  Future<void> cancel() async {
    final transfer = _transfer;
    if (transfer == null) return;
    _transfer = null;
    _setStatus(const InstallFailed(InstallCancelled()));
    await transfer.cancel();
  }

  void retry() {
    if (_status is! InstallFailed) return;
    startDownload();
  }

  void _setStatus(ModelStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_transfer?.cancel());
    _transfer = null;
    super.dispose();
  }
}
