import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/utils/common.dart' show imageHref;
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:quill_fb2/services/app.service.dart' show FileInfo;

const _fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Sample</book-title><lang>en</lang></title-info>
<document-info><id>doc-1</id></document-info></description>
<body><title><p>Sample</p></title><section><title><p>Ch</p></title><p>Hi</p></section></body>
</FictionBook>''';

class _Items {
  final List items;
  _Items(this.items);
}

String _png() => base64Encode(img.encodePng(img.Image(width: 20, height: 20)));

Future<ProjectModel> _model() async =>
    ProjectModel.fromJson(await Fb2Service().convertXmlToJson(_fb2));

Map _values({String cover = ''}) => {
      'bookCoverPage': cover,
      'authorFirst': 'Bob',
      'authorMid': 'M',
      'authorLast': 'Ray',
      'authorHomePage': 'x.org',
      'bookTitle': 'New title',
      'genre': _Items(['sf']),
      'sequence': _Items(['Saga']),
      'annotation': _Items(['<p>note</p>']),
    };

void main() {
  group('addSection', () {
    test('appends a section with the default title', () async {
      final m = await _model();
      final before = m.section.length;
      final s = m.addSection();
      expect(m.section.length, before + 1);
      expect(m.section.last, same(s));
    });
    test('uses a custom title', () async {
      final s = (await _model()).addSection('Custom');
      expect(s.title, 'Custom');
    });
  });

  group('getInfo', () {
    test('describes the book using the given path', () async {
      final info = await (await _model()).getInfo(null, '/books/x.fb2');
      expect(info['path'], '/books/x.fb2');
      expect(info['title'], 'Sample');
      expect(info['author'], 'Ann Lee');
      expect(info['lang'], 'en');
      expect(info['cover'], '');
    });
    test('moves the source file when a path is given', () async {
      final dir = Directory.systemTemp.createTempSync('info_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final src = File('${dir.path}/src.fb2')..writeAsStringSync('x');
      final info = await (await _model())
          .getInfo(FileInfo('x', src.path), '${dir.path}/dst.fb2');
      expect(File('${dir.path}/dst.fb2').existsSync(), isTrue);
      expect(src.existsSync(), isFalse);
      expect(info['path'], '${dir.path}/dst.fb2');
    });
    test('falls back to the file path when no path is given', () async {
      final info = await (await _model()).getInfo(FileInfo('x', '/tmp/f.fb2'));
      expect(info['path'], '/tmp/f.fb2');
    });
  });

  group('updateInfo file and language fields', () {
    test('id, version, language, date, keywords and e-mail are saved', () async {
      final m = (await _model())
        ..updateInfo({
          ..._values(),
          'bookId': 'new-id',
          'bookVersion': '2.3',
          'bookLang': ' ru ',
          'bookDate': '1999',
          'bookKeywords': 'a, b',
          'authorEmail': 'me@x.org',
        });
      final xml = m.getBookXml() as String;
      expect(xml, contains('<id>new-id</id>'));
      expect(xml, contains('<version>2.3</version>'));
      expect(xml, contains('<lang>ru</lang>'));
      expect(xml, contains('<date>1999</date>'));
      expect(xml, contains('<keywords>a, b</keywords>'));
      expect(xml, contains('<email>me@x.org</email>'));
      // and they come back after a reload
      final again = ProjectModel.fromJson(await Fb2Service().convertXmlToJson(xml));
      expect([again.id, again.version, again.lang, again.date, again.keywords, again.author.email],
          ['new-id', '2.3', 'ru', '1999', 'a, b', 'me@x.org']);
    });

    test('leaving them out keeps the current values', () async {
      final m = (await _model())..updateInfo(_values());
      expect([m.id, m.lang], ['doc-1', 'en']);
    });

    test('list fields the form has not built yet keep their values', () async {
      final m = await _model();
      final before = [m.genre, m.sequence, m.annotation];
      m.updateInfo({..._values(), 'genre': null, 'sequence': null, 'annotation': null});
      expect([m.genre, m.sequence, m.annotation], before);
      expect(m.bookTitle, 'New title');
    });

    test('values with markup characters are escaped', () async {
      final m = (await _model())
        ..updateInfo({..._values(), 'bookKeywords': 'a<b & c', 'bookId': 'x&y'});
      final again = ProjectModel.fromJson(
          await Fb2Service().convertXmlToJson(m.getBookXml() as String));
      expect([again.keywords, again.id], ['a<b & c', 'x&y']);
    });

    test('empty optional author parts are not written', () async {
      final m = (await _model())..updateInfo({..._values(), 'authorMid': '', 'authorHomePage': ''});
      final xml = m.getBookXml() as String;
      expect(xml, isNot(contains('<middle-name>')));
      expect(xml, isNot(contains('<home-page>')));
      expect(xml, isNot(contains('<nickname>')));
    });
  });

  group('updateInfo', () {
    test('updates title, author, genre, sequence and annotation', () async {
      final m = (await _model())..updateInfo(_values());
      expect(m.getBookTitle(), 'New title');
      expect(m.getAuthor(), 'Bob Ray');
      expect(m.genre, ['sf']);
      expect(m.getSequence(), 'Saga');
      expect(m.annotation, ['<p>note</p>']);
    });
    test('clears the cover reference for an empty cover', () async {
      final m = (await _model())..updateInfo(_values());
      expect(m.coverpage.href, '');
    });
    test('stores a new cover image under the cover section id', () async {
      final m = (await _model())..updateInfo(_values(cover: _png()));
      expect(m.coverpage.href, startsWith('#'));
      expect(m.getImageBySectionId('cover'), _png());
    });
    test('replaces the previous cover instead of duplicating it', () async {
      final m = (await _model())
        ..updateInfo(_values(cover: _png()))
        ..updateInfo(_values(cover: _png()));
      expect(
          m.binaryResource.resources.where((r) => r.sectionId == 'cover'),
          hasLength(1));
    });
  });

  group('cover type and identity', () {
    String png() => base64Encode(img.encodePng(img.Image(width: 8, height: 8)));
    String jpg() => base64Encode(img.encodeJpg(img.Image(width: 8, height: 8)));

    test('a PNG cover is saved as image/png with a matching id', () async {
      final m = (await _model())..updateInfo(_values(cover: png()));
      final r = m.binaryResource.findBySectionId('cover');
      expect(r.contentType, 'image/png');
      expect(r.id, endsWith('.png'));
      expect(r.id, isNot(contains('.png.png')));
      expect(m.coverpage.href, '#${r.id}');
      expect(m.getBookXml(), contains('<coverpage><image l:href="#${r.id}"'));
      expect(m.getBookXml(), contains('content-type="image/png" id="${r.id}"'));
    });

    test('a JPEG cover stays image/jpeg', () async {
      final m = (await _model())..updateInfo(_values(cover: jpg()));
      final r = m.binaryResource.findBySectionId('cover');
      expect([r.contentType, r.id.split('.').last], ['image/jpeg', 'jpg']);
    });

    test('saving again without touching the cover keeps id and bytes', () async {
      final m = (await _model())..updateInfo(_values(cover: png()));
      final before = m.binaryResource.findBySectionId('cover');
      final id = before.id;
      m.updateInfo(_values(cover: png()));
      final after = m.binaryResource.findBySectionId('cover');
      expect([after.id, after.data], [id, png()]);
      expect(m.coverpage.href, '#$id');
    });

    test('a different picture gets a new id so readers drop the old one', () async {
      final m = (await _model())..updateInfo(_values(cover: png()));
      final id = m.binaryResource.findBySectionId('cover').id;
      m.updateInfo(_values(cover: jpg()));
      final r = m.binaryResource.findBySectionId('cover');
      expect(r.id, isNot(id));
      expect(m.coverpage.href, '#${r.id}');
      expect(m.binaryResource.resources.where((e) => e.sectionId == 'cover'), hasLength(1));
    });

    test('a section picture keeps its real type too', () async {
      final m = await _model();
      final s = m.addSection();
      m.addSecionImage(s, png());
      expect(m.binaryResource.findBySectionId(s.sectionId).contentType, 'image/png');
    });
  });

  group('toPlainText', () {
    test('title, author, section titles and paragraphs; no markup, pictures or empties', () async {
      final m = await _model();
      m.section.clear();
      m.addSection('One').p = [
        '<p>Hello <strong>big</strong> &amp; world</p>',
        '<image xlink:href="#x.jpg"/>',
        '<p>   </p>',
        '<poem><stanza><v>a</v><v>b</v></stanza><stanza><v>c</v></stanza></poem>',
      ];
      m.addSection('Two').p = ['<p>end</p>'];
      expect(m.toPlainText(),
          'Sample\nAnn Lee\n\nOne\n\nHello big & world\n\na\nb\n\nc\n\nTwo\n\nend\n');
    });
  });

  group('inline pictures', () {
    String png() => base64Encode(img.encodePng(img.Image(width: 8, height: 8)));

    test('a picture goes after the given paragraph with its real type', () async {
      final m = await _model();
      final s = m.addSection()..p = ['<p>a</p>', '<p>b</p>'];
      final at = m.addInlineImage(s, png(), 0);
      expect(at, 1);
      expect(s.p[0], '<p>a</p>');
      expect(imageHref(s.p[1]), isNotNull);
      expect(s.p[2], '<p>b</p>');
      final res = m.binaryResource.find(imageHref(s.p[1])!);
      expect([res.contentType, res.sectionId], ['image/png', s.sectionId]);
    });

    test('several pictures fit in one section and all are saved', () async {
      final m = await _model();
      final s = m.addSection()..p = ['<p>a</p>'];
      m.addInlineImage(s, png(), 0);
      m.addInlineImage(s, png(), -1);
      expect(s.pictureRefs, hasLength(2));
      final xml = m.getBookXml() as String;
      expect(RegExp('<image ').allMatches(xml).length, 2);
      expect('<binary '.allMatches(xml).length, 2);
    });

    test('removing a picture frees its data', () async {
      final m = await _model();
      final s = m.addSection()..p = ['<p>a</p>'];
      m.addInlineImage(s, png(), 0);
      m.removeInlineImage(s, 1);
      expect(s.p, ['<p>a</p>']);
      expect(m.binaryResource.resources, isEmpty);
    });

    test('empty data adds nothing', () async {
      final m = await _model();
      final s = m.addSection();
      expect(m.addInlineImage(s, '', 0), -1);
      expect(s.p, isEmpty);
    });
  });

  group('addSecionImage', () {
    test('sets and then clears the section image', () async {
      final m = await _model();
      final s = m.addSection();
      m.addSecionImage(s, _png());
      expect(m.getImageBySectionId(s.sectionId), _png());
      m.addSecionImage(s, '');
      expect(m.getImageBySectionId(s.sectionId), '');
    });
  });

  group('getCoverPageImage', () {
    test('returns a resized thumbnail when a cover is set', () async {
      final m = (await _model())..updateInfo(_values(cover: _png()));
      final thumb = await m.getCoverPageImage();
      expect(img.decodeJpg(base64Decode(thumb))!.width, 120);
    });
  });

  group('cover thumbnail cache', () {
    String png(int w, [int? h]) =>
        base64Encode(img.encodePng(img.Image(width: w, height: h ?? w)));

    test('reuses the thumbnail while the cover data is unchanged', () async {
      final m = (await _model())..updateInfo(_values(cover: png(300)));
      final res = m.binaryResource.findBySectionId('cover');
      final first = await m.getImage(res);
      final second = await m.getImage(res);
      expect(identical(first, second), isTrue);
    });

    test('regenerates the thumbnail when the cover changes', () async {
      final m = (await _model())..updateInfo(_values(cover: png(300)));
      final first = await m.getCoverPageImage();
      m.updateInfo(_values(cover: png(300, 150)));
      final second = await m.getCoverPageImage();
      expect(second, isNot(first));
      final decoded = img.decodeJpg(base64Decode(second))!;
      expect([decoded.width, decoded.height], [120, 60]);
    });

    test('getInfo twice returns the same cover thumbnail', () async {
      final m = (await _model())..updateInfo(_values(cover: png(300)));
      final a = await m.getInfo(null, '/a.fb2');
      final b = await m.getInfo(null, '/a.fb2');
      expect(b['cover'], a['cover']);
    });
  });
}
