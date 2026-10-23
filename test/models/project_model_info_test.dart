import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/models/project.model.dart';
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
}
