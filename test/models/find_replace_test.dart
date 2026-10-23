import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/find_replace.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:xml/xml.dart';

Section _section(String title, List<String> p) =>
    Section({'title': title, 'p': p}, BinaryResources([]));

void main() {
  group('findText', () {
    test('finds paragraphs, nested markup and titles, ignoring case by default', () {
      final s = [
        _section('The Cat', ['<p>a cat sat</p>', '<p>no match</p>', '<p>big <strong>CAT</strong> here</p>']),
        _section('Other', ['<p>cat cat</p>']),
      ];
      final hits = findText(s, 'cat');
      expect(hits.map((h) => [h.section, h.paragraph, h.count]), [
        [0, FindHit.titleIndex, 1],
        [0, 0, 1],
        [0, 2, 1],
        [1, 0, 2],
      ]);
    });

    test('match case narrows the result', () {
      final s = [_section('', ['<p>Cat cat CAT</p>'])];
      expect(findText(s, 'cat', matchCase: true).single.count, 1);
    });

    test('tag names and attributes are not searched', () {
      final s = [_section('', ['<p>x <a href="#cat" type="note">[1]</a></p>', '<image xlink:href="#cat"/>'])];
      expect(findText(s, 'cat'), isEmpty);
      expect(findText(s, 'strong'), isEmpty);
    });

    test('regex characters in the query are literal', () {
      final s = [_section('', ['<p>1+1=2 (ok)</p>', '<p>111</p>'])];
      expect(findText(s, '1+1').map((h) => h.paragraph), [0]);
      expect(findText(s, '(ok)').length, 1);
      expect(findText(s, '.'), isEmpty);
    });

    test('empty query and broken blocks give nothing and do not throw', () {
      final s = [_section('t', ['<p>broken', '<p>fine</p>'])];
      expect(findText(s, ''), isEmpty);
      expect(findText(s, 'fine').single.paragraph, 1);
    });

    test('the snippet shows the surroundings', () {
      final s = [_section('', ['<p>${'x' * 60}needle${'y' * 60}</p>'])];
      final snippet = findText(s, 'needle').single.snippet;
      expect(snippet, contains('needle'));
      expect(snippet.startsWith('…') && snippet.endsWith('…'), isTrue);
      expect(snippet.length, lessThan(70));
    });
  });

  group('replaceText', () {
    test('replaces in text, keeping markup and links intact', () {
      final s = [
        _section('Cat story', [
          '<p>a cat and <strong>the Cat</strong><a xlink:href="#n1" type="note">[1]</a></p>'
        ])
      ];
      final n = replaceText(s, 'cat', 'dog');
      expect(n, 3);
      expect(s[0].title, 'dog story');
      expect(s[0].p.single,
          '<p>a dog and <strong>the dog</strong><a xlink:href="#n1" type="note">[1]</a></p>');
    });

    test('markup characters in the replacement are escaped, not interpreted', () {
      final s = [_section('', ['<p>a b</p>'])];
      replaceText(s, 'a', '<b>&');
      // a lone ">" is legal XML text; "<" and "&" must be escaped
      expect(s[0].p.single, '<p>&lt;b>&amp; b</p>');
      expect(XmlDocument.parse(s[0].p.single).rootElement.innerText, '<b>& b');
    });

    test('a replacement containing the query does not loop and is applied once', () {
      final s = [_section('', ['<p>ab</p>'])];
      expect(replaceText(s, 'a', 'aa'), 1);
      expect(s[0].p.single, '<p>aab</p>');
    });

    test('replacing with nothing deletes the text; match case is honoured', () {
      final s = [_section('', ['<p>Cat cat</p>'])];
      replaceText(s, 'cat', '', matchCase: true);
      expect(s[0].p.single, '<p>Cat </p>');
    });

    test('only the chosen hits change', () {
      final s = [_section('', ['<p>cat</p>', '<p>cat</p>'])];
      final hits = findText(s, 'cat');
      replaceText(s, 'cat', 'dog', hits: [hits[1]]);
      expect(s[0].p, ['<p>cat</p>', '<p>dog</p>']);
    });

    test('poems, pictures and unmatched blocks are not damaged', () {
      final s = [
        _section('', [
          '<poem><stanza><v>red roses</v></stanza></poem>',
          '<image xlink:href="#red.jpg"/>',
        ])
      ];
      replaceText(s, 'red', 'blue');
      expect(s[0].p, ['<poem><stanza><v>blue roses</v></stanza></poem>', '<image xlink:href="#red.jpg"/>']);
    });

    test('whitespace and indentation survive', () {
      final s = [_section('', ['<p>   one  two</p>'])];
      replaceText(s, 'two', '2');
      expect(s[0].p.single, '<p>   one  2</p>');
    });

    test('nothing to replace returns 0', () {
      final s = [_section('t', ['<p>x</p>'])];
      expect(replaceText(s, 'zzz', 'a'), 0);
      expect(replaceText(s, '', 'a'), 0);
    });
  });
}
