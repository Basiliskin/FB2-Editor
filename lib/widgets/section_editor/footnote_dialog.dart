import 'package:flutter/material.dart';
import 'package:quill_fb2/models/footnotes.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// What the user chose in the footnote dialog.
sealed class FootnoteAction {
  const FootnoteAction();
}

class SaveFootnote extends FootnoteAction {
  final String label;
  final String text;
  const SaveFootnote(this.label, this.text);
}

class DeleteFootnote extends FootnoteAction {
  const DeleteFootnote();
}

/// Asks for a footnote's label and text. With [note] it edits that note (and
/// offers Delete); a note the app can't edit is shown read-only. Returns null
/// when cancelled.
Future<FootnoteAction?> showFootnoteDialog(BuildContext context, AppService service,
        {Footnote? note, String label = ''}) =>
    showDialog<FootnoteAction>(
        context: context,
        builder: (_) => FootnoteDialog(service: service, note: note, label: label));

class FootnoteDialog extends StatefulWidget {
  final AppService service;
  final Footnote? note;
  final String label;
  const FootnoteDialog({super.key, required this.service, this.note, this.label = ''});

  @override
  State<FootnoteDialog> createState() => _FootnoteDialogState();
}

class _FootnoteDialogState extends State<FootnoteDialog> {
  late final _label = TextEditingController(text: widget.note?.label ?? widget.label);
  late final _text = TextEditingController(text: widget.note?.text ?? '');

  @override
  void dispose() {
    _label.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final note = widget.note;
    final readOnly = note != null && !note.editable;
    final canSave = _label.text.trim().isNotEmpty && _text.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(note == null
          ? tr(s, 'Insert footnote', 'Вставить сноску')
          : tr(s, 'Footnote', 'Сноска')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (readOnly) ...[
            Text(tr(s, "This note has formatting the app can't edit. It is kept as it is.",
                'В этой сноске есть оформление, которое приложение не умеет править. Она останется как есть.')),
            const SizedBox(height: 12),
            Text(note.text),
          ] else ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: TextField(
                key: const ValueKey('footnote-label'),
                controller: _label,
                decoration: InputDecoration(
                    labelText: tr(s, 'Label', 'Метка'), hintText: tr(s, 'e.g. 1 or *', 'напр. 1 или *')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('footnote-text'),
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                  labelText: tr(s, 'Note text', 'Текст сноски'),
                  hintText: tr(s, 'What the reader sees at the end of the book', 'Что читатель увидит в конце книги'),
                  alignLabelWithHint: true),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ]),
      ),
      actions: [
        if (note != null)
          TextButton(
              onPressed: () => Navigator.pop(context, const DeleteFootnote()),
              child: Text(tr(s, 'Delete', 'Удалить'))),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(s, 'Cancel', 'Отмена'))),
        if (!readOnly)
          FilledButton(
              onPressed: canSave
                  ? () => Navigator.pop(context, SaveFootnote(_label.text.trim(), _text.text.trim()))
                  : null,
              child: Text(tr(s, 'Save', 'Сохранить'))),
      ],
    );
  }
}
