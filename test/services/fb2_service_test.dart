import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:xml/xml.dart';

const _fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink" xmlns:xlink="http://www.w3.org/1999/xlink">
<description>
  <title-info>
    <genre>prose</genre>
    <author><first-name>Ann</first-name><last-name>Lee</last-name></author>
    <book-title>Sample</book-title>
    <annotation><p>About it</p></annotation>
    <lang>en</lang>
  </title-info>
  <document-info><id>doc-1</id><version>2.0</version></document-info>
</description>
<body>
  <title>Sample Body</title>
  <section section-id="s1">
    <title><p>Chapter 1</p></title>
    <p>First</p>
    <p>Second</p>
  </section>
</body>
<binary content-type="image/jpeg" id="c.jpg" section-id="cover">QUJD</binary>
</FictionBook>''';

void main() {
  final service = Fb2Service();

  group('safeGetXmlText', () {
    final node = XmlDocument.parse('<r><a>x</a><a>y</a></r>').rootElement;
    test('returns inner text of the first match', () {
      expect(service.safeGetXmlText(node, 'a'), 'x');
    });
    test('returns empty string when missing', () {
      expect(service.safeGetXmlText(node, 'zzz'), '');
    });
  });

  group('xmlToJson', () {
    test('wraps in the tag and returns badgerfish JSON', () {
      final json = service.xmlToJson('<b>hi</b>', 'root');
      expect(json['root']['b'][r'$'], 'hi');
    });
  });

  group('getAllChildren', () {
    test('returns [] for an empty list', () {
      expect(service.getAllChildren([]), isEmpty);
    });
    test('lists non-empty children with name and outer XML', () {
      final doc = XmlDocument.parse('<r><a>1</a><b></b></r>');
      final res = service.getAllChildren([doc.rootElement]);
      expect(res, hasLength(1));
      expect((res.first['name'] as XmlName).local, 'a');
      expect(res.first['text'], '<a>1</a>');
    });
  });

  group('tryParse', () {
    test('returns a valid result for well-formed XML', () async {
      final r = await service.tryParse('<a><b/></a>', 5);
      expect(r.valid, isTrue);
      expect(r.xml, '<a><b/></a>');
    });

    test('repairs a stray "<" by dropping it', () async {
      final r = await service.tryParse('<a>x < y</a>', 5);
      expect(r.valid, isTrue);
      expect(r.doc.rootElement.innerText, 'x  y');
    });

    test('returns an invalid result, not an exception, when unrecoverable',
        () async {
      final r = await service.tryParse('<a><b>t</c></a>', 5);
      expect(r.valid, isFalse);
    });

    test('returns invalid when the error is at end of input', () async {
      final r = await service.tryParse('<a>t', 5);
      expect(r.valid, isFalse);
    });

    test('stops retrying when level is exhausted', () async {
      final r = await service.tryParse('<a>x < y</a>', 0);
      expect(r.valid, isFalse);
      expect(r.doc.rootElement.name.local, 'xml');
    });
  });

  group('convertXmlToJson', () {
    test('extracts body title, resources and sections', () async {
      final json = await service.convertXmlToJson(_fb2) as Map;
      expect(json['bodyTitle'], 'Sample Body');

      final res = (json['resources'] as List).single as Map;
      expect(res['id'], 'c.jpg');
      expect(res['contentType'], 'image/jpeg');
      expect(res['sectionId'], 'cover');
      expect(res['data'], 'QUJD');

      final sections = json['sections'] as List;
      expect(sections, hasLength(1));
      expect((sections.single as Map)['sectionId'], 's1');
      expect((sections.single as Map)['title'], 'Chapter 1');
    });

    test('returns null for input that is not FB2', () async {
      expect(await service.convertXmlToJson('<nothing/>'), isNull);
    });
  });

  group('import → ProjectModel → export round trip', () {
    test('parsed project exposes metadata', () async {
      final json = await service.convertXmlToJson(_fb2);
      final p = ProjectModel.fromJson(json, 'pid');
      expect(p.projectId, 'pid');
      expect(p.getBookTitle(), 'Sample Body');
      expect(p.getAuthor(), 'Ann Lee');
      expect(p.lang, 'en');
      expect(p.genre, ['prose']);
      expect(p.annotation, ['About it']);
      expect(p.version, '2.0');
      expect(p.section.single.title, 'Chapter 1');
      expect(p.binaryResource.find('#c.jpg').data, 'QUJD');
    });

    test('exported XML parses back to equivalent content', () async {
      final p = ProjectModel.fromJson(await service.convertXmlToJson(_fb2));
      final exported = p.getBookXml() as String;
      // exported document must be well-formed
      final out = XmlDocument.parse(exported);
      expect(out.rootElement.name.local, 'FictionBook');

      final again = await service.convertXmlToJson(exported) as Map;
      final p2 = ProjectModel.fromJson(again);
      expect(p2.getBookTitle(), p.getBookTitle());
      expect(p2.section.single.title, 'Chapter 1');
      expect(p2.section.single.p, p.section.single.p);
      expect(p2.binaryResource.resources.single.data, 'QUJD');
    });
  });
}
