/// Why a Model Download did not finish. A failure carries no
/// text and never names a URL, path or file; the app maps each kind to its
/// message.
sealed class InstallFailure implements Exception {
  const InstallFailure();

  @override
  String toString() => runtimeType.toString();
}

final class NetworkFailure extends InstallFailure {
  const NetworkFailure();
}

final class FingerprintMismatch extends InstallFailure {
  const FingerprintMismatch();
}

final class StorageFailure extends InstallFailure {
  const StorageFailure();
}

final class InstallCancelled extends InstallFailure {
  const InstallCancelled();
}
