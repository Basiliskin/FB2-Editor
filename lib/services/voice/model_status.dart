import 'install_failure.dart';

sealed class ModelStatus {
  const ModelStatus();
}

/// The app is looking at the device to see whether the Speech Model is there.
final class Checking extends ModelStatus {
  const Checking();
}

final class NotInstalled extends ModelStatus {
  const NotInstalled();
}

final class Installing extends ModelStatus {
  const Installing({required this.receivedBytes, required this.totalBytes});

  final int receivedBytes;
  final int totalBytes;

  @override
  bool operator ==(Object other) =>
      other is Installing &&
      other.receivedBytes == receivedBytes &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(receivedBytes, totalBytes);
}

final class Installed extends ModelStatus {
  const Installed();
}

final class InstallFailed extends ModelStatus {
  const InstallFailed(this.failure);

  final InstallFailure failure;

  @override
  bool operator ==(Object other) =>
      other is InstallFailed && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;
}
