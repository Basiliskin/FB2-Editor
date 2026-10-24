import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'microphone_permission.dart';

const int captureSampleRate = 16000;

const int _bytesPerChunk = captureSampleRate ~/ 10 * 2;

/// Converts little-endian signed 16-bit PCM to samples in [-1, 1].
///
/// Divides by 32768, so -32768 maps to exactly -1.0 and 32767 to just under
/// 1.0. A trailing odd byte is dropped; [MicrophoneCapture.chunks] carries it
/// into the next buffer instead.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final samples = Float32List(bytes.length ~/ 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
  }
  return samples;
}

/// The slice of the audio plugin that [MicrophoneCapture] uses.
abstract interface class PcmRecorder {
  /// Checks the permission, prompting the user when it is not yet decided.
  Future<bool> hasPermission();

  /// Starts mono 16-bit PCM capture at [sampleRate].
  Future<Stream<Uint8List>> startPcm16Stream({
    required int sampleRate,
    required int bufferBytes,
  });

  Future<void> stop();
}

class _PluginPcmRecorder implements PcmRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startPcm16Stream({
    required int sampleRate,
    required int bufferBytes,
  }) {
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        streamBufferSize: bufferBytes,
      ),
    );
  }

  @override
  Future<void> stop() => _recorder.stop();
}

/// Live microphone input: permission at the point of use and 16 kHz mono
/// samples in roughly 100 ms chunks.
class MicrophoneCapture implements MicrophonePermission {
  MicrophoneCapture({PcmRecorder Function()? recorderFactory})
    : _recorderFactory = recorderFactory ?? _PluginPcmRecorder.new;

  final PcmRecorder Function() _recorderFactory;
  PcmRecorder? _recorderInstance;

  PcmRecorder get _recorder => _recorderInstance ??= _recorderFactory();

  /// The plugin cannot tell a permanent denial from a plain one, so
  /// [MicrophonePermissionResult.permanentlyDenied] is never returned.
  @override
  Future<MicrophonePermissionResult> request() async {
    final granted = await _recorder.hasPermission();
    return granted
        ? MicrophonePermissionResult.granted
        : MicrophonePermissionResult.denied;
  }

  /// A new single-subscription stream per call. Listening starts the
  /// recorder; cancelling, or an error from the plugin, stops it.
  Stream<Float32List> chunks() {
    final recorder = _recorder;
    StreamSubscription<Uint8List>? source;
    var stopped = false;
    int? carriedByte;
    late final StreamController<Float32List> controller;

    Future<void> stopOnce() async {
      if (stopped) return;
      stopped = true;
      final started = source;
      if (started == null) return;
      await started.cancel();
      await recorder.stop();
    }

    void onBytes(Uint8List bytes) {
      var buffer = bytes;
      if (carriedByte != null) {
        buffer = Uint8List(bytes.length + 1)
          ..[0] = carriedByte!
          ..setRange(1, bytes.length + 1, bytes);
        carriedByte = null;
      }
      if (buffer.length.isOdd) carriedByte = buffer.last;
      controller.add(pcm16ToFloat32(buffer));
    }

    controller = StreamController<Float32List>(
      onListen: () async {
        try {
          final bytes = await recorder.startPcm16Stream(
            sampleRate: captureSampleRate,
            bufferBytes: _bytesPerChunk,
          );
          if (stopped) {
            await recorder.stop();
            return;
          }
          source = bytes.listen(
            onBytes,
            onError: (Object error, StackTrace stackTrace) async {
              controller.addError(error, stackTrace);
              await stopOnce();
              await controller.close();
            },
            onDone: () async {
              await stopOnce();
              await controller.close();
            },
          );
        } catch (error, stackTrace) {
          stopped = true;
          controller.addError(error, stackTrace);
          await controller.close();
        }
      },
      onCancel: stopOnce,
    );
    return controller.stream;
  }
}
