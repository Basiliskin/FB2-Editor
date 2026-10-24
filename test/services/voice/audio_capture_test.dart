import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/audio_capture.dart';
import 'package:quill_fb2/services/voice/microphone_permission.dart';

class FakePcmRecorder implements PcmRecorder {
  bool permission = true;
  int permissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int? lastSampleRate;
  StreamController<Uint8List>? bytes;

  @override
  Future<bool> hasPermission() async {
    permissionCalls++;
    return permission;
  }

  @override
  Future<Stream<Uint8List>> startPcm16Stream({
    required int sampleRate,
    required int bufferBytes,
  }) async {
    startCalls++;
    lastSampleRate = sampleRate;
    bytes = StreamController<Uint8List>();
    return bytes!.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await bytes?.close();
  }
}

Uint8List le(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('pcm16ToFloat32', () {
    test('empty input gives no samples', () {
      expect(pcm16ToFloat32(Uint8List(0)), isEmpty);
    });

    test('silence', () {
      expect(pcm16ToFloat32(Uint8List(8)), everyElement(0.0));
    });

    test('full-scale positive', () {
      expect(pcm16ToFloat32(le([0xFF, 0x7F])).single, 32767 / 32768);
    });

    test('full-scale negative is exactly -1', () {
      expect(pcm16ToFloat32(le([0x00, 0x80])).single, -1.0);
    });

    test('reads little-endian byte order', () {
      expect(pcm16ToFloat32(le([0x01, 0x80])).single, -32767 / 32768);
      expect(pcm16ToFloat32(le([0x00, 0x01])).single, 256 / 32768);
    });

    test('odd-length input drops the trailing byte', () {
      final samples = pcm16ToFloat32(le([0x00, 0x40, 0x7F]));
      expect(samples, [0.5]);
    });
  });

  group('MicrophoneCapture.request', () {
    test('maps granted and denied; never permanentlyDenied', () async {
      final recorder = FakePcmRecorder();
      final capture = MicrophoneCapture(recorderFactory: () => recorder);

      expect(await capture.request(), MicrophonePermissionResult.granted);
      recorder.permission = false;
      expect(await capture.request(), MicrophonePermissionResult.denied);
      expect(recorder.permissionCalls, 2);
      expect(recorder.startCalls, 0);
    });

    test('the constructor touches no recorder', () {
      var created = 0;
      MicrophoneCapture(
        recorderFactory: () {
          created++;
          return FakePcmRecorder();
        },
      );
      expect(created, 0);
    });
  });

  group('MicrophoneCapture.chunks', () {
    late FakePcmRecorder recorder;
    late MicrophoneCapture capture;

    setUp(() {
      recorder = FakePcmRecorder();
      capture = MicrophoneCapture(recorderFactory: () => recorder);
    });

    test('starts at 16 kHz and converts each buffer', () async {
      final received = <Float32List>[];
      final sub = capture.chunks().listen(received.add);
      await pumpEventQueue();
      recorder.bytes!.add(le([0x00, 0x80, 0x00, 0x40]));
      await pumpEventQueue();

      expect(recorder.lastSampleRate, 16000);
      expect(received.single, [-1.0, 0.5]);
      await sub.cancel();
    });

    test('carries an odd trailing byte into the next buffer', () async {
      final received = <double>[];
      final sub = capture.chunks().listen(received.addAll);
      await pumpEventQueue();
      recorder.bytes!.add(le([0x00, 0x40, 0x00]));
      recorder.bytes!.add(le([0x80, 0x00, 0x40]));
      await pumpEventQueue();

      expect(received, [0.5, -1.0, 0.5]);
      await sub.cancel();
    });

    test('cancelling mid-stream stops the recorder once', () async {
      final sub = capture.chunks().listen((_) {});
      await pumpEventQueue();
      recorder.bytes!.add(le([0, 0]));
      await sub.cancel();
      await pumpEventQueue();

      expect(recorder.stopCalls, 1);
    });

    test('cancelling before the recorder starts stops it once', () async {
      final sub = capture.chunks().listen((_) {});
      await sub.cancel();
      await pumpEventQueue();

      expect(recorder.startCalls, 1);
      expect(recorder.stopCalls, 1);
    });

    test('a plugin error is forwarded and stops the recorder once', () async {
      final errors = <Object>[];
      final done = Completer<void>();
      final sub = capture.chunks().listen(
        (_) {},
        onError: errors.add,
        onDone: done.complete,
      );
      await pumpEventQueue();
      recorder.bytes!.addError(StateError('mic lost'));
      await done.future;
      await sub.cancel();

      expect(errors.single, isA<StateError>());
      expect(recorder.stopCalls, 1);
    });

    test('a second recording after cancel gets a fresh stream', () async {
      await capture.chunks().listen((_) {}).cancel();
      await pumpEventQueue();
      final received = <Float32List>[];
      final sub = capture.chunks().listen(received.add);
      await pumpEventQueue();
      recorder.bytes!.add(le([0, 0]));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(recorder.startCalls, 2);
      await sub.cancel();
      expect(recorder.stopCalls, 2);
    });
  });
}
