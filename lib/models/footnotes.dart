import 'package:quill_fb2/utils/common.dart';
import 'package:xml/xml.dart';

/// A note for readers, kept in the book's notes body and pointed to from the
/// text by a Note mark. [editable] is false when the note holds more than plain
/// paragraphs (emphasis, a poem, ...); such a note is shown but never rewritten.
class Footnote {
  final String id;
  final String label;
  final String text;
  final bool editable;
  const Footnote(this.id, this.label, this.text, {this.editable = true});
}

/// A Note mark found in a line of editable paragraph text.
typedef NoteMarkMatch = ({int start, int end, String id});

final _anyRef = RegExp(r'(?:xlink|l):href="#([^"]+)"');
final _markTag = RegExp(r'<a\b[^>]*?(?:xlink|l):href="#([^"]+)"[^>]*>.*?</a>');

bool _isNotesBody(XmlElement body) => body.getAttribute('name') == 'notes';

XmlElement? _parse(String xml) {
  try {
    return XmlDocument.parse(xml).rootElement;
  } catch (_) {
    return null;
  }
}

/// Plain text of an element made only of text (no child elements), else null.
String? _plain(XmlElement e) {
  if (e.attributes.isNotEmpty) return null;
  if (e.children.any((n) => n is! XmlText)) return null;
  return e.innerText;
}

Footnote? _read(XmlElement sec) {
  final id = sec.getAttribute('id');
  if (id == null || id.isEmpty) return null;
  final elements = sec.childElements.toList();
  var label = '';
  final lines = <String>[];
  var editable = sec.attributes.length == 1 &&
      sec.children.every((n) => n is XmlElement || (n is XmlText && n.value.trim().isEmpty));
  for (var i = 0; i < elements.length; i++) {
    final e = elements[i];
    if (i == 0 && e.name.local == 'title') {
      final ps = e.childElements.toList();
      final t = ps.length == 1 && ps.first.name.local == 'p' ? _plain(ps.first) : null;
      if (t == null || e.attributes.isNotEmpty) editable = false;
      label = e.innerText.trim();
      continue;
    }
    final t = e.name.local == 'p' ? _plain(e) : null;
    if (t == null) editable = false;
    lines.add(t ?? e.innerText.trim());
  }
  return Footnote(id, label, lines.join('\n'), editable: editable);
}

/// Every footnote in the notes bodies of [bodies], in book order.
List<Footnote> readFootnotes(List<String> bodies) => [
      for (final b in bodies)
        if (_parse(b) case final body? when _isNotesBody(body))
          for (final sec in body.childElements.where((e) => e.name.local == 'section'))
            if (_read(sec) case final note?) note,
    ];

Footnote? findFootnote(List<String> bodies, String id) {
  for (final n in readFootnotes(bodies)) {
    if (n.id == id) return n;
  }
  return null;
}

String _sectionXml(String id, String label, String text) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  return '<section id="${escapeXml(id)}">'
      '${label.isEmpty ? '' : '<title><p>${escapeText(label)}</p></title>'}'
      '${lines.map((l) => '<p>${escapeText(l)}</p>').join()}'
      '</section>';
}

/// [bodies] with the footnote [id] set to [label] and [text]: replaced in
/// place when it exists, else added to the first notes body (made if missing).
List<String> putFootnote(List<String> bodies, String id, String label, String text) {
  final fresh = XmlDocumentFragment.parse(_sectionXml(id, label, text)).firstElementChild!;
  final out = List.of(bodies);
  for (var i = 0; i < out.length; i++) {
    final body = _parse(out[i]);
    if (body == null || !_isNotesBody(body)) continue;
    for (final sec in body.childElements) {
      if (sec.name.local == 'section' && sec.getAttribute('id') == id) {
        sec.replace(fresh.copy());
        out[i] = body.toXmlString();
        return out;
      }
    }
  }
  for (var i = 0; i < out.length; i++) {
    final body = _parse(out[i]);
    if (body == null || !_isNotesBody(body)) continue;
    body.children.add(fresh.copy());
    out[i] = body.toXmlString();
    return out;
  }
  return [...out, '<body name="notes">${fresh.toXmlString()}</body>'];
}

/// [bodies] without the footnotes whose ids are in [ids].
List<String> removeFootnotes(List<String> bodies, Set<String> ids) {
  if (ids.isEmpty) return bodies;
  return [
    for (final b in bodies)
      if (_parse(b) case final body? when _isNotesBody(body) && _hasAny(body, ids))
        (body
              ..children.removeWhere((n) =>
                  n is XmlElement && n.name.local == 'section' && ids.contains(n.getAttribute('id'))))
            .toXmlString()
      else
        b
  ];
}

bool _hasAny(XmlElement body, Set<String> ids) =>
    body.childElements.any((s) => s.name.local == 'section' && ids.contains(s.getAttribute('id')));

/// The ids every link in [xml] points at (`#id`).
Iterable<String> linkedIds(String xml) => _anyRef.allMatches(xml).map((m) => m.group(1)!);


/// The label a new footnote is offered: one past the highest number in use.
String nextFootnoteLabel(List<Footnote> notes) {
  var top = 0;
  for (final n in notes) {
    final m = RegExp(r'\d+').firstMatch(n.label);
    final v = m == null ? null : int.tryParse(m.group(0)!);
    if (v != null && v > top) top = v;
  }
  return '${top + 1}';
}

/// An id no element in the book uses yet.
String newFootnoteId(Set<String> taken) {
  var n = 1;
  while (taken.contains('note_$n')) {
    n++;
  }
  return 'note_$n';
}

/// The inline markup of a Note mark showing [label].
String noteMarkXml(String id, String label) =>
    '<a l:href="#${escapeXml(id)}" type="note">[${escapeText(label)}]</a>';

/// The Note mark (pointing at one of [noteIds]) that covers [offset] in
/// [text], touching either end included; null when there is none.
NoteMarkMatch? noteMarkAt(String text, int offset, Set<String> noteIds) {
  for (final m in _markTag.allMatches(text)) {
    if (offset >= m.start && offset <= m.end && noteIds.contains(m.group(1))) {
      return (start: m.start, end: m.end, id: m.group(1)!);
    }
  }
  return null;
}
