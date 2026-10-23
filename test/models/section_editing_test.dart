import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:xml/xml.dart';

Section _section(List<String> p) =>
    Section({'p': p, 'sectionId': 's'}, BinaryResources([]));

/// The text of a stored paragraph as a reader would see it.
String _plain(String xml) => XmlDocument.parse(xml).rootElement.innerText;

void main() {
  group('editableText', () {
    test('a paragraph with inline markup is one line, not one line per child', () {
      final s = _section(['<p>one <strong>two</strong> three</p>']);
      expect(s.editableText(s.p[0]), 'one <strong>two</strong> three');
    });

    test('keeps link attributes so footnotes survive an edit', () {
      final s = _section(['<p>see<a l:href="#n1" type="note">[1]</a></p>']);
      expect(s.editableText(s.p[0]), 'see<a l:href="#n1" type="note">[1]</a>');
    });

    test('keeps leading spaces and no-break spaces (indents)', () {
      final s = _section(['<p>   indented</p>', '<p>   spaced</p>']);
      expect(s.editableText(s.p[0]), '   indented');
      expect(s.editableText(s.p[1]), '   spaced');
    });

    test('a block element is shown whole', () {
      final s = _section(['<poem><stanza><v>Roses</v></stanza></poem>']);
      expect(s.editableText(s.p[0]), '<poem><stanza><v>Roses</v></stanza></poem>');
    });

    test('unparsable xml is shown as it is', () {
      final s = _section(['<p>broken']);
      expect(s.editableText(s.p[0]), '<p>broken');
    });
  });

  group('replaceParagraph', () {
    test('saving the text unchanged leaves the paragraph byte for byte', () {
      final s = _section(['<p>one <strong>two</strong> three</p>']);
      s.replaceParagraph(0, s.editableText(s.p[0]));
      expect(s.p, ['<p>one <strong>two</strong> three</p>']);
    });

    test('an edit next to inline markup keeps a single paragraph', () {
      final s = _section(['<p>a</p>', '<p>one <strong>two</strong> three</p>', '<p>z</p>']);
      final count = s.replaceParagraph(1, 'X${s.editableText(s.p[1])}');
      expect(count, 1);
      expect(s.p, ['<p>a</p>', '<p>Xone <strong>two</strong> three</p>', '<p>z</p>']);
    });

    test('new lines split a paragraph and report the new size', () {
      final s = _section(['<p>a</p>', '<p>b</p>']);
      expect(s.replaceParagraph(0, 'x\ny\nz'), 3);
      expect(s.p, ['<p>x</p>', '<p>y</p>', '<p>z</p>', '<p>b</p>']);
    });

    test('a typed ampersand is stored safely', () {
      final s = _section(['<p>a</p>']);
      s.replaceParagraph(0, 'AT&T and &amp; more');
      expect(_plain(s.p[0]), 'AT&T and & more');
    });

    test('a typed "<" is stored safely', () {
      final s = _section(['<p>a</p>']);
      s.replaceParagraph(0, '5 < 6 and 7 <8');
      expect(_plain(s.p[0]), '5 < 6 and 7 <8');
    });

    test('typed markup stays markup', () {
      final s = _section(['<p>a</p>']);
      s.replaceParagraph(0, 'x <strong>bold</strong> <emphasis>it</emphasis>');
      expect(s.p[0], '<p>x <strong>bold</strong> <emphasis>it</emphasis></p>');
    });

    test('unclosed markup never produces a broken paragraph', () {
      final s = _section(['<p>a</p>']);
      s.replaceParagraph(0, 'oops <strong>never closed');
      expect(() => XmlDocument.parse(s.p[0]), returnsNormally);
      expect(_plain(s.p[0]), contains('never closed'));
    });

    test('a poem edited into something broken is left as it was', () {
      const poem = '<poem><stanza><v>Roses</v></stanza></poem>';
      final s = _section([poem]);
      expect(s.replaceParagraph(0, '<poem><stanza><v>Roses</stanza>'), 1);
      expect(s.p, [poem]);
    });

    test('a poem edited into a valid poem is kept as a poem', () {
      final s = _section(['<poem><stanza><v>Roses</v></stanza></poem>']);
      s.replaceParagraph(0, '<poem><stanza><v>Violets</v></stanza></poem>');
      expect(s.p, ['<poem><stanza><v>Violets</v></stanza></poem>']);
    });

    test('indents typed as no-break spaces survive', () {
      final s = _section(['<p>a</p>']);
      s.replaceParagraph(0, '   text');
      expect(s.p[0], '<p>   text</p>');
    });
  });

  group('load (pasted plain text)', () {
    test('escapes characters that would break the xml', () {
      final s = _section([]);
      s.load('AT&T\n5 < 6\n<strong>not markup</strong>');
      expect(s.p.map(_plain), ['AT&T', '5 < 6', '<strong>not markup</strong>']);
    });
  });
}
