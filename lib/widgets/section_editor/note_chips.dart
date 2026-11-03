import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The Quill embed type that stands for one in-book link (a Note mark) while a
/// paragraph is open, so the user sees a small [1] chip instead of its XML.
const noteEmbedType = 'fb2note';

final _linkTag = RegExp(r'<a\b[^>]*?(?:xlink|l):href="#[^"]+"[^>]*>(.*?)</a>');
final _idOf = RegExp(r'(?:xlink|l):href="#([^"]+)"');

/// The Quill document ops for editable paragraph [text]: plain text, with every
/// in-book link turned into a chip that keeps the link's exact XML.
List<Map<String, dynamic>> noteOps(String text) {
  final ops = <Map<String, dynamic>>[];
  var at = 0;
  for (final m in _linkTag.allMatches(text)) {
    if (m.start > at) ops.add({'insert': text.substring(at, m.start)});
    ops.add({
      'insert': {noteEmbedType: m.group(0)!}
    });
    at = m.end;
  }
  ops.add({'insert': '${text.substring(at)}\n'});
  return ops;
}

/// The paragraph text back from [doc], each chip written out as its XML.
String serializeNotes(Document doc) {
  final out = StringBuffer();
  for (final op in doc.toDelta().toList()) {
    final v = op.data;
    if (v is String) {
      out.write(v);
    } else if (v is Map && v[noteEmbedType] is String) {
      out.write(v[noteEmbedType]);
    }
  }
  return out.toString().replaceFirst(RegExp(r'\n$'), '');
}

/// [text] with every in-book link shown as just its label, for paragraphs
/// that are not open.
String showNoteLabels(String text) => text.replaceAllMapped(_linkTag, (m) => m.group(1)!);

/// The id a chip's XML points at.
String noteChipId(String xml) => _idOf.firstMatch(xml)?.group(1) ?? '';

/// The label a chip shows, its tags removed.
String noteChipLabel(String xml) =>
    (_linkTag.firstMatch(xml)?.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '');

/// The chip right at or just before [offset] in [doc]: the cursor sits on
/// either side of it.
({int offset, String xml})? noteChipNear(Document doc, int offset) {
  var at = 0;
  for (final op in doc.toDelta().toList()) {
    final v = op.data;
    final len = op.length!;
    if (v is Map && v[noteEmbedType] is String && (at == offset || at == offset - 1)) {
      return (offset: at, xml: v[noteEmbedType] as String);
    }
    at += len;
  }
  return null;
}

/// Draws a chip as its label; tapping it calls [onTap] with its offset.
class NoteChipBuilder extends EmbedBuilder {
  final void Function(int offset) onTap;
  const NoteChipBuilder({required this.onTap});

  @override
  String get key => noteEmbedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final xml = '${embedContext.node.value.data}';
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey('note-chip-${noteChipId(xml)}'),
      onTap: () => onTap(embedContext.node.documentOffset),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
            color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
        child: Text(noteChipLabel(xml),
            style: embedContext.textStyle.copyWith(
                color: cs.onPrimaryContainer,
                fontSize: (embedContext.textStyle.fontSize ?? 14) * 0.85)),
      ),
    );
  }
}
