import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:xml/xml.dart';

/// One place where a search text occurs: a paragraph, or a section title when
/// [paragraph] is [titleIndex].
class FindHit {
  static const titleIndex = -1;
  final int section;
  final int paragraph;
  final int count;
  final String snippet;
  const FindHit(this.section, this.paragraph, this.count, this.snippet);
}

RegExp _pattern(String query, bool matchCase) =>
    RegExp(RegExp.escape(query), caseSensitive: matchCase, unicode: true);

List<XmlText> _textNodes(XmlElement root) =>
    root.descendants.whereType<XmlText>().toList();

String _snippet(String text, Match m) {
  final from = (m.start - 24).clamp(0, text.length);
  final to = (m.end + 24).clamp(0, text.length);
  return '${from > 0 ? '…' : ''}${text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ')}'
      '${to < text.length ? '…' : ''}';
}

/// Every paragraph and section title containing [query] (text inside markup
/// such as `<strong>` counts; a match split across two styles does not).
List<FindHit> findText(List<Section> sections, String query,
    {bool matchCase = false}) {
  if (query.isEmpty) return [];
  final re = _pattern(query, matchCase);
  final hits = <FindHit>[];
  for (var s = 0; s < sections.length; s++) {
    final title = sections[s].title;
    final tm = re.allMatches(title).toList();
    if (tm.isNotEmpty) {
      hits.add(FindHit(s, FindHit.titleIndex, tm.length, _snippet(title, tm.first)));
    }
    final p = sections[s].p;
    for (var i = 0; i < p.length; i++) {
      if (imageHref(p[i]) != null) continue;
      try {
        var count = 0;
        String? snippet;
        for (final node in _textNodes(XmlDocument.parse(p[i]).rootElement)) {
          final ms = re.allMatches(node.value).toList();
          if (ms.isEmpty) continue;
          count += ms.length;
          snippet ??= _snippet(node.value, ms.first);
        }
        if (count > 0) hits.add(FindHit(s, i, count, snippet!));
      } catch (_) {
        // a block that is not valid XML is left alone
      }
    }
  }
  return hits;
}

/// Replaces [query] inside one stored block; null when nothing changed.
String? _replaceInBlock(String block, RegExp re, String replacement) {
  try {
    final doc = XmlDocument.parse(block);
    var changed = false;
    for (final node in _textNodes(doc.rootElement)) {
      final next = node.value.replaceAllMapped(re, (_) => replacement);
      if (next != node.value) {
        node.value = next;
        changed = true;
      }
    }
    return changed ? doc.rootElement.outerXml : null;
  } catch (_) {
    return null;
  }
}

/// Replaces every occurrence in the given [hits] (all of them when null) and
/// returns how many places were changed.
int replaceText(List<Section> sections, String query, String replacement,
    {bool matchCase = false, List<FindHit>? hits}) {
  if (query.isEmpty) return 0;
  final re = _pattern(query, matchCase);
  var changes = 0;
  final targets = hits ?? findText(sections, query, matchCase: matchCase);
  for (final h in targets) {
    final section = sections[h.section];
    if (h.paragraph == FindHit.titleIndex) {
      section.title = section.title.replaceAllMapped(re, (_) => replacement);
      changes += h.count;
    } else {
      final next = _replaceInBlock(section.p[h.paragraph], re, replacement);
      if (next != null) {
        section.p[h.paragraph] = next;
        changes += h.count;
      }
    }
  }
  return changes;
}
