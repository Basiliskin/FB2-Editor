import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/cp1251.dart';

Uint8List _cp1251(String s) => Uint8List.fromList(s.codeUnits.map((c) {
      if (c < 0x80) return c;
      return cp1251.indexOf(String.fromCharCode(c));
    }).toList());

String _png64(int w, int h) =>
    base64Encode(img.encodePng(img.Image(width: w, height: h)));

void main() {
  group('decodeFb2Bytes', () {
    test('decodes UTF-8', () {
      expect(decodeFb2Bytes(utf8.encode('<?xml version="1.0" encoding="UTF-8"?>Привет')),
          endsWith('Привет'));
    });
    test('uses cp1251 when the header declares windows-1251', () {
      final bytes = _cp1251('<?xml version="1.0" encoding="windows-1251"?>Привет');
      expect(decodeFb2Bytes(bytes), endsWith('Привет'));
    });
    test('header match is case-insensitive and accepts single quotes / cp1251', () {
      expect(decodeFb2Bytes(_cp1251("<?xml version='1.0' encoding='Windows-1251'?>Да")),
          endsWith('Да'));
      expect(decodeFb2Bytes(_cp1251('<?xml encoding="cp1251"?>Да')), endsWith('Да'));
    });
    test('declared windows-1251 skips UTF-8 even for bytes that are valid UTF-8', () {
      // 0xD0 0x9F is a valid UTF-8 pair ("П") but cp1251 for "Рџ"
      final bytes = <int>[...ascii.encode('<?xml encoding="windows-1251"?>'), 0xD0, 0x9F];
      expect(decodeFb2Bytes(bytes), endsWith('\u0420\u045F'));
    });
    test('falls back to cp1251 for invalid UTF-8 with no declaration', () {
      expect(decodeFb2Bytes([0xCF, 0xF0, 0xE8]), 'При');
    });
    test('ignores an encoding mention past the first 200 bytes', () {
      final bytes = <int>[
        ...utf8.encode('${' ' * 300}<?xml encoding="windows-1251"?>Привет')
      ];
      expect(decodeFb2Bytes(bytes), endsWith('Привет'));
    });
    test('empty input', () => expect(decodeFb2Bytes(<int>[]), ''));
  });

  group('decodeCp1251', () {
    test('matches the lookup table for every byte value', () {
      final all = List<int>.generate(256, (i) => i);
      final out = decodeCp1251(all) as String;
      expect(out.length, 256);
      for (var i = 0; i < 256; i++) {
        expect(out[i], cp1251[i], reason: 'byte $i');
      }
    });
  });

  group('trimSpecialChar', () {
    test('removes doubled-escaped sequences as a unit', () {
      expect(trimSpecialChar(r'a\\nb\\tc\\rd'), 'abcd');
    });
    test('leaves unrelated backslashes alone', () {
      expect(trimSpecialChar(r'a\xb\\'), r'a\xb\\');
    });
    test('handles a large base64-like blob with wrapped lines', () {
      final blob = List.filled(2000, 'QUJDREVGRw==').join('\n');
      expect(trimSpecialChar(blob), isNot(contains('\n')));
      expect(trimSpecialChar(blob).length, 2000 * 12);
    });
  });

  group('timed', () {
    test('returns the body result', () async {
      expect(await timed('x', () async => 42), 42);
    });
    test('rethrows errors from the body', () async {
      await expectLater(
          timed('x', () async => throw StateError('boom')), throwsStateError);
    });
    test('logs the label and duration in debug builds', () async {
      final lines = <String?>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m);
      addTearDown(() => debugPrint = old);
      await timed('stage', () async => 1);
      expect(lines.single, matches(RegExp(r'^\[load\] stage: \d+ ms$')));
    });
  });

  group('resizeImage (native codec)', () {
    test('returns a JPEG scaled to the requested width', () async {
      final out = await resizeImage(_png64(80, 40), 20) as String;
      final decoded = img.decodeJpg(base64Decode(out))!;
      expect(decoded.width, 20);
      expect(decoded.height, 10);
    });
    test('accepts base64 wrapped across lines', () async {
      final b = _png64(40, 40);
      final wrapped = [
        for (var i = 0; i < b.length; i += 60) b.substring(i, (i + 60).clamp(0, b.length))
      ].join('\n');
      expect(await resizeImage(wrapped, 10), isNotNull);
    });
    test('returns null for invalid base64 and for non-image bytes', () async {
      expect(await resizeImage('!!!not base64!!!', 10), isNull);
      expect(await resizeImage(base64Encode([1, 2, 3]), 10), isNull);
      expect(await resizeImage('', 10), isNull);
    });
  });
}
