import 'package:flutter/material.dart';

/// Shows the little Markdown a model answers with: headings, bullets, **bold** and paragraphs.
class MarkdownLite extends StatelessWidget {
  final String text;
  const MarkdownLite(this.text, {super.key});

  static List<TextSpan> _inline(String s, TextStyle? base) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(s)) {
      if (m.start > at) spans.add(TextSpan(text: s.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.bold)));
      at = m.end;
    }
    if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        rows.add(const SizedBox(height: 6));
      } else if (RegExp(r'^#{1,6}\s').hasMatch(line.trim())) {
        rows.add(Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), ''), style: t.titleSmall)));
      } else if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
        rows.add(Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  '),
              Expanded(
                  child: Text.rich(TextSpan(
                      style: t.bodyMedium, children: _inline(line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''), t.bodyMedium)))),
            ])));
      } else {
        rows.add(Text.rich(TextSpan(style: t.bodyMedium, children: _inline(line.trim(), t.bodyMedium))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}
