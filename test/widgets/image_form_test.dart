import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/widgets/forms/image.dart';

import '../support/form_harness.dart';

String _png(int w, int h) =>
    base64Encode(img.encodePng(img.Image(width: w, height: h)));

void main() {
  late FormHarness harness;
  setUp(() => harness = FormHarness());

  Future<void> pump(WidgetTester tester, String initial,
          {int? width, int? quality = 50}) =>
      harness.pump(
          tester,
          ImageFormField(
              name: 'cover',
              initialValue: initial,
              width: width,
              quality: quality));

  testWidgets('renders the cover with remove and change controls',
      (tester) async {
    await pump(tester, _png(4, 4));
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('base64Image can build an Image widget or a provider',
      (tester) async {
    await pump(tester, _png(4, 4));
    final field = tester.widget<ImageField>(find.byType(ImageField));
    expect(field.base64Image(_png(4, 4), false), isA<Image>());
    expect(field.base64Image(_png(4, 4), true), isA<MemoryImage>());
    expect(field.base64Image('', false), isA<Image>());
    expect(field.base64Image('', true), isA<AssetImage>());
  });

  testWidgets('keeps the initial image in the saved values', (tester) async {
    final png = _png(4, 4);
    await pump(tester, png);
    await harness.save(tester);
    expect(harness.lastValues['cover'], png);
  });

  testWidgets('remove clears the value', (tester) async {
    await pump(tester, _png(4, 4));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await harness.save(tester);
    expect(harness.lastValues['cover'], '');
  });

  testWidgets('an invalid image falls back to the placeholder without crashing',
      (tester) async {
    await pump(tester, '###');
    expect(find.text('Change'), findsOneWidget);
    await harness.save(tester);
    expect(harness.lastValues['cover'], '###');
  });

  group('picking an image', () {
    late Directory dir;
    String? picked;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('image_form_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      picked = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => picked,
      );
    });

    testWidgets('stores the picked file resized to the configured width',
        (tester) async {
      final file = File('${dir.path}/pic.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 40)));
      picked = file.path;
      await pump(tester, '', width: 10);
      await tester.tap(find.text('Change'));
      await settleIO(tester);
      await harness.save(tester);
      final value = harness.lastValues['cover'] as String;
      expect(img.decodeJpg(base64Decode(value))!.width, 10);
    });

    Future<List<int>> pickPng(WidgetTester tester) async {
      // Noise, so JPEG size actually depends on quality.
      final image = img.Image(width: 40, height: 40);
      var seed = 7;
      for (final p in image) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        p.setRgb(seed & 255, (seed >> 8) & 255, (seed >> 16) & 255);
      }
      final bytes = img.encodePng(image);
      picked = (File('${dir.path}/pic.png')..writeAsBytesSync(bytes)).path;
      return bytes;
    }

    testWidgets('quality 100 stores the original bytes without re-encoding',
        (tester) async {
      final bytes = await pickPng(tester);
      await pump(tester, '', width: 10, quality: 100);
      await tester.tap(find.text('Change'));
      await settleIO(tester);
      await harness.save(tester);
      expect(harness.lastValues['cover'], base64Encode(bytes));
    });

    testWidgets('the configured quality is honoured, not a fixed default',
        (tester) async {
      await pickPng(tester);
      Future<int> sizeAt(int quality) async {
        harness = FormHarness();
        await tester.pumpWidget(const SizedBox()); // drop previous state
        await pump(tester, '', width: 40, quality: quality);
        await tester.tap(find.text('Change'));
        await settleIO(tester);
        await harness.save(tester);
        return (harness.lastValues['cover'] as String).length;
      }

      final low = await sizeAt(10);
      final high = await sizeAt(90);
      expect(low, lessThan(high));
    });

    testWidgets('falls back to a default quality when none is given',
        (tester) async {
      await pickPng(tester);
      await pump(tester, '', width: 10, quality: null);
      await tester.tap(find.text('Change'));
      await settleIO(tester);
      await harness.save(tester);
      final value = harness.lastValues['cover'] as String;
      expect(img.decodeJpg(base64Decode(value))!.width, 10);
    });

    testWidgets('keeps the current value when the picker is cancelled',
        (tester) async {
      final png = _png(4, 4);
      await pump(tester, png);
      await tester.tap(find.text('Change'));
      await settleIO(tester);
      await harness.save(tester);
      expect(harness.lastValues['cover'], png);
    });
  });
}
