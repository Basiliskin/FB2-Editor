import 'package:flutter/material.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// The one place to keep a book in the app or write it out as a file:
/// its saved state, "Save in the app", and one tile per export format
/// with the file name it will get.
Future<void> showSaveExportSheet(
  BuildContext context,
  AppService service,
  ProjectModel book, {
  required VoidCallback onSave,
  required VoidCallback onExportFb2,
  required VoidCallback onExportEpub,
  required VoidCallback onExportTxt,
}) {
  final s = service;
  final unsaved = s.hasUnsavedChanges(book);
  final name = book.exportBaseName;

  Widget status() {
    final color = unsaved ? Colors.orange.shade800 : Colors.green.shade700;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(unsaved ? Icons.circle : Icons.check_circle, size: 12, color: color),
      const SizedBox(width: 6),
      Text(
          unsaved
              ? tr(s, 'Unsaved changes', 'Есть несохранённые изменения')
              : tr(s, 'Saved in the app', 'Сохранено в приложении'),
          style: TextStyle(color: color, fontSize: 13)),
    ]);
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      Widget tile(IconData icon, String title, String subtitle, VoidCallback run) =>
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            onTap: () {
              Navigator.pop(ctx);
              run();
            },
          );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(book.bookTitle,
                        style: Theme.of(ctx).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    status(),
                  ]),
                ),
                tile(
                    Icons.save_outlined,
                    tr(s, 'Save in the app', 'Сохранить в приложении'),
                    tr(s, 'Keeps your work inside FB2 Editor',
                        'Хранит вашу работу внутри FB2 Editor'),
                    onSave),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(tr(s, 'EXPORT A FILE', 'ЭКСПОРТ В ФАЙЛ'),
                      style: const TextStyle(fontSize: 12, letterSpacing: 1)),
                ),
                tile(
                    Icons.menu_book_outlined,
                    'FB2  ·  $name.fb2',
                    tr(s, 'Editable book. Keeps everything, best for backup.',
                        'Редактируемая книга. Сохраняет всё, подходит для резервной копии.'),
                    onExportFb2),
                tile(
                    Icons.tablet_android_outlined,
                    'EPUB  ·  $name.epub',
                    tr(s, 'For e-readers and phone reading apps.',
                        'Для читалок и приложений для чтения.'),
                    onExportEpub),
                tile(
                    Icons.notes_outlined,
                    'TXT  ·  $name.txt',
                    tr(s, 'Plain text, no pictures.', 'Простой текст, без картинок.'),
                    onExportTxt),
                const SizedBox(height: 8),
              ]),
        ),
      );
    },
  );
}
