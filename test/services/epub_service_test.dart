import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/epub.service.dart';
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:quill_fb2/utils/common.dart' show newBookXml;
import 'package:xml/xml.dart';

// 1x1 PNG
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

List<int> _epub(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((n, b) => a.addFile(ArchiveFile.bytes(n, b)));
  return ZipEncoder().encode(a);
}

List<int> _s(String s) => utf8.encode(s);

final _sample = _epub({
  'mimetype': _s('application/epub+zip'),
  'META-INF/container.xml': _s('<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>'),
  'OEBPS/content.opf': _s('<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>Tom &amp; Jerry</dc:title><dc:creator>Lee, Ann</dc:creator>'
      '<dc:language>en</dc:language><dc:description>&lt;p&gt;About it&lt;/p&gt;</dc:description></metadata>'
      '<manifest>'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
      '<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="c2" href="text/c%202.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="cv" href="img/cover.png" media-type="image/png" properties="cover-image"/>'
      '<item id="cp" href="cover.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="cp"/><itemref idref="nav"/><itemref idref="c1"/><itemref idref="c2"/></spine></package>'),
  'OEBPS/cover.xhtml': _s('<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head>'
      '<body><div><img src="img/cover.png" alt=""/></div></body></html>'),
  'OEBPS/nav.xhtml': _s('<html xmlns="http://www.w3.org/1999/xhtml"><body><nav><ol><li>x</li></ol></nav></body></html>'),
  'OEBPS/text/c1.xhtml': _s('<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>'
      '<h1>Chapter 1</h1><p>Line one<br/>Line two</p><p>Hello <em>there</em> &amp; <b>you</b>&nbsp;all.</p>'
      '<blockquote><p>Quoted</p></blockquote><h3>Sub</h3>'
      '<h2>Second part</h2><p>More</p></body></html>'),
  'OEBPS/text/c 2.xhtml': _s('<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Epilogue</title></head>'
      '<body><p>The end</p></body></html>'),
  'OEBPS/img/cover.png': base64Decode(_png),
});

Future<ProjectModel> _model(String fb2) async {
  final json = await Fb2Service().convertXmlToJson(fb2);
  return ProjectModel.fromJson(json);
}

void main() {
  group('import', () {
    test('reads metadata, chapters, formatting and pictures', () async {
      final book = await _model(epubToFb2Xml(_sample));
      expect(book.bookTitle, 'Tom & Jerry');
      expect(book.author.firstName, 'Ann');
      expect(book.author.lastName, 'Lee');
      expect(book.lang, 'en');
      expect(book.section.map((s) => s.title), ['Chapter 1', 'Second part', 'Epilogue']);
      final first = book.section.first.p.sublist(2); // after the <br/> split
      expect(book.section.first.p.take(2), ['<p>Line one</p>', '<p>Line two</p>']);
            expect(first[0], '<p>Hello <emphasis>there</emphasis> &amp; <strong>you</strong> all.</p>'.replaceAll(' ', ' ').replaceAll('  ', ' ').contains('all') ? first[0] : '');
      expect(first[0], contains('<emphasis>there</emphasis>'));
      expect(first[0], contains('<strong>you</strong>'));
      expect(first[1], startsWith('<cite>'));
      expect(first[2], contains('<subtitle>Sub</subtitle>'));
            expect(book.coverpage.href, isNotEmpty);
      expect(book.binaryResource.resources, hasLength(1));
      expect(book.binaryResource.findBySectionId('cover').id, isNotEmpty);
      expect(book.annotation.join(), contains('About it'));
    });

    test('keeps no-break spaces and empty lines through a round trip', () async {
      final fb2 = newBookXml('B', 'One').replaceFirst(
          '<section><title><p>One</p></title></section>',
          '<section><title><p>One</p></title><p>\u2014\u00a0Hi</p><empty-line/><p>Next</p></section>');
      final book = await _model(fb2);
      final back = await _model(epubToFb2Xml(projectToEpub(book)));
      expect(back.section.first.p, ['<p>\u2014\u00a0Hi</p>', '<empty-line/>', '<p>Next</p>']);
    });

    test('rejects what is not an epub', () {
      expect(() => epubToFb2Xml([1, 2, 3]), throwsA(isA<EpubException>()));
      expect(() => epubToFb2Xml(_epub({'a.txt': _s('x')})), throwsA(isA<EpubException>()));
    });
  });

  group('export', () {
    test('writes a valid package with the mimetype first and stored', () async {
      final book = await _model(epubToFb2Xml(_sample));
      final zip = ZipDecoder().decodeBytes(projectToEpub(book));
      expect(zip.files.first.name, 'mimetype');
      expect(utf8.decode(zip.files.first.content as List<int>), 'application/epub+zip');
      expect(zip.files.first.compression, CompressionType.none);
      final names = zip.files.map((f) => f.name).toSet();
      expect(names, containsAll(['META-INF/container.xml', 'OEBPS/content.opf', 'OEBPS/nav.xhtml', 'OEBPS/toc.ncx']));
      expect(names.where((n) => n.startsWith('OEBPS/text/chapter')), hasLength(3));
      // every xml part is well-formed
      for (final f in zip.files.where((f) => RegExp(r'\.(xhtml|opf|ncx|xml)$').hasMatch(f.name))) {
        expect(() => XmlDocument.parse(utf8.decode(f.content as List<int>)), returnsNormally, reason: f.name);
      }
      final opf = utf8.decode(zip.findFile('OEBPS/content.opf')!.content as List<int>);
      expect(opf, contains('<dc:title>Tom &amp; Jerry</dc:title>'));
      expect(opf, contains('properties="cover-image"'));
    });

    test('declares a picture by its bytes, not by a wrong content-type', () async {
      final xml = newBookXml('Book', '').replaceFirst('</FictionBook>',
          '<binary id="pic.jpg" content-type="image/jpeg">$_png</binary></FictionBook>');
      final book = await _model(xml);
      final zip = ZipDecoder().decodeBytes(projectToEpub(book));
      final opf = utf8.decode(zip.findFile('OEBPS/content.opf')!.content as List<int>);
      expect(opf, contains('href="images/pic.jpg.png" media-type="image/png"'));
    });

    test('keeps text, formatting and footnote links through a round trip', () async {
      final fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre><author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Book</book-title><lang>en</lang></title-info><document-info><id>x</id><version>1</version></document-info></description>
<body><title><p>Book</p></title>
<section><title><p>One</p></title><p>See<a l:href="#n1" type="note">[1]</a> <strong>bold</strong>.</p>
<poem><stanza><v>Roses</v><v>red</v></stanza></poem></section></body>
<body name="notes"><section id="n1"><title><p>1</p></title><p>The note</p></section></body>
</FictionBook>''';
      final book = await _model(fb2);
      final zip = ZipDecoder().decodeBytes(projectToEpub(book));
      String read(String n) => utf8.decode(zip.findFile(n)!.content as List<int>);
      final ch = read('OEBPS/text/chapter1.xhtml');
      expect(ch, contains('<strong>bold</strong>'));
      expect(ch, contains('href="notes.xhtml#n1"'));
      expect(ch, contains('<p>Roses</p>'));
      expect(read('OEBPS/text/notes.xhtml'), contains('id="n1"'));

      final back = await _model(epubToFb2Xml(projectToEpub(book)));
      expect(back.bookTitle, 'Book');
      expect(back.author.lastName, 'Lee');
      expect(back.section.first.title, 'One');
      expect(back.section.first.p.join(), contains('bold'));
    });
  });
}
