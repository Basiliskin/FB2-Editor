import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/model_installation_controller.dart';
import 'package:quill_fb2/services/voice/install_failure.dart';
import 'package:quill_fb2/services/voice/model_status.dart';
import 'package:quill_fb2/services/voice/speech_model_files.dart';

import '../../support/voice/fake_model_installer.dart';

const _total = SpeechModelFile.totalBytes;

void main() {
  late FakeModelInstaller installer;
  late ModelInstallationController controller;
  late List<ModelStatus> notified;

  setUp(() {
    installer = FakeModelInstaller();
    controller = ModelInstallationController(installer: installer);
    notified = [];
    controller.addListener(() => notified.add(controller.status));
  });

  tearDown(() => controller.dispose());

  group('refresh', () {
    test('starts in Checking before anything is known', () {
      expect(controller.status, const Checking());
    });

    test('ends in NotInstalled when the files are missing', () async {
      installer.isInstalledGate = Completer<void>();

      final refreshing = controller.refresh();
      expect(controller.status, const Checking());

      installer.isInstalledGate!.complete();
      await refreshing;

      expect(controller.status, const NotInstalled());
      expect(notified, [const Checking(), const NotInstalled()]);
    });

    test('ends in Installed when the files are present', () async {
      installer.installed = true;

      await controller.refresh();

      expect(controller.status, const Installed());
      expect(notified, [const Checking(), const Installed()]);
    });

    test('does nothing while a Model Download is running', () async {
      controller.startDownload();
      notified.clear();

      await controller.refresh();

      expect(installer.isInstalledCalls, 0);
      expect(notified, isEmpty);
      expect(
        controller.status,
        const Installing(receivedBytes: 0, totalBytes: _total),
      );
    });

    test('a download started during the check wins over its result', () async {
      installer.isInstalledGate = Completer<void>();
      final refreshing = controller.refresh();

      controller.startDownload();
      installer.isInstalledGate!.complete();
      await refreshing;

      expect(controller.status, isA<Installing>());
    });
  });

  group('startDownload', () {
    test(
      'reports progress against the Speech Model total, then Installed',
      () async {
        controller.startDownload();
        installer.emitProgress(1000);
        installer.emitProgress(_total);
        await installer.finish();

        expect(notified, [
          const Installing(receivedBytes: 0, totalBytes: _total),
          const Installing(receivedBytes: 1000, totalBytes: _total),
          const Installing(receivedBytes: _total, totalBytes: _total),
          const Installed(),
        ]);
      },
    );

    test('runs one Model Download at a time', () async {
      controller.startDownload();
      installer.emitProgress(500);
      controller.startDownload();

      expect(installer.downloadCalls, 1);
      expect(
        controller.status,
        const Installing(receivedBytes: 500, totalBytes: _total),
      );

      await installer.finish();
      expect(controller.status, const Installed());
    });

    test('does nothing once the Speech Model is installed', () async {
      installer.installed = true;
      await controller.refresh();

      controller.startDownload();

      expect(installer.downloadCalls, 0);
      expect(controller.status, const Installed());
    });

    test(
      'ends in InstallFailed with the failure the installer raised',
      () async {
        controller.startDownload();
        installer.fail(const FingerprintMismatch());
        await pumpEventQueue();

        expect(controller.status, const InstallFailed(FingerprintMismatch()));
        expect(installer.isTransferring, isFalse);
      },
    );

    test('treats an unexpected error as a network failure', () async {
      controller.startDownload();
      installer.fail(StateError('socket closed'));
      await pumpEventQueue();

      expect(controller.status, const InstallFailed(NetworkFailure()));
    });
  });

  group('cancel', () {
    test('stops the transfer and ends in InstallFailed(cancelled)', () async {
      controller.startDownload();
      installer.emitProgress(42);
      expect(installer.isTransferring, isTrue);

      await controller.cancel();

      expect(installer.isTransferring, isFalse);
      expect(controller.status, const InstallFailed(InstallCancelled()));
      expect(notified.last, const InstallFailed(InstallCancelled()));
    });

    test('does nothing when no Model Download is running', () async {
      await controller.cancel();

      expect(controller.status, const Checking());
      expect(notified, isEmpty);
    });

    test('allows a new Model Download afterwards', () async {
      controller.startDownload();
      await controller.cancel();

      controller.startDownload();

      expect(installer.downloadCalls, 2);
      expect(controller.status, isA<Installing>());
    });
  });

  group('retry', () {
    test(
      'starts a new Model Download after a failure and can finish',
      () async {
        controller.startDownload();
        installer.fail(const NetworkFailure());
        await pumpEventQueue();
        notified.clear();

        controller.retry();
        installer.emitProgress(7);
        await installer.finish();

        expect(installer.downloadCalls, 2);
        expect(notified, [
          const Installing(receivedBytes: 0, totalBytes: _total),
          const Installing(receivedBytes: 7, totalBytes: _total),
          const Installed(),
        ]);
      },
    );

    test('does nothing unless the last Model Download failed', () async {
      await controller.refresh();

      controller.retry();

      expect(installer.downloadCalls, 0);
      expect(controller.status, const NotInstalled());
    });
  });

  test('dispose stops a running Model Download', () {
    final installer = FakeModelInstaller();
    ModelInstallationController(installer: installer)
      ..startDownload()
      ..dispose();

    expect(installer.isTransferring, isFalse);
  });
}
