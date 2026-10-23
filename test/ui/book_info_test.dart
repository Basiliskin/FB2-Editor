import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/book_info.dart';

String _fb2(String png) => '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Sample</book-title><coverpage><image l:href="#c.jpg"/></coverpage><lang>en</lang></title-info>
<document-info><id>doc-1</id></document-info></description>
<body><section><title><p>Ch</p></title><p>Hi</p></section></body>
<binary id="c.jpg" content-type="image/png">$png</binary>
</FictionBook>''';

void main() {
  late AppService service;
  final png = base64Encode(img.encodePng(img.Image(width: 4, height: 4)));

  late ProjectModel covered;

  // parsing runs in an isolate, so it must happen outside the widget zone
  setUp(() async {
    service = AppService();
    covered = ProjectModel.fromJson(await service.convertXmlToJson(_fb2(png)));
  });

  InfoKit kit(ProjectModel book) => InfoKit(service, book,
      text: (item, value, {style, maxLines = 1, flat = false}) =>
          Text('text:${item.name}=$value'),
      cover: (w) => Text('cover:$w'),
      labels: (name, hint, items) => Text('labels:$name:${items.join(',')}'),
      annotation: () => const Text('annotation'));

  Future<void> pump(WidgetTester tester, InfoKit k) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BookInfoLayout(k))));
  }

  test('InfoKit.title trims special characters from the book title', () {
    final book = covered;
    expect(kit(book).title, 'Sample');
  });

  testWidgets('InfoKit.caption upper-cases the label', (tester) async {
    final book = covered;
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) => kit(book).caption(c, 'Genre'))));
    expect(find.text('GENRE'), findsOneWidget);
  });

  testWidgets('lays out every section with the supplied fields',
      (tester) async {
    final book = covered;
    await pump(tester, kit(book));
    for (final caption in [
      'TITLE', 'AUTHOR', 'GENRE', 'SERIES', 'ANNOTATION', 'BOOK DETAILS', 'FILE INFO',
    ]) {
      expect(find.text(caption), findsOneWidget);
    }
    expect(find.text('cover:132.0'), findsOneWidget);
    expect(find.text('annotation'), findsOneWidget);
    expect(find.text('text:bookTitle=Sample'), findsOneWidget);
    expect(find.text('text:authorFirst=Ann'), findsOneWidget);
    expect(find.text('text:authorLast=Lee'), findsOneWidget);
    expect(find.textContaining('labels:genre:'), findsOneWidget);
    expect(find.textContaining('labels:sequence:'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(5));
  });

  testWidgets('uses Russian captions when the language is ru',
      (tester) async {
    service.getSettings()['language'] = 'ru';
    final book = covered;
    await pump(tester, kit(book));
    expect(find.text('НАЗВАНИЕ'), findsOneWidget);
    expect(find.text('АВТОР'), findsOneWidget);
  });

  testWidgets('paints the cover as a darkened banner background',
      (tester) async {
    final book = covered;
    expect(book.getImageBySectionId('cover'), isNotEmpty);
    await pump(tester, kit(book));
    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    final banner = decorations.firstWhere((d) => d.image != null);
    expect(banner.image!.image, isA<MemoryImage>());
    expect(banner.image!.fit, BoxFit.cover);
  });

  testWidgets('has a plain banner when the book has no cover',
      (tester) async {
    final book = ProjectModel.fromJson({'title': 'B', 'section': []});
    expect(book.getImageBySectionId('cover'), '');
    await pump(tester, kit(book));
    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    expect(decorations.any((d) => d.image != null), isFalse);
    expect(decorations.any((d) => d.color != null), isTrue);
  });
}
