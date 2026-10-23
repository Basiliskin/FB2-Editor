import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/pages/book_page.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/services/app.service.dart';

import '../support/form_harness.dart';

const _fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Sample</book-title><lang>en</lang></title-info>
<document-info><id>doc-1</id></document-info></description>
<body><section><title><p>Ch</p></title><p>Hi</p></section></body>
</FictionBook>''';

/// Keeps the page off the disk and records what it was asked to do.
class _FakeService extends AppService {
  int saves = 0;
  final exported = <ProjectModel>[];

  @override
  saveProject(ProjectModel model) async => saves++;

  @override
  exportProject(ProjectModel model) async {
    exported.add(model);
    return '/exported/book.fb2';
  }

  @override
  setSettings(settings) async {
    for (final e in (settings as Map).entries) {
      getSettings()[e.key] = e.value;
    }
  }
}

void main() {
  late _FakeService service;
  late ProjectModel book;

  setUp(() async {
    mockDocumentsDir();
    service = _FakeService();
    book = ProjectModel.fromJson(await service.convertXmlToJson(_fb2));
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: BookPage(service, book, StreamController<void>.broadcast())));
    await tester.pump();
  }

  Future<void> openSectionsTab(WidgetTester tester) async {
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
  }

  Future<void> addSection(WidgetTester tester, String title) async {
    await tester.tap(find.text('New section'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, title);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows the title and author in the app bar', (tester) async {
    await pump(tester);
    expect(find.text('Sample'), findsWidgets);
    expect(find.text(book.getAuthor()), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('reacts to app lifecycle changes without errors', (tester) async {
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('resultsCallback accepts a results map', (tester) async {
    await pump(tester);
    (tester.state(find.byType(BookPage)) as dynamic).resultsCallback({'a': 'b'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('the help button opens the help screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets('the auto-save button toggles the setting', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Auto-save: off'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await tester.pumpAndSettle();
    expect(service.getSettings()['auto-save'], true);
    expect(find.byTooltip('Auto-save: on'), findsOneWidget);
    expect(service.saves, greaterThan(0)); // change notification saved the book
  });

  testWidgets('the save button asks the book to be saved', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();
    expect(service.saves, greaterThan(0));
  });

  testWidgets('export reports where the file was saved', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.storage_outlined));
    await tester.pumpAndSettle();
    expect(service.exported, [book]);
    expect(find.textContaining('/exported/book.fb2'), findsOneWidget);
  });

  testWidgets('tapping a tab saves, and the FAB only shows on sections',
      (tester) async {
    await pump(tester);
    await openSectionsTab(tester);
    expect(service.saves, greaterThan(0));
    expect(find.text('New section'), findsOneWidget);
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('New section'), findsNothing);
  });

  testWidgets('a new section is added and announced', (tester) async {
    await pump(tester);
    await openSectionsTab(tester);
    final before = book.section.length;
    await addSection(tester, 'Fresh');
    expect(book.section.length, before + 1);
    // snackbars queue: let the earlier "Saved" one go before ours shows
    for (var i = 0; i < 5 && find.text('Fresh Created').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Fresh Created'), findsOneWidget);
  });

  testWidgets('cancelling the name prompt adds nothing', (tester) async {
    await pump(tester);
    await openSectionsTab(tester);
    final before = book.section.length;
    await tester.tap(find.text('New section'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(book.section.length, before);
    await tester.pumpAndSettle(); // lets any queued snackbar play out
    expect(find.textContaining('Created'), findsNothing);
  });

  testWidgets('selected sections are deleted with the FAB', (tester) async {
    await pump(tester);
    await openSectionsTab(tester);
    await addSection(tester, 'Extra');
    final before = book.section.length;

    await tester.tap(find.byTooltip('Select').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete 1'), findsOneWidget);

    // selecting again unselects
    await tester.tap(find.byTooltip('Select').first);
    await tester.pumpAndSettle();
    expect(find.text('New section'), findsOneWidget);

    await tester.tap(find.byTooltip('Select').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete 1'));
    await tester.pumpAndSettle();
    expect(book.section.length, before - 1);
    expect(find.text('New section'), findsOneWidget);
  });

  testWidgets('uses Russian labels when the language is ru', (tester) async {
    service.getSettings()['language'] = 'ru';
    await pump(tester);
    expect(find.byTooltip('Справка'), findsOneWidget);
    expect(find.byTooltip('Автосохранение: выкл'), findsOneWidget);
    expect(find.byTooltip('Экспорт .fb2'), findsOneWidget);
  });
}
