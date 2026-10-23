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
      final s = _section(['<poem><stanza><v>Roses</v></stanza><text-author>Me</text-author></poem>']);
      expect(s.editableText(s.p[0]), '<poem><stanza><v>Roses</v></stanza><text-author>Me</text-author></poem>');
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
      const poem = '<poem><stanza><v>Roses</v></stanza><text-author>Me</text-author></poem>';
      final s = _section([poem]);
      expect(s.replaceParagraph(0, '<poem><stanza><v>Roses</stanza>'), 1);
      expect(s.p, [poem]);
    });

    test('a poem edited into a valid poem is kept as a poem', () {
      final s = _section(['<poem><stanza><v>Roses</v></stanza><text-author>Me</text-author></poem>']);
      s.replaceParagraph(0, '<poem><stanza><v>Violets</v></stanza><text-author>Me</text-author></poem>');
      expect(s.p, ['<poem><stanza><v>Violets</v></stanza><text-author>Me</text-author></poem>']);
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

  group('poems', () {
    test('poemBlock: blank line = new stanza, text is escaped', () {
      expect(Section.poemBlock('a & b\n  c  \n\n\n\nd<e\r\ng'),
          '<poem><stanza><v>a &amp; b</v><v>c</v></stanza><stanza><v>d&lt;e</v><v>g</v></stanza></poem>');
      expect(Section.poemBlock('  \n\n'), isNull);
    });

    test('insertBlock puts a poem after the given paragraph', () {
      final s = _section(['<p>a</p>', '<p>b</p>']);
      expect(s.insertBlock(0, Section.poemBlock('x')!), 1);
      expect(s.p.map((e) => e.startsWith('<poem')), [false, true, false]);
    });

    test('a plain poem is edited as lines and written back as a poem', () {
      final s = _section(['<poem><stanza><v>one</v><v>two</v></stanza><stanza><v>three</v></stanza></poem>']);
      expect(s.editableText(s.p[0]), 'one\ntwo\n\nthree');
      expect(s.replaceParagraph(0, 'one\ntwo\nTWO-B\n\nthree & four'), 1);
      expect(s.p, [
        '<poem><stanza><v>one</v><v>two</v><v>TWO-B</v></stanza><stanza><v>three &amp; four</v></stanza></poem>'
      ]);
    });

    test('clearing a plain poem removes it', () {
      final s = _section(['<p>a</p>', '<poem><stanza><v>x</v></stanza></poem>']);
      expect(s.replaceParagraph(1, ''), 0);
      expect(s.p, ['<p>a</p>']);
    });

    test('a poem with a title, author or styled verse keeps its structure', () {
      for (final xml in [
        '<poem><title><p>T</p></title><stanza><v>x</v></stanza></poem>',
        '<poem><stanza><v>x <emphasis>y</emphasis></v></stanza><text-author>Me</text-author></poem>',
      ]) {
        final s = _section([xml]);
        expect(s.editableText(xml), xml);
        s.replaceParagraph(0, xml.replaceFirst('x', 'z'));
        expect(s.p.single, contains('z'));
        expect(s.p.single, contains(xml.contains('<title>') ? '<title>' : 'text-author'));
      }
    });

    test('displayText shows verses for any poem', () {
      final s = _section([]);
      expect(s.displayText('<poem><title><p>T</p></title><stanza><v>x</v><v>y</v></stanza></poem>'), 'x\ny');
    });
  });
}
