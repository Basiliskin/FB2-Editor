import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/find_replace_dialog.dart';

void main() {
  late ProjectModel book;
  bool? result;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    book = ProjectModel.fromJson({'title': 'B', 'section': []});
    book.addSection('Ch').p = ['<p>one cat</p>', '<p>cat two</p>', '<p>none</p>'];
    result = null;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => TextButton(
                onPressed: () async =>
                    result = await showFindReplace(c, AppService(), book),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('typing lists the hits and counts them', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'cat');
    await tester.pump();
    expect(find.text('Found: 2 in 2 places'), findsOneWidget);
    expect(find.text('Replace'), findsNWidgets(2));
  });

  testWidgets('Replace all changes the book and reports it on close', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'cat');
    await tester.enterText(find.widgetWithText(TextField, 'Replace with'), 'dog');
    await tester.pump();
    await tester.tap(find.text('Replace all'));
    await tester.pump();
    expect(book.section.single.p, ['<p>one dog</p>', '<p>dog two</p>', '<p>none</p>']);
    expect(find.text('Replaced: 2'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Replace on one hit changes only that paragraph', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'cat');
    await tester.enterText(find.widgetWithText(TextField, 'Replace with'), 'dog');
    await tester.pump();
    await tester.tap(find.text('Replace').first);
    await tester.pump();
    expect(book.section.single.p, ['<p>one dog</p>', '<p>cat two</p>', '<p>none</p>']);
    expect(find.text('Replace'), findsOneWidget);
  });

  testWidgets('closing without replacing reports no change', (tester) async {
    await open(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('match case toggles the result', (tester) async {
    await open(tester);
    book.section.single.p = ['<p>Cat cat</p>'];
    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'cat');
    await tester.pump();
    expect(find.text('Found: 2 in 1 places'), findsOneWidget);
    await tester.tap(find.text('Match case'));
    await tester.pump();
    expect(find.text('Found: 1 in 1 places'), findsOneWidget);
  });
}
