import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:xml/xml.dart';

/// A [File] whose rename always fails, forcing [moveFile] to copy.
class _NoRenameFile implements File {
  _NoRenameFile(this.inner);
  final File inner;

  @override
  Future<File> rename(String newPath) => throw const FileSystemException('x');

  @override
  Future<File> copy(String newPath) => inner.copy(newPath);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('timed runs the body and returns its value', () async {
    expect(await timed('x', () async => 42), 42);
  });

  test('colorPalette covers every shade', () {
    expect(colorPalette.keys, hasLength(10));
    expect(colorPalette[900], isNotNull);
  });

  group('prepareList / prepareJSon', () {
    test('converts nested dates, maps and lists; keeps plain values', () {
      final d = DateTime.utc(2020, 1, 2);
      final out = prepareList([
        d,
        <String, dynamic>{'k': d},
        [d],
        'plain',
        1
      ]);
      expect(out[0], d.toString());
      expect(out[1], {'k': d.toString()});
      expect(out[2], [d.toString()]);
      expect(out[3], 'plain');
      expect(out[4], 1);
    });
  });

  group('resizeImage fallback', () {
    test('falls back to the pure-Dart path when the codec cannot decode',
        () async {
      // TGA is decoded by package:image but not by the engine codec.
      final tga = base64Encode(img.encodeTga(img.Image(width: 40, height: 20)));
      final out = await resizeImage(tga, 10);
      expect(out, isNotNull);
      expect(img.decodeJpg(base64Decode(out))!.width, 10);
    });
  });

  group('moveFile', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('common_extra'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('copies when rename fails', () async {
      final src = File('${dir.path}/a.txt')..writeAsStringSync('hi');
      final moved = await moveFile(_NoRenameFile(src), '${dir.path}/b.txt');
      expect(moved.readAsStringSync(), 'hi');
    });
  });

  test('readyAscii falls back to ascii which rejects wide values', () {
    expect(readyAscii([104, 105]), 'hi');
    expect(() => readyAscii([300]), throwsFormatException);
  });

  group('parseXml / parseSectionXml', () {
    test('keeps inline elements and mixed text in paragraphs', () {
      final doc = XmlDocument.parse(
          '<FictionBook><body><section><p>hello <strong>b</strong></p>'
          '<p><emphasis>only</emphasis></p></section></body></FictionBook>');
      final s = (parseSectionXml(doc) as List).single as Map;
      final p = (s['p'] as List).cast<String>();
      expect(p[0], contains('hello '));
      expect(p[0], contains('<strong>b</strong>'));
      expect(p[1], contains('<emphasis>only</emphasis>'));
    });

    test('keeps nested inline elements and plain text', () {
      final doc = XmlDocument.parse(
          '<FictionBook><body><section><p>plain</p>'
          '<p><strong><emphasis>deep</emphasis> tail</strong></p>'
          '</section></body></FictionBook>');
      final s = (parseSectionXml(doc) as List).single as Map;
      final p = (s['p'] as List).cast<String>();
      expect(p[0], '<p>plain</p>');
      expect(p[1], '<p><strong><emphasis>deep</emphasis> tail</strong></p>');
    });

    test('a section that fails to parse yields null', () {
      final doc = XmlDocument.parse(
          '<FictionBook><body><section><image/></section></body></FictionBook>');
      expect(parseSectionXml(doc) as List, [null]);
    });
  });
}
