import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/utils/common.dart';

String _pngBase64(int w, int h) =>
    base64Encode(img.encodePng(img.Image(width: w, height: h)));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('common_io_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('trimSpecialChar', () {
    test('returns empty string for null', () => expect(trimSpecialChar(null), ''));
    test('strips real and escaped newlines, tabs and carriage returns', () {
      expect(trimSpecialChar('a\nb\tc\rd'), 'abcd');
      expect(trimSpecialChar(r'a\nb\tc\rd'), 'abcd');
    });
    test('replaces with the given character', () {
      expect(trimSpecialChar('a\nb', ' '), 'a b');
    });
  });

  group('toBeginningOfSentenceCase', () {
    test('capitalizes the first letter', () {
      expect(toBeginningOfSentenceCase('hello'), 'Hello');
    });
    test('passes null and empty through', () {
      expect(toBeginningOfSentenceCase(null), isNull);
      expect(toBeginningOfSentenceCase(''), '');
    });
  });

  group('resizeImage', () {
    test('returns a JPEG scaled to the requested width', () async {
      final out = await resizeImage(_pngBase64(40, 20), 10);
      final decoded = img.decodeJpg(base64Decode(out))!;
      expect(decoded.width, 10);
      expect(decoded.height, 5);
    });
    test('returns null for data that is not an image', () async {
      expect(await resizeImage(base64Encode([1, 2, 3]), 10), isNull);
    });
  });

  group('resizeImageBytes', () {
    test('returns the input untouched at 100 quality', () async {
      final bytes = base64Decode(_pngBase64(8, 8));
      expect(await resizeImageBytes(bytes, 4, 100), same(bytes));
    });
    test('re-encodes as base64 JPEG below 100 quality', () async {
      final bytes = img.encodePng(img.Image(width: 40, height: 40));
      final out = await resizeImageBytes(bytes, 10, 50);
      expect(img.decodeJpg(base64Decode(out))!.width, 10);
    });
    test('falls back to the input bytes when decoding fails', () async {
      final bytes = [1, 2, 3];
      expect(await resizeImageBytes(bytes, 10, 50), same(bytes));
    });
  });

  group('moveFile / moveFileTo', () {
    test('moveFile renames the file', () async {
      final src = File('${dir.path}/a.txt')..writeAsStringSync('hi');
      final moved = await moveFile(src, '${dir.path}/b.txt');
      expect(src.existsSync(), isFalse);
      expect(moved.readAsStringSync(), 'hi');
    });
    test('moveFileTo keeps the base name in the target dir', () async {
      final target = Directory('${dir.path}/t')..createSync();
      final src = File('${dir.path}/a.txt')..writeAsStringSync('hi');
      final moved = await moveFileTo(src.path, target.path);
      expect(moved.path, '${target.path}/a.txt');
      expect(moved.readAsStringSync(), 'hi');
    });
  });

  group('readAsString', () {
    test('decodes UTF-8', () async {
      final f = File('${dir.path}/u.txt')..writeAsStringSync('Привет');
      expect(await readAsString(f), 'Привет');
    });
    test('falls back to cp1251 for invalid UTF-8', () async {
      // "При" in windows-1251
      final f = File('${dir.path}/c.txt')..writeAsBytesSync([0xCF, 0xF0, 0xE8]);
      expect(await readAsString(f), 'При');
    });
  });

  test('readFileByte reads the file contents', () async {
    final f = File('${dir.path}/r.bin')..writeAsBytesSync([1, 2, 3]);
    expect(await readFileByte(f.path), [1, 2, 3]);
  });

  test('readyAscii decodes latin1', () {
    expect(readyAscii([0x68, 0x69]), 'hi');
  });

  test('getXmlText returns the root inner text', () {
    expect(getXmlText('<r>a<b>c</b></r>'), 'ac');
  });
}
