import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/voice/dictation_limits.dart';
import 'package:quill_fb2/services/voice/dictation_target.dart';
import 'package:quill_fb2/services/voice/model_status.dart';
import 'package:quill_fb2/services/voice/recording_status.dart';
import 'package:quill_fb2/services/voice/speech_language.dart';
import 'package:quill_fb2/services/voice/voice_availability.dart';
import 'package:quill_fb2/services/voice/voice_input.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/voice/model_download_dialog.dart';
import 'package:quill_fb2/widgets/voice/voice_texts.dart';

/// The mic: tap to dictate into [target], tap again to stop. Absent unless
/// Voice input is switched on in Settings (and the phone is Android).
class DictationButton extends StatefulWidget {
  const DictationButton({
    super.key,
    required this.service,
    required this.target,
    this.choice = SpeechLanguageChoice.auto,
    this.onBusyChanged,
    this.onInserted,
    @visibleForTesting this.stopwatch,
  });

  final AppService service;
  final DictationTarget target;

  /// The Speech Language to start from, usually the book's.
  final SpeechLanguageChoice choice;

  /// Called with true while a Dictation is under way, so the owner can keep
  /// the text still until it lands.
  final ValueChanged<bool>? onBusyChanged;

  /// Called after the dictated words are in the target, for fields that do
  /// something with their text beyond showing it.
  final VoidCallback? onInserted;

  /// For tests: a clock that can be moved by hand.
  final Stopwatch? stopwatch;

  @override
  State<DictationButton> createState() => _DictationButtonState();
}

class _DictationButtonState extends State<DictationButton>
    with WidgetsBindingObserver {
  VoiceInput? _voice;
  DictationAnchor? _anchor;
  bool _awaiting = false;
  // Idle is also what the controller reports before a session starts, so a
  // session only counts as finished once it has been seen running.
  bool _seenActive = false;
  bool _busy = false;
  bool _disposed = false;
  Timer? _ticker;
  late final Stopwatch _stopwatch = widget.stopwatch ?? Stopwatch();

  bool get _enabled => voiceInputEnabled(widget.service.getSettings());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_enabled) unawaited(_attach());
  }

  Future<VoiceInput?> _attach() async {
    if (_voice != null) return _voice;
    try {
      final voice = await widget.service.voiceInput();
      if (_disposed) return null;
      _voice = voice..recording.addListener(_onRecordingChanged);
      return voice;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    final voice = _voice;
    if (voice != null) {
      voice.recording.removeListener(_onRecordingChanged);
      if (_awaiting) unawaited(voice.recording.cancel());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final recording = _voice?.recording;
    // Inactive also covers the notification shade and system dialogs, which
    // should not cost the user their recording.
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        _awaiting &&
        recording != null &&
        recording.status == RecordingStatus.recording) {
      _awaiting = false;
      unawaited(recording.cancel());
      _say(tr(widget.service, 'Recording stopped.', 'Запись остановлена.'));
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _setBusy(bool busy) {
    if (busy == _busy) return;
    _busy = busy;
    widget.onBusyChanged?.call(busy);
  }

  void _onRecordingChanged() {
    final recording = _voice!.recording;
    final status = recording.status;
    _setBusy(_awaiting &&
        status != RecordingStatus.idle &&
        status != RecordingStatus.error);

    if (status == RecordingStatus.recording) {
      if (!_stopwatch.isRunning) {
        _stopwatch
          ..reset()
          ..start();
        _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _ticker?.cancel();
      _stopwatch.stop();
    }

    if (_awaiting &&
        status != RecordingStatus.idle &&
        status != RecordingStatus.error) {
      _seenActive = true;
    }
    if (_awaiting && _seenActive && status == RecordingStatus.idle) {
      _awaiting = false;
      _setBusy(false);
      _land(recording.captureText, recording.hitLengthLimit);
    } else if (_awaiting && status == RecordingStatus.error) {
      _awaiting = false;
      _setBusy(false);
      final error = recording.error;
      if (error != null) _say(recordingErrorText(widget.service, error));
    }
    if (mounted) setState(() {});
  }

  void _land(String text, bool hitLimit) {
    final anchor = _anchor;
    if (text.trim().isEmpty || anchor == null) {
      _say(tr(widget.service, 'Nothing was heard.', 'Ничего не расслышал.'));
      return;
    }
    if (widget.target.insert(anchor, text)) widget.onInserted?.call();
    if (hitLimit) {
      _say(tr(
          widget.service,
          'That is as much as fits in one go. Tap the mic to carry on.',
          'Больше за один раз не помещается. Нажмите на микрофон, чтобы продолжить.'));
    }
  }

  Future<void> _tap() async {
    final voice = await _attach();
    if (voice == null) {
      _say(recordingFailedText());
      return;
    }
    final recording = voice.recording;
    switch (recording.status) {
      case RecordingStatus.recording:
        await recording.stop();
        return;
      case RecordingStatus.idle || RecordingStatus.error:
        break;
      default:
        return;
    }

    await voice.installation.refresh();
    if (!mounted) return;
    if (voice.installation.status is! Installed) {
      final installed =
          await offerModelDownload(context, widget.service, voice.installation);
      if (installed) {
        _say(tr(widget.service, 'Speech model ready. Tap the mic to dictate.',
            'Речевая модель готова. Нажмите на микрофон, чтобы диктовать.'));
      }
      return;
    }

    _anchor = widget.target.anchor();
    await recording.setChoice(widget.choice);
    _seenActive = false;
    _awaiting = true;
    await recording.record();
  }

  String recordingFailedText() => tr(widget.service,
      'Dictation is not available right now.', 'Диктовка сейчас недоступна.');

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final s = widget.service;
    final status = _voice?.recording.status ?? RecordingStatus.idle;

    // The recording is shared by every mic on the page; only the one that
    // started it shows what is happening, the others wait.
    final others = !_awaiting &&
        status != RecordingStatus.idle &&
        status != RecordingStatus.error;
    if (others) {
      return const IconButton(onPressed: null, icon: Icon(Icons.mic_none));
    }

    switch (status) {
      case RecordingStatus.requestingPermission ||
            RecordingStatus.loadingModel ||
            RecordingStatus.processing:
        return IconButton(
          tooltip: tr(s, 'Working…', 'Обработка…'),
          onPressed: null,
          icon: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case RecordingStatus.recording:
        final left = dictationMaxDuration - _stopwatch.elapsed;
        final counting = left <= dictationCountdown;
        return TextButton.icon(
          onPressed: _tap,
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error),
          icon: const Icon(Icons.stop_circle_outlined),
          label: Text(counting
              ? '${left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil()}'
              : tr(s, 'Stop', 'Стоп')),
        );
      case RecordingStatus.idle || RecordingStatus.error:
        return IconButton(
          tooltip: tr(s, 'Dictate', 'Диктовать'),
          onPressed: _tap,
          icon: const Icon(Icons.mic_none),
        );
    }
  }
}
