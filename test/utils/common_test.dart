import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:xml/xml.dart';

void main() {
  group('findFb2File', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fb2_zip_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns null when no fb2 is present', () {
      File('${dir.path}/cover.jpg').writeAsStringSync('x');
      File('${dir.path}/readme.txt').writeAsStringSync('x');
      expect(findFb2File(dir), isNull);
    });
    test('returns null for an empty directory', () {
      expect(findFb2File(dir), isNull);
    });
    test('skips non-fb2 files that sort first', () {
      File('${dir.path}/a.jpg').writeAsStringSync('x');
      File('${dir.path}/b.fb2').writeAsStringSync('x');
      expect(findFb2File(dir)!.path, endsWith('b.fb2'));
    });
    test('finds nested files with uppercase extension', () {
      Directory('${dir.path}/sub').createSync();
      File('${dir.path}/sub/Book.FB2').writeAsStringSync('x');
      expect(findFb2File(dir)!.path, endsWith('Book.FB2'));
    });
  });

  group('stringToInt', () {
    test('parses numeric strings', () => expect(stringToInt('42'), 42));
    test('maps "best" to 100', () => expect(stringToInt('best'), 100));
    test('passes non-strings through', () => expect(stringToInt(7), 7));
    test('throws on non-numeric strings',
        () => expect(() => stringToInt('abc'), throwsFormatException));
  });

  group('stringToBool', () {
    test('is case-insensitive', () {
      expect(stringToBool('TRUE'), isTrue);
      expect(stringToBool('false'), isFalse);
    });
    test('passes non-strings through', () => expect(stringToBool(true), true));
  });

  group('getRandomString', () {
    test('returns requested length from the allowed alphabet', () {
      final s = getRandomString(32);
      expect(s.length, 32);
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(s), isTrue);
    });
    test('returns empty string for zero length',
        () => expect(getRandomString(0), ''));
  });

  group('safeGet', () {
    final data = {
      'a': {
        'b': {'c': 1},
        'n': null
      },
      'list': [1, 2]
    };
    test('reads nested values by dotted key', () {
      expect(safeGet(data, 'a.b.c', 0), 1);
    });
    test('returns default for missing key', () {
      expect(safeGet(data, 'a.x.c', 'def'), 'def');
    });
    test('returns default when value is null', () {
      expect(safeGet(data, 'a.n', 'def'), 'def');
    });
    test('returns default when traversing through a non-map', () {
      expect(safeGet(data, 'list.0', 'def'), 'def');
    });
    test('returns default for null data', () {
      expect(safeGet(null, 'a', 'def'), 'def');
    });
  });

  group('prettyJson / toJSonString / cloneMap', () {
    test('prettyJson indents with two spaces', () {
      expect(prettyJson({'a': 1}), '{\n  "a": 1\n}');
    });
    test('prettyJson returns error text for unencodable objects', () {
      final out = prettyJson({'a': Object()});
      expect(out, contains('Converting object'));
    });
    test('toJSonString converts DateTime values, including nested ones', () {
      final d = DateTime.utc(2020, 1, 2);
      final Map<String, dynamic> input = {
        'd': d,
        'm': <String, dynamic>{'d': d},
        'l': <dynamic>[d]
      };
      final out = jsonDecode(toJSonString(input));
      expect(out['d'], d.toString());
      expect(out['m']['d'], d.toString());
      expect(out['l'][0], d.toString());
    });
    test('cloneMap produces an independent deep copy', () {
      final src = {
        'a': {'b': 1}
      };
      final copy = cloneMap(src);
      copy['a']['b'] = 2;
      expect(src['a']!['b'], 1);
    });
  });

  group('toBeginningOfSentenceCase', () {
    test('capitalizes the first letter', () {
      expect(toBeginningOfSentenceCase('hello world'), 'Hello world');
    });
    test('handles null and empty input', () {
      expect(toBeginningOfSentenceCase(null), isNull);
      expect(toBeginningOfSentenceCase(''), '');
    });
  });

  group('trimSpecialChar', () {
    test('strips real control characters', () {
      expect(trimSpecialChar('a\nb\tc\rd'), 'abcd');
    });
    test('strips escaped (literal backslash) sequences', () {
      expect(trimSpecialChar(r'a\nb\tc\rd'), 'abcd');
      expect(trimSpecialChar(r'a\\nb'), 'ab');
    });
    test('substitutes a replacement character', () {
      expect(trimSpecialChar('a\nb', ' '), 'a b');
    });
    test('returns empty string for null', () {
      expect(trimSpecialChar(null), '');
    });
  });

  group('decode64Image', () {
    test('decodes plain base64', () {
      expect(decode64Image(base64Encode([1, 2, 3, 4])), [1, 2, 3, 4]);
    });
    test('ignores embedded newlines and fixes missing padding', () {
      final b64 = base64Encode([1, 2, 3, 4]); // "AQIDBA=="
      final noPad = b64.replaceAll('=', '');
      expect(decode64Image('${noPad.substring(0, 2)}\n${noPad.substring(2)}'),
          [1, 2, 3, 4]);
    });
    test('returns null for invalid input', () {
      expect(decode64Image('!!!not base64!!!'), isNull);
    });
  });

  group('resizeImage', () {
    test('returns undefined (null) for invalid image data', () async {
      expect(await resizeImage(base64Encode([1, 2, 3]), 10), isNull);
    });
  });

  group('resizeImageBytes sizing', () {
    List<int> png(int w) => img.encodePng(img.Image(width: w, height: w));
    test('shrinks a wide picture to the target width', () async {
      final out = await resizeImageBytes(png(800), 400, 75);
      expect(img.decodeJpg(base64Decode(out as String))!.width, 400);
    });
    test('does not enlarge a small picture', () async {
      final out = await resizeImageBytes(png(200), 600, 75);
      expect(img.decodeJpg(base64Decode(out as String))!.width, 200);
    });
  });

  group('sniffImageType', () {
    test('tells PNG, GIF, WebP and JPEG apart', () {
      expect(sniffImageType([0x89, 0x50, 0x4E, 0x47, 0]).ext, 'png');
      expect(sniffImageType([0x47, 0x49, 0x46, 0x38, 0]).ext, 'gif');
      expect(sniffImageType([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]).contentType,
          'image/webp');
      expect(sniffImageType([0xFF, 0xD8, 0xFF]).contentType, 'image/jpeg');
      expect(sniffImageType([]).ext, 'jpg');
    });
    test('reads base64 text and tolerates junk', () {
      expect(sniffBase64ImageType(base64Encode([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])).ext, 'png');
      expect(sniffBase64ImageType('%%%').ext, 'jpg');
    });
  });

  group('resizeImageBytes', () {
    test('returns input untouched when quality is 100', () async {
      final bytes = [1, 2, 3];
      expect(await resizeImageBytes(bytes, 10, 100), same(bytes));
    });
    test('falls back to input when bytes are not an image', () async {
      final bytes = [1, 2, 3];
      expect(await resizeImageBytes(bytes, 10, 50), same(bytes));
    });
  });

  group('readyAscii / getXmlText', () {
    test('readyAscii decodes latin1 bytes', () {
      expect(readyAscii([0x68, 0xE9]), 'hé');
    });
    test('getXmlText returns root inner text', () {
      expect(getXmlText('<p>Hello <b>big</b> world</p>'), 'Hello big world');
    });
  });

  group('splitStringByEof', () {
    test('splits on \\n, \\r\\n and \\r', () {
      expect(splitStringByEof('a\nb\r\nc\rd'), ['a', 'b', 'c', 'd']);
    });
  });

  group('parseXml', () {
    XmlElement root(String xml) => XmlDocument.parse(xml).rootElement;

    test('emits text items for text nodes', () {
      final items = parseXml(root('<section>hello</section>'));
      expect(items.single.tag, 'text');
      expect(items.single.text, 'hello');
      expect(items.single.xml, 'hello');
    });

    test('rebuilds <p> keeping inline markup one level deep', () {
      final items =
          parseXml(root('<section><p>a <strong>b</strong> c</p></section>'));
      expect(items.single.tag, 'p');
      expect(items.single.text, 'a b c');
      expect(items.single.xml, startsWith('<p>'));
      expect(items.single.xml, contains('<strong>b</strong>'));
    });

    test('splits an image out of a paragraph', () {
      final items = parseXml(root(
          '<section xmlns:xlink="x"><p>t<image xlink:href="#i1"/></p></section>'));
      expect(items.map((i) => i.tag), ['p', 'image']);
      expect(items[1].text, '#i1');
      expect(items[0].xml, isNot(contains('image')));
    });

    test('reads standalone image href from xlink or l namespace', () {
      final a = parseXml(
          root('<s xmlns:xlink="x"><image xlink:href="#a"/></s>'));
      final b = parseXml(root('<s xmlns:l="x"><image l:href="#b"/></s>'));
      expect(a.single.text, '#a');
      expect(b.single.text, '#b');
    });

    test('keeps other elements as generic items', () {
      final items = parseXml(root('<s><title><p>T</p></title></s>'));
      expect(items.single.tag, 'title');
      expect(items.single.text, 'T');
    });
  });

  group('parseSectionXml', () {
    test('extracts title, paragraphs, images and section id', () {
      final doc = XmlDocument.parse('''
<FictionBook xmlns:xlink="x"><body>
  <section section-id="s1">
    <title><p>Chapter</p></title>
    <image xlink:href="#img1"/>
    <p>One</p><p>Two</p>
  </section>
</body></FictionBook>''');
      final sections = parseSectionXml(doc) as List;
      expect(sections, hasLength(1));
      final s = sections.single as Map;
      expect(s['sectionId'], 's1');
      expect(s['title'], 'Chapter');
      expect(s['img'], ['#img1']);
      // title is dropped from paragraphs
      final p = (s['p'] as List).cast<String>();
      expect(p, containsAll(['<p>One</p>', '<p>Two</p>']));
      expect(p, hasLength(2)); // no title, no image
      expect(p.any((e) => e.contains('<image')), isFalse);
    });

    test('falls back to the first paragraph as title', () {
      final doc = XmlDocument.parse(
          '<FictionBook><body><section><p>First</p><p>Second</p></section></body></FictionBook>');
      final s = (parseSectionXml(doc) as List).single as Map;
      expect(s['title'], 'First');
      expect(s['sectionId'], '');
    });

    test('wraps bare text in <p> and drops whitespace-only text', () {
      final doc = XmlDocument.parse(
          '<FictionBook><body><section>\n  loose &amp; text\n  <p>x</p>\n</section></body></FictionBook>');
      final s = (parseSectionXml(doc) as List).single as Map;
      final p = (s['p'] as List).cast<String>();
      expect(p, hasLength(2));
      expect(XmlDocument.parse(p.first).rootElement.innerText.trim(),
          'loose & text');
      expect(p.last, '<p>x</p>');
    });

    test('returns one entry per section', () {
      final doc = XmlDocument.parse(
          '<FictionBook><body><section><p>a</p></section><section><p>b</p></section></body></FictionBook>');
      expect(parseSectionXml(doc) as List, hasLength(2));
    });
  });

  group('safeFileName', () {
    test('replaces reserved characters and collapses spaces', () {
      expect(safeFileName('A/B: "C"?  <D>|*'), 'A B C D');
    });
    test('strips leading dots and control characters', () {
      expect(safeFileName('..\u0001hidden'), 'hidden');
    });
    test('keeps Cyrillic', () {
      expect(safeFileName('Война и мир'), 'Война и мир');
    });
    test('cuts long names', () {
      expect(safeFileName('x' * 300, maxLength: 20), 'x' * 20);
    });
    test('can end up empty', () {
      expect(safeFileName('???'), '');
    });
  });
}
