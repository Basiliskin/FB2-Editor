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
  String? exportResult = '/exported/book.fb2';
  dynamic openResult;
  Object? openThrows;

  @override
  saveProject(ProjectModel model) async => saves++;

  @override
  exportProject(ProjectModel model) async {
    exported.add(model);
    return exportResult;
  }

  final epubExported = <ProjectModel>[];
  final textExported = <ProjectModel>[];

  @override
  Future<String?> exportEpub(ProjectModel model) async {
    epubExported.add(model);
    return '/exported/book.epub';
  }

  @override
  Future<String?> exportText(ProjectModel model) async {
    textExported.add(model);
    return '/exported/book.txt';
  }

  @override
  openFile(Map extensionNames) async {
    if (openThrows != null) throw openThrows!;
    return openResult;
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

  Future<void> openSaveExport(WidgetTester tester) async {
    await tester.tap(find.text('Save & export'));
    await tester.pumpAndSettle();
  }

  testWidgets('Save & export offers saving and every format with its file name',
      (tester) async {
    await pump(tester);
    await openSaveExport(tester);
    expect(find.text('Save in the app'), findsOneWidget);
    expect(find.text('FB2  ·  Lee Ann - Sample.fb2'), findsOneWidget);
    expect(find.text('EPUB  ·  Lee Ann - Sample.epub'), findsOneWidget);
    expect(find.text('TXT  ·  Lee Ann - Sample.txt'), findsOneWidget);
  });

  testWidgets('Save & export says the book is saved', (tester) async {
    await pump(tester);
    service.markSaved(book);
    await openSaveExport(tester);
    expect(find.text('Saved in the app'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);
  });

  testWidgets('Save & export warns about unsaved changes', (tester) async {
    await pump(tester);
    service.markSaved(book);
    book.bookTitle = 'Changed';
    await openSaveExport(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('"Save in the app" asks the book to be saved', (tester) async {
    await pump(tester);
    await openSaveExport(tester);
    await tester.tap(find.text('Save in the app'));
    await tester.pumpAndSettle();
    expect(service.saves, greaterThan(0));
  });

  testWidgets('the EPUB tile exports an epub and says where', (tester) async {
    await pump(tester);
    await openSaveExport(tester);
    await tester.tap(find.textContaining('EPUB  ·'));
    await tester.pumpAndSettle();
    expect(service.epubExported, [book]);
    expect(find.textContaining('/exported/book.epub'), findsOneWidget);
  });

  testWidgets('the TXT tile exports plain text', (tester) async {
    await pump(tester);
    await openSaveExport(tester);
    await tester.tap(find.textContaining('TXT  ·'));
    await tester.pumpAndSettle();
    expect(service.textExported, [book]);
    expect(find.textContaining('/exported/book.txt'), findsOneWidget);
  });

  testWidgets('on a narrow screen Save & export is an icon with a tooltip', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: BookPage(service, book, StreamController<void>.broadcast())));
    await tester.pump();
    expect(find.text('Save & export'), findsNothing);
    await tester.tap(find.byTooltip('Save & export'));
    await tester.pumpAndSettle();
    expect(find.text('Save in the app'), findsOneWidget);
  });

  testWidgets('export reports where the file was saved', (tester) async {
    await pump(tester);
    await openSaveExport(tester);
    await tester.tap(find.textContaining('FB2  ·'));
    await tester.pumpAndSettle();
    expect(service.exported, [book]);
    expect(find.textContaining('/exported/book.fb2'), findsOneWidget);
  });

  testWidgets('a cancelled export shows no message', (tester) async {
    service.exportResult = null;
    await pump(tester);
    await openSaveExport(tester);
    await tester.tap(find.textContaining('FB2  ·'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exported'), findsNothing);
  });

  testWidgets('the export message replaces the "saved" notice', (tester) async {
    await pump(tester);
    await openSaveExport(tester);
    await tester.tap(find.textContaining('FB2  ·'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Exported'), findsOneWidget);
    expect(find.textContaining('Saved in the app'), findsNothing);
  });

  group('leaving the book', () {
    Future<void> openBook(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (c) => TextButton(
                  onPressed: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                          builder: (_) => BookPage(
                              service, book, StreamController<void>.broadcast()))),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('an unedited book just closes', (tester) async {
      service.markSaved(book);
      await openBook(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('unsaved section changes ask before closing', (tester) async {
      service.markSaved(book);
      book.addSection('Extra');
      await openBook(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't save"));
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
    });
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
    expect(find.text('Сохранить и экспорт'), findsOneWidget);
  });

  Future<void> tapMerge(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add another book'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Add another book appends its chapters', (tester) async {
    service.openResult = FileInfo(
        _fb2.replaceAll('Sample', 'Second').replaceAll('>Ch<', '>Other<'), '/x.fb2');
    await pump(tester);
    await tapMerge(tester);
    expect(book.section.map((s) => s.title), ['Ch', 'Second', 'Other']);
    expect(find.textContaining('Added 2 sections'), findsOneWidget);
  });

  testWidgets('Add another book: cancelling changes nothing', (tester) async {
    await pump(tester);
    await tapMerge(tester);
    expect(book.section.length, 1);
  });

  testWidgets('Add another book: a failure is explained', (tester) async {
    service.openThrows = StateError('boom');
    await pump(tester);
    await tapMerge(tester);
    expect(book.section.length, 1);
    expect(find.textContaining('read'), findsOneWidget);
  });

  testWidgets('the More menu offers find and merge', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Find and replace'), findsOneWidget);
    expect(find.text('Add another book'), findsOneWidget);
    expect(find.textContaining('Export'), findsNothing); // exporting lives in Save & export
    await tester.tap(find.text('Find and replace'));
    await tester.pumpAndSettle();
    expect(find.text('Replace with'), findsOneWidget);
  });
}
