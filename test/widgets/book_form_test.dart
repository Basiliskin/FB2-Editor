import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/forms/book_form.dart';

import '../support/form_harness.dart';

const _fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Sample</book-title><annotation><p>About it</p></annotation><lang>en</lang></title-info>
<document-info><id>doc-1</id><version>2.0</version></document-info></description>
<body><title><p>Sample</p></title><section><title><p>Ch</p></title><p>Hi</p></section></body>
</FictionBook>''';

void main() {
  late AppService service;
  late Directory docs;
  late ProjectModel book;
  late StreamController<void> trigger;

  setUp(() async {
    docs = mockDocumentsDir();
    service = AppService();
    book = ProjectModel.fromJson(await service.convertXmlToJson(_fb2));
    trigger = StreamController<void>.broadcast();
    addTearDown(trigger.close);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookComponent(service, book, trigger.stream))));
  }

  Future<void> save(WidgetTester tester) async {
    trigger.add(null);
    await settleIO(tester);
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('shows the book metadata in the fields', (tester) async {
    await pump(tester);
    expect(find.text('Sample'), findsWidgets);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Lee'), findsOneWidget);
    expect(find.text('Prose'), findsOneWidget); // genre chip
    expect(find.text('About it'), findsOneWidget);
    expect(find.text('2.0'), findsOneWidget);
    expect(find.text('doc-1'), findsOneWidget);
  });

  testWidgets('saving applies edits to the model and writes the book',
      (tester) async {
    await pump(tester);
    await tester.enterText(field('Book Title'), 'New title');
    await tester.enterText(field('First'), 'Bob');
    await save(tester);

    expect(book.bookTitle, 'New title');
    expect(book.author.firstName, 'Bob');
    expect(book.author.lastName, 'Lee');
    final file = File('${docs.path}/${book.projectId}.fb2');
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('New title'));
    expect(service.workspace['history'], hasLength(1));
    expect(service.workspace['history'].first['title'], 'New title');
  });

  testWidgets('saving shows a confirmation with the title', (tester) async {
    await pump(tester);
    await save(tester);
    expect(find.textContaining('New title'), findsNothing);
    expect(find.textContaining('Sample: Saved in the app'), findsOneWidget);
  });

  testWidgets('genre edits are saved', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Enter Genre'), 'sf');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.widgetWithText(InputChip, 'Prose'),
        matching: find.byIcon(Icons.clear)));
    await tester.pump();
    await save(tester);
    expect(book.genre, ['sf']);
  });

  testWidgets('saving twice keeps a single history entry', (tester) async {
    await pump(tester);
    await save(tester);
    await save(tester);
    expect(service.workspace['history'], hasLength(1));
  });
}
