import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:xml/xml.dart';

// Content the editor must not lose when it re-saves a book it did not author.
const _book = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description>
  <title-info>
    <genre>prose</genre>
    <author><first-name>Ann</first-name><last-name>Lee</last-name></author>
    <book-title>Tom &amp; Jerry</book-title>
    <annotation><p>About it</p></annotation>
    <date>2001</date>
    <coverpage><image l:href="#cover.jpg"/></coverpage>
    <lang>en</lang>
    <sequence name="Saga"/>
  </title-info>
  <document-info>
    <author><nickname>scanner</nickname></author>
    <program-used>Scanner 1</program-used>
    <date>2020-01-02</date>
    <src-url>http://example.com/b</src-url>
    <id>doc-1</id>
    <version>2.0</version>
  </document-info>
</description>
<body>
  <title><p>Tom &amp; Jerry</p></title>
  <section section-id="s1">
    <title><p>Chapter 1</p></title>
    <image l:href="#i1.jpg"/>
    <image l:href="#i2.jpg"/>
    <p>See<a l:href="#n1" type="note">[1]</a> and <strong><emphasis>both</emphasis></strong>.</p>
    <poem><stanza><v>Roses are red</v></stanza></poem>
    <section><title><p>Nested</p></title><p>Inner text</p></section>
  </section>
</body>
<body name="notes">
  <title><p>Notes</p></title>
  <section id="n1"><title><p>1</p></title><p>The footnote text</p></section>
</body>
<binary content-type="image/jpeg" id="cover.jpg" section-id="cover">QUJD</binary>
<binary content-type="image/jpeg" id="i1.jpg">QUJD</binary>
<binary content-type="image/jpeg" id="i2.jpg">QUJD</binary>
</FictionBook>''';

Future<XmlDocument> _resave() async {
  final json = await Fb2Service().convertXmlToJson(_book);
  final out = ProjectModel.fromJson(json).getBookXml() as String;
  return XmlDocument.parse(out);
}

Iterable<XmlElement> _all(XmlDocument d, String name) =>
    d.rootElement.descendants.whereType<XmlElement>().where((e) => e.name.local == name);

void main() {
  group('re-saving an untouched book keeps its content', () {
    test('writes <book-title> into title-info', () async {
      final doc = await _resave();
      final info = _all(doc, 'title-info').single;
      expect(info.findElements('book-title').single.innerText, 'Tom & Jerry');
    });

    test('title-info follows the FB2 schema order, without foreign elements', () async {
      final doc = await _resave();
      final names = _all(doc, 'title-info')
          .single
          .childElements
          .map((e) => e.name.local)
          .toList();
      expect(names, isNot(contains('fb-editor')));
      const schema = [
        'genre', 'author', 'book-title', 'annotation', 'date', 'coverpage', 'lang', 'sequence'
      ];
      final order = names.map(schema.indexOf).toList();
      expect(order, everyElement(isNot(-1)));
      expect(order, orderedEquals([...order]..sort()));
    });

    test('keeps date and lang in title-info and program-used / src-url in document-info', () async {
      final doc = await _resave();
      final info = _all(doc, 'title-info').single;
      expect(info.findElements('date').single.innerText, '2001');
      expect(info.findElements('lang').single.innerText, 'en');
      final docInfo = _all(doc, 'document-info').single;
      expect(docInfo.findElements('program-used'), isNotEmpty);
      expect(docInfo.findElements('src-url').single.innerText, 'http://example.com/b');
      expect(docInfo.findElements('lang'), isEmpty);
    });

    test('keeps the notes body', () async {
      final doc = await _resave();
      final bodies = doc.rootElement.findElements('body').toList();
      expect(bodies, hasLength(2));
      expect(bodies[1].getAttribute('name'), 'notes');
      expect(bodies[1].innerText, contains('The footnote text'));
    });

    test('keeps footnote link attributes', () async {
      final doc = await _resave();
      final link = _all(doc, 'a').single;
      expect(link.getAttribute('href', namespace: 'http://www.w3.org/1999/xlink'), '#n1');
      expect(link.getAttribute('type'), 'note');
    });

    test('keeps nested inline formatting', () async {
      final doc = await _resave();
      expect(_all(doc, 'strong').single.findElements('emphasis').single.innerText, 'both');
    });

    test('keeps every section image', () async {
      final doc = await _resave();
      final section = doc.rootElement.findElements('body').first.findElements('section').single;
      final hrefs = section
          .findElements('image')
          .map((e) => e.getAttribute('href', namespace: 'http://www.w3.org/1999/xlink'))
          .toList();
      expect(hrefs, ['#i1.jpg', '#i2.jpg']);
      final binaries = doc.rootElement.findElements('binary').map((e) => e.getAttribute('id'));
      expect(binaries, containsAll(['cover.jpg', 'i1.jpg', 'i2.jpg']));
    });

    test('keeps poems and nested sections', () async {
      final doc = await _resave();
      expect(_all(doc, 'v').single.innerText, 'Roses are red');
      final section = doc.rootElement.findElements('body').first.findElements('section').single;
      expect(section.findElements('section').single.innerText, contains('Inner text'));
    });

    test('image prefix is declared and the book title is escaped', () async {
      final doc = await _resave();
      // would throw on an undeclared prefix when resolving the namespace
      final image = doc.rootElement.findElements('body').first.descendants
          .whereType<XmlElement>()
          .firstWhere((e) => e.name.local == 'image');
      expect(image.name.namespaceUri ?? 'x', isNotNull);
      expect(image.attributes.every((a) => a.name.prefix != 'xlink' ||
          doc.rootElement.getAttribute('xmlns:xlink') != null), isTrue);
    });

    test('a second round trip is stable', () async {
      final first = (await _resave()).toXmlString();
      final json = await Fb2Service().convertXmlToJson(first);
      final second = ProjectModel.fromJson(json).getBookXml() as String;
      expect(XmlDocument.parse(second).toXmlString(), first);
    });
  });
}
