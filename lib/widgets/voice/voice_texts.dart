import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/voice/install_failure.dart';
import 'package:quill_fb2/services/voice/recording_error.dart';
import 'package:quill_fb2/ui/widgets.dart';

String modelFailureText(AppService s, InstallFailure failure) =>
    switch (failure) {
      NetworkFailure() => tr(
          s,
          'The download failed. Check the connection and try again.',
          'Загрузка не удалась. Проверьте соединение и попробуйте снова.'),
      FingerprintMismatch() => tr(
          s,
          'The downloaded file was damaged. Try again.',
          'Загруженный файл повреждён. Попробуйте снова.'),
      StorageFailure() => tr(
          s,
          'Not enough free space. About 400 MB is needed.',
          'Не хватает места. Нужно около 400 МБ.'),
      InstallCancelled() =>
        tr(s, 'The download was cancelled.', 'Загрузка отменена.'),
    };

String recordingErrorText(AppService s, RecordingError error) =>
    switch (error) {
      RecordingError.permissionDenied || RecordingError.permissionBlocked =>
        tr(
            s,
            'Dictation needs the microphone. Allow it for this app in the phone settings.',
            'Для диктовки нужен микрофон. Разрешите его для приложения в настройках телефона.'),
      RecordingError.modelMissing => tr(
          s,
          'The speech model is missing. Tap the mic to download it.',
          'Речевая модель не найдена. Нажмите на микрофон, чтобы загрузить её.'),
      RecordingError.engineFailed => tr(
          s,
          'Dictation failed. Try again.',
          'Диктовка не удалась. Попробуйте снова.'),
      RecordingError.audioTooLong => tr(
          s,
          'That was too long to transcribe. Try shorter pieces.',
          'Слишком длинная запись. Диктуйте короче.'),
    };
