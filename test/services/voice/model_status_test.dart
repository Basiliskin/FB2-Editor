import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/install_failure.dart';
import 'package:quill_fb2/services/voice/model_status.dart';

void main() {
  test('Installing has value equality', () {
    const a = Installing(receivedBytes: 1, totalBytes: 2);
    const b = Installing(receivedBytes: 1, totalBytes: 2);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const Installing(receivedBytes: 2, totalBytes: 2)));
    expect(a, isNot(const Installing(receivedBytes: 1, totalBytes: 3)));
  });

  test('InstallFailed compares by failure', () {
    expect(const InstallFailed(NetworkFailure()),
        const InstallFailed(NetworkFailure()));
    expect(const InstallFailed(NetworkFailure()).hashCode,
        const InstallFailed(NetworkFailure()).hashCode);
    expect(const InstallFailed(NetworkFailure()),
        isNot(const InstallFailed(StorageFailure())));
  });

  test('an exhaustive switch covers every status', () {
    String name(ModelStatus s) => switch (s) {
          Checking() => 'checking',
          NotInstalled() => 'not',
          Installing() => 'installing',
          Installed() => 'installed',
          InstallFailed() => 'failed',
        };
    expect(name(const Installed()), 'installed');
  });
}
