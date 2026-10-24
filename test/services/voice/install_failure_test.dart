import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/install_failure.dart';

const _failures = <InstallFailure>[
  NetworkFailure(),
  FingerprintMismatch(),
  StorageFailure(),
  InstallCancelled(),
];

String _kind(InstallFailure failure) => switch (failure) {
      NetworkFailure() => 'network',
      FingerprintMismatch() => 'fingerprint',
      StorageFailure() => 'storage',
      InstallCancelled() => 'cancelled',
    };

void main() {
  test('an exhaustive switch covers every failure without a default', () {
    expect(_failures.map(_kind), [
      'network',
      'fingerprint',
      'storage',
      'cancelled',
    ]);
  });

  test('toString is the kind name and carries no text', () {
    expect(const StorageFailure().toString(), 'StorageFailure');
    expect(
      _failures.map((failure) => failure.toString()).toSet(),
      hasLength(4),
    );
  });
}
