import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// Asks before a running AI request is thrown away. True when the user chose to stop it.
Future<bool> confirmStopRun(BuildContext context, AppService s) async {
  final stop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
            title: Text(tr(s, 'Stop the running request?', 'Остановить запрос?')),
            content: Text(tr(
                s,
                'The AI is still working. If you leave now, what it has not finished is lost.',
                'ИИ ещё работает. Если уйти сейчас, незавершённое будет потеряно.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(s, 'Keep waiting', 'Подождать'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(s, 'Stop', 'Остановить'))),
            ],
          ));
  return stop == true;
}
