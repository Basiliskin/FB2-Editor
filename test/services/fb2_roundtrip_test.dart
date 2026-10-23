import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:quill_fb2/utils/common.dart' show newBookXml;
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

  group('section structure survives a save', () {
    String book(String sections) => '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><book-title>T</book-title></title-info></description>
<body><title><p>T</p></title>$sections</body>
<binary content-type="image/jpeg" id="pic.jpg">QUJD</binary>
</FictionBook>''';

    Future<ProjectModel> load(String xml) async =>
        ProjectModel.fromJson(await Fb2Service().convertXmlToJson(xml));

    Future<XmlDocument> resave(ProjectModel p) async {
      final out = p.getBookXml() as String;
      // the saved file must load back into the same number of sections
      return XmlDocument.parse(out);
    }

    test('a long chapter stays one section with its title and id', () async {
      final paras = List.generate(1200, (i) => '<p>line $i</p>').join();
      final p = await load(book(
          '<section section-id="big"><title><p>Long</p></title>$paras</section>'));
      expect(p.section, hasLength(1));
      expect(p.section.single.title, 'Long');
      expect(p.section.single.sectionId, 'big');
      expect(p.section.single.p, hasLength(1200));

      final doc = await resave(p);
      final sections =
          doc.rootElement.findElements('body').first.findElements('section');
      expect(sections, hasLength(1));
      expect(sections.single.findElements('p'), hasLength(1200));
    });

    test('an image shown once stays once for a long chapter', () async {
      final paras = List.generate(900, (i) => '<p>x$i</p>').join();
      final p = await load(book(
          '<section section-id="s"><title><p>T</p></title><image l:href="#pic.jpg"/>$paras</section>'));
      final doc = await resave(p);
      expect(doc.rootElement.descendants.whereType<XmlElement>().where((e) => e.name.local == 'image'),
          hasLength(1));
    });

    test('a section with only a title is kept', () async {
      final p = await load(book(
          '<section section-id="a"><title><p>Part One</p></title></section>'
          '<section section-id="b"><title><p>Ch</p></title><p>text</p></section>'));
      expect(p.section.map((s) => s.title), ['Part One', 'Ch']);
    });

    test('a section with only a picture is kept', () async {
      final p = await load(book(
          '<section section-id="a"><image l:href="#pic.jpg"/></section>'));
      expect(p.section, hasLength(1));
      expect(p.section.single.pictureRefs, ['#pic.jpg']);
    });

    test('a section added in the app is still there after save and reload',
        () async {
      final p = await load(book('<section><title><p>One</p></title><p>x</p></section>'));
      p.addSection('Brand new');
      final again = await load(p.getBookXml() as String);
      expect(again.section.map((s) => s.title), ['One', 'Brand new']);
    });

    test('a book with no sections at all still opens', () async {
      final p = await load(book(''));
      expect(p.section, isEmpty);
    });
  });

  group('description parts the editor does not model survive a save', () {
    const full = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description>
<title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name><email>a@x.org</email></author>
<author><first-name>Bo</first-name><last-name>Kay</last-name></author>
<book-title>T</book-title><keywords>one, two</keywords><date value="2001-01-01">2001</date>
<lang>ru</lang><src-lang>en</src-lang>
<translator><first-name>Tim</first-name><last-name>Roe</last-name></translator>
<sequence name="S" number="2"/></title-info>
<document-info><author><nickname>scanner</nickname></author><program-used>P</program-used>
<date>2020</date><src-ocr>ocr</src-ocr><id>doc-1</id><version>1.1</version>
<history><p>fixed</p></history><publisher><nickname>pub</nickname></publisher></document-info>
<publish-info><publisher>House</publisher><year>1999</year></publish-info>
<custom-info info-type="x">note</custom-info>
</description>
<body><section><p>x</p></section></body></FictionBook>''';

    Future<XmlDocument> resave() async => XmlDocument.parse(
        ProjectModel.fromJson(await Fb2Service().convertXmlToJson(full)).getBookXml()
            as String);

    List<String> names(XmlElement e) => e.childElements.map((c) => c.name.local).toList();

    test('second author, translator, src-lang and keywords stay in schema order', () async {
      final info = _all(await resave(), 'title-info').single;
      expect(names(info), [
        'genre', 'author', 'author', 'book-title', 'keywords', 'date', 'lang',
        'src-lang', 'translator', 'sequence'
      ]);
      expect(info.findElements('author').last.innerText, contains('Kay'));
      expect(info.findElements('translator').single.innerText, contains('Roe'));
      expect(info.findElements('keywords').single.innerText, 'one, two');
      expect(info.findElements('author').first.findElements('email').single.innerText, 'a@x.org');
    });

    test('document-info keeps its own author, history and publisher', () async {
      final doc = _all(await resave(), 'document-info').single;
      expect(names(doc), [
        'author', 'program-used', 'date', 'src-url', 'src-ocr', 'id', 'version',
        'history', 'publisher'
      ]);
      expect(doc.findElements('author').single.innerText, 'scanner');
      expect(doc.findElements('id').single.innerText, 'doc-1');
    });

    test('publish-info and custom-info stay after document-info', () async {
      final d = await resave();
      final desc = d.rootElement.findElements('description').single;
      expect(names(desc), ['title-info', 'document-info', 'publish-info', 'custom-info']);
    });

    test('the author id is not overwritten by the document id', () async {
      final m = ProjectModel.fromJson(await Fb2Service().convertXmlToJson(full));
      expect(m.author.id, '');
      expect(m.getBookXml(), isNot(contains('<id>doc-1</id></author>')));
    });

    test('a second round trip is stable', () async {
      final first = (await resave()).toXmlString();
      final again = ProjectModel.fromJson(await Fb2Service().convertXmlToJson(first))
          .getBookXml() as String;
      expect(XmlDocument.parse(again).toXmlString(), first);
    });
  });

  group('a book created in the app', () {
    test('is valid FB2 with one empty chapter and survives a save', () async {
      final xml = newBookXml('Tom & Jerry', 'Chapter <1>');
      final m = ProjectModel.fromJson(await Fb2Service().convertXmlToJson(xml));
      expect(m.bookTitle, 'Tom & Jerry');
      expect(m.section.map((s) => s.title), ['Chapter <1>']);
      expect(m.section.single.p, isEmpty);
      expect(m.id, isNotEmpty);
      final again = ProjectModel.fromJson(
          await Fb2Service().convertXmlToJson(m.getBookXml() as String));
      expect(again.section.map((s) => s.title), ['Chapter <1>']);
      expect(again.id, m.id);
    });
  });

  group('pictures stay where the author put them', () {
    test('order of text and pictures survives open and save', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><book-title>T</book-title></title-info></description>
<body><section section-id="s"><title><p>T</p></title>
<p>one</p><image l:href="#a.jpg"/><p>two</p><image l:href="#b.jpg"/><p>three</p></section></body>
<binary content-type="image/jpeg" id="a.jpg">QUJD</binary>
<binary content-type="image/jpeg" id="b.jpg">QUJD</binary>
</FictionBook>''';
      final p = ProjectModel.fromJson(await Fb2Service().convertXmlToJson(xml));
      final out = XmlDocument.parse(p.getBookXml() as String);
      final kids = out.rootElement
          .findElements('body')
          .first
          .findElements('section')
          .first
          .childElements
          .map((e) => e.name.local == 'image'
              ? e.attributes.firstWhere((a) => a.name.local == 'href').value
              : e.innerText)
          .toList();
      expect(kids, ['T', 'one', '#a.jpg', 'two', '#b.jpg', 'three']);
    });
  });

  group('paragraph text survives a save', () {
    Future<List<String>> texts(String paragraphs) async {
      final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info><book-title>T</book-title></title-info></description>
<body><section section-id="s"><title><p>T</p></title>$paragraphs</section></body>
</FictionBook>''';
      final p = ProjectModel.fromJson(await Fb2Service().convertXmlToJson(xml));
      final out = XmlDocument.parse(p.getBookXml() as String);
      return out.rootElement
          .findElements('body')
          .first
          .findElements('section')
          .first
          .findElements('p')
          .map((e) => e.innerText)
          .toList();
    }

    test('backslash sequences in text are kept', () async {
      expect(await texts(r'<p>C:\temp\new and \r\n</p>'), [r'C:\temp\new and \r\n']);
    });

    test('a line wrapped inside a paragraph keeps the space', () async {
      expect(await texts('<p>line one\nline two</p>'), ['line one line two']);
    });

    test('pretty-printed paragraphs are not padded', () async {
      expect(await texts('<p>\n    text\n  </p>'), [' text ']);
    });

    test('indentation made of spaces and no-break spaces is kept', () async {
      expect(await texts('<p>\u00a0\u00a0\u00a0indented</p><p>   spaced</p>'),
          ['\u00a0\u00a0\u00a0indented', '   spaced']);
    });

    test('inline markup keeps the spaces around it', () async {
      expect(await texts('<p>a <strong>b</strong> c</p>'), ['a b c']);
    });
  });
}
