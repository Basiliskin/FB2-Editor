import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/footnotes.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';
import 'package:quill_fb2/widgets/section_editor/footnote_dialog.dart';
import 'package:quill_fb2/widgets/section_editor/note_chips.dart';

class _FakeService extends AppService {
  Map settings = {};
  @override
  saveProject(ProjectModel model) async {}
  @override
  getSettings() => settings;
  @override
  setSettings(s) async => settings = {...settings, ...s};
}

void main() {
  late _FakeService service;
  late ProjectModel book;
  late Section section;

  setUp(() {
    service = _FakeService();
    book = ProjectModel.fromJson({'title': 'B', 'section': []});
  });

  Future<void> pump(WidgetTester tester, List<String> paragraphs) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    section = book.addSection('S');
    section.p = paragraphs;
    await tester.pumpWidget(MaterialApp(home: SectionEditor(service, book, section)));
    await tester.pump();
  }

  QuillController controller(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  /// Taps the closed paragraph showing [text]; its note labels are set apart
  /// by thin spaces.
  Future<void> activate(WidgetTester tester, String text) async {
    await tester.tap(find.text(text.replaceAll('[1]', '\u2009[1]\u2009')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> tapFootnote(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Insert footnote').last);
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('inserting puts a mark at the cursor and a note in the book', (tester) async {
    await pump(tester, ['<p>samovar</p>']);
    await activate(tester, 'samovar');
    controller(tester).updateSelection(const TextSelection.collapsed(offset: 7), ChangeSource.local);
    await tapFootnote(tester);
    expect(find.text('Insert footnote'), findsWidgets);
    final label = tester.widget<TextField>(find.byKey(const ValueKey('footnote-label')));
    expect(label.controller!.text, '1');
    await tester.enterText(find.byKey(const ValueKey('footnote-text')), 'A tea urn.');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final id = book.footnotes.single.id;
    expect(book.footnote(id)!.text, 'A tea urn.');
    expect(serializeNotes(controller(tester).document), 'samovar${noteMarkXml(id, '1')}');
    expect(find.byKey(ValueKey('note-chip-$id')), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('with the cursor on a mark the note opens for editing', (tester) async {
    final id = book.addFootnote('1', 'old');
    final mark = noteMarkXml(id, '1');
    await pump(tester, ['<p>tea$mark</p>']);
    await activate(tester, 'tea[1]');
    controller(tester).updateSelection(const TextSelection.collapsed(offset: 4), ChangeSource.local);
    await tapFootnote(tester);
    expect(find.text('Footnote'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('footnote-label')), '*');
    await tester.enterText(find.byKey(const ValueKey('footnote-text')), 'new');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(book.footnote(id)!.text, 'new');
    expect(serializeNotes(controller(tester).document), 'tea${noteMarkXml(id, '*')}');
    await dispose(tester);
  });

  testWidgets('delete removes both the mark and the note', (tester) async {
    final id = book.addFootnote('1', 'old');
    final mark = noteMarkXml(id, '1');
    await pump(tester, ['<p>tea$mark!</p>']);
    await activate(tester, 'tea[1]!');
    controller(tester).updateSelection(const TextSelection.collapsed(offset: 4), ChangeSource.local);
    await tapFootnote(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(book.footnotes, isEmpty);
    expect(controller(tester).document.toPlainText(), 'tea!\n');
    await dispose(tester);
  });

  testWidgets('cancel changes nothing', (tester) async {
    await pump(tester, ['<p>tea</p>']);
    await activate(tester, 'tea');
    await tapFootnote(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(book.footnotes, isEmpty);
    expect(controller(tester).document.toPlainText(), 'tea\n');
    await dispose(tester);
  });

  testWidgets('tapping a chip opens its note', (tester) async {
    final id = book.addFootnote('1', 'urn');
    await pump(tester, ['<p>tea${noteMarkXml(id, '1')} hot</p>']);
    await activate(tester, 'tea[1] hot');
    await tester.tap(find.byKey(ValueKey('note-chip-$id')));
    await tester.pumpAndSettle();
    expect(find.text('Footnote'), findsOneWidget);
    expect(find.text('urn'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await dispose(tester);
  });

  testWidgets('a link that is not a footnote shows as a chip but opens nothing', (tester) async {
    await pump(tester, ['<p>see<a l:href="#ch2">here</a></p>']);
    await activate(tester, 'see\u2009here\u2009');
    controller(tester).updateSelection(const TextSelection.collapsed(offset: 4), ChangeSource.local);
    await tapFootnote(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await dispose(tester);
  });

  testWidgets('bold around a chip keeps the chip', (tester) async {
    final id = book.addFootnote('1', 'urn');
    await pump(tester, ['<p>tea${noteMarkXml(id, '1')}</p>']);
    await activate(tester, 'tea[1]');
    controller(tester).updateSelection(const TextSelection(baseOffset: 0, extentOffset: 4), ChangeSource.local);
    await tester.pump();
    await tester.tap(find.byTooltip('Bold').last);
    await tester.pumpAndSettle();
    expect(serializeNotes(controller(tester).document), '<strong>tea${noteMarkXml(id, '1')}</strong>');
    await dispose(tester);
  });

  testWidgets('closing the paragraph writes the mark back as XML', (tester) async {
    final id = book.addFootnote('1', 'urn');
    await pump(tester, ['<p>tea${noteMarkXml(id, '1')}</p>', '<p>other</p>']);
    await activate(tester, 'tea[1]');
    controller(tester).replaceText(0, 0, 'hot ', null);
    await activate(tester, 'other');
    expect(section.p.first, '<p>hot tea${noteMarkXml(id, '1')}</p>');
    await dispose(tester);
  });

  group('dialog', () {
    Future<FootnoteAction?> open(WidgetTester tester, {Footnote? note}) async {
      FootnoteAction? result;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (c) => TextButton(
                  onPressed: () async => result = await showFootnoteDialog(c, service, note: note, label: '4'),
                  child: const Text('go')))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('save is off until both fields have text', (tester) async {
      await open(tester);
      FilledButton save() => tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save().onPressed, isNull);
      expect(find.text('Delete'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('footnote-text')), 'x');
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tester.enterText(find.byKey(const ValueKey('footnote-label')), ' ');
      await tester.pump();
      expect(save().onPressed, isNull);
    });

    testWidgets('a formatted note is shown read-only with Delete only', (tester) async {
      await open(tester, note: const Footnote('n', '2', 'fancy text', editable: false));
      expect(find.textContaining("can't edit"), findsOneWidget);
      expect(find.text('fancy text'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
