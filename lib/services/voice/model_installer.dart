import 'install_failure.dart';

/// Puts the Speech Model on the device.
abstract interface class ModelInstaller {
  /// Whether every Speech Model file is in place.
  Future<bool> isInstalled();

  /// Starts a Model Download. The stream reports the bytes received so far
  /// and ends once the Speech Model is installed. It fails with an
  /// [InstallFailure]; cancelling the subscription stops the transfer.
  Stream<int> download();
}
