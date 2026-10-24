import 'package:flutter/material.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';

/// Called before leaving a screen that edits [book]. Saves silently when
/// auto-save is on, otherwise asks. Returns false when the user chose to stay.
/// [onDiscard] runs when the user chose not to save, to undo the edits in memory.
Future<bool> confirmLeave(
    BuildContext context, AppService service, ProjectModel book,
    {VoidCallback? onDiscard}) async {
  final autoSave = stringToBool(service.getSettings()["auto-save"]) ?? false;
  if (autoSave) {
    await service.saveProject(book);
    return true;
  }
  if (!service.hasUnsavedChanges(book)) return true;
  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${service.translate(LangTranslateItems.unsavedTitle)}'),
      content: Text('${service.translate(LangTranslateItems.unsavedBody)}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('${service.translate(LangTranslateItems.buttonCancel)}')),
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('${service.translate(LangTranslateItems.buttonDiscard)}')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('${service.translate(LangTranslateItems.buttonSave)}')),
      ],
    ),
  );
  if (choice == null) return false; // dismissed or Cancel: stay
  if (choice) {
    await service.saveProject(book);
  } else {
    onDiscard?.call();
  }
  return true;
}

/// Snackbar text after an export; null when the user cancelled the dialog.
String? exportedMessage(AppService service, ProjectModel book, String? path) =>
    path == null
        ? null
        : '${book.bookTitle} ${service.translate(LangTranslateItems.messageExported)}\n$path';
