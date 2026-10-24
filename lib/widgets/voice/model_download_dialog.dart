import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/voice/model_installation_controller.dart';
import 'package:quill_fb2/services/voice/model_status.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/voice/voice_texts.dart';

/// Asks before a Model Download, then shows its progress. True when the
/// Speech Model is installed afterwards.
Future<bool> offerModelDownload(
  BuildContext context,
  AppService service,
  ModelInstallationController installation,
) async {
  if (installation.status is! Installing) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(service, 'Download the speech model?',
            'Загрузить речевую модель?')),
        content: Text(tr(
            service,
            'Dictation runs on this phone, so it needs a one-time download of about 375 MB. Wi-Fi is recommended. Nothing you say is ever sent anywhere.',
            'Диктовка работает прямо на телефоне, поэтому нужна разовая загрузка около 375 МБ. Лучше по Wi-Fi. Ничего из сказанного никуда не отправляется.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(service, 'Not now', 'Не сейчас'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(service, 'Download', 'Загрузить'))),
        ],
      ),
    );
    if (go != true || !context.mounted) return false;
    installation.startDownload();
  }
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ProgressDialog(service, installation),
  );
  return done == true;
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog(this.service, this.installation);

  final AppService service;
  final ModelInstallationController installation;

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: installation,
      builder: (ctx, _) {
        final status = installation.status;
        if (status is Installed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) Navigator.pop(ctx, true);
          });
        }
        final failed = status is InstallFailed;
        return AlertDialog(
          title: Text(tr(service, 'Speech model', 'Речевая модель')),
          content: switch (status) {
            Installing(:final receivedBytes, :final totalBytes) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                      value: totalBytes == 0 ? null : receivedBytes / totalBytes),
                  const SizedBox(height: 8),
                  Text('${_mb(receivedBytes)} / ${_mb(totalBytes)} MB'),
                ],
              ),
            InstallFailed(:final failure) =>
              Text(modelFailureText(service, failure)),
            _ => const LinearProgressIndicator(),
          },
          actions: [
            if (failed) ...[
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr(service, 'Close', 'Закрыть'))),
              FilledButton(
                  onPressed: installation.retry,
                  child: Text(tr(service, 'Try again', 'Повторить'))),
            ] else
              TextButton(
                  onPressed: () async {
                    await installation.cancel();
                    if (ctx.mounted) Navigator.pop(ctx, false);
                  },
                  child: Text(tr(service, 'Cancel', 'Отмена'))),
          ],
        );
      },
    );
  }
}
