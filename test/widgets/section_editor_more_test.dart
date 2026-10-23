import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart' show imageHref;
import 'package:quill_fb2/widgets/section_editor/editor.dart';

/// AppService that keeps settings in memory and records saves/exports.
class _FakeService extends AppService {
  int saves = 0;
  Map settings = {};

  @override
  saveProject(ProjectModel model) async {
    saves++;
  }

  String? exportResult = '/exported/path.fb2';
  final exportedParagraphs = <List<String>>[];

  @override
  exportProject(ProjectModel model) async {
    exportedParagraphs.add([...model.section.last.p]);
    return exportResult;
  }

  @override
  getSettings() => settings;

  @override
  setSettings(s) async {
    settings = {...settings, ...s};
  }
}

void main() {
  late _FakeService service;
  late ProjectModel book;
  late Section section;
  String? clipboard;
  String? pickedPath;

  setUp(() {
    service = _FakeService();
    book = ProjectModel.fromJson({'title': 'B', 'section': []});
    clipboard = null;
    pickedPath = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return clipboard == null ? null : {'text': clipboard};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => pickedPath);
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'), null);
    });
  });

  Future<void> pump(WidgetTester tester, List<String> paragraphs) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    section = book.addSection('S');
    section.p = paragraphs;
    await tester.pumpWidget(
        MaterialApp(home: SectionEditor(service, book, section)));
    await tester.pump();
  }

  List<String> paras(int n) =>
      [for (var i = 0; i < n; i++) '<p>para $i</p>'];

  QuillController controller(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  Future<void> activate(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Lets the editor's cursor timers die with the widget.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder toolbarIcon(IconData icon) => find.byIcon(icon).last;

  testWidgets('changePage stores the page index', (tester) async {
    await pump(tester, paras(2));
    final state = tester.state(find.byType(SectionEditor)) as dynamic;
    state.changePage(2);
    await tester.pump();
    expect(state.currentIndex, 2);
  });

  testWidgets('unparsable paragraph falls back to its raw xml', (tester) async {
    await pump(tester, ['<p>broken', '<p>ok</p>']);
    expect(find.text('<p>broken'), findsOneWidget);
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('the text cache is flushed when it grows large', (tester) async {
    await pump(tester, paras(900));
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 40; i++) {
      await tester.drag(list, const Offset(0, -1000));
      await tester.pump();
    }
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('activating the already active paragraph is a no-op',
      (tester) async {
    await pump(tester, paras(5));
    final tile = find.ancestor(
        of: find.text('para 3'), matching: find.byType(InkWell));
    final onTap = tester.widget<InkWell>(tile).onTap!;
    onTap();
    await tester.pump();
    expect(find.byType(QuillEditor), findsOneWidget);
    final c = controller(tester);
    onTap();
    await tester.pump();
    expect(controller(tester), same(c));
    await dispose(tester);
  });

  testWidgets('splitting a paragraph shifts a later target', (tester) async {
    await pump(tester, paras(6));
    await activate(tester, 'para 1');
    final c = controller(tester);
    c.replaceText(c.document.length - 1, 0, '\nsplit tail', null);
    await tester.pump();
    await tester.tap(find.text('para 4'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(section.p.length, 7);
    expect(section.p[1], '<p>para 1</p>');
    expect(section.p[2], '<p>split tail</p>');
    // the editor sits on the original "para 4", now at index 5
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(controller(tester).document.toPlainText(), 'para 4\n');
    await dispose(tester);
  });

  testWidgets('switching to an earlier paragraph keeps its index',
      (tester) async {
    await pump(tester, paras(6));
    await activate(tester, 'para 4');
    final c = controller(tester);
    c.replaceText(0, 0, 'X', null);
    await tester.pump();
    await tester.tap(find.text('para 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(section.p[4], '<p>Xpara 4</p>');
    expect(controller(tester).document.toPlainText(), 'para 1\n');
    await dispose(tester);
  });

  testWidgets('save button commits edits and shows a snackbar',
      (tester) async {
    await pump(tester, paras(3));
    await activate(tester, 'para 1');
    controller(tester).replaceText(0, 0, 'Y', null);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pump();
    await tester.pump();
    expect(section.p[1], '<p>Ypara 1</p>');
    expect(service.saves, 1);
    expect(find.textContaining('Saved'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('saving a split paragraph drops the stale editor',
      (tester) async {
    await pump(tester, paras(3));
    await activate(tester, 'para 1');
    final c = controller(tester);
    c.replaceText(c.document.length - 1, 0, '\nmore', null);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pump();
    await tester.pump();
    expect(section.p.length, 4);
    expect(find.byType(QuillEditor), findsNothing);
    await dispose(tester);
  });

  testWidgets('autosave on pause saves; other states and autosave off do not',
      (tester) async {
    await pump(tester, paras(2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(service.saves, 0);
    service.settings = {'auto-save': true};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(service.saves, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(service.saves, 1);
  });

  testWidgets('back button pops, saving first when autosave is on',
      (tester) async {
    await pump(tester, paras(2));
    // ModalRoute-less home: pushing lets us observe the pop
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => TextButton(
                onPressed: () => Navigator.push(
                    c,
                    MaterialPageRoute(
                        builder: (_) => SectionEditor(service, book, section))),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(SectionEditor), findsNothing);
    expect(service.saves, 0);

    service.settings = {'auto-save': true};
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(SectionEditor), findsNothing);
    expect(service.saves, 1);
  });

  group('leaving with unsaved changes', () {
    Future<void> openEditor(WidgetTester tester) async {
      section = book.addSection('S');
      section.p = paras(2);
      service.markSaved(book);
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (c) => TextButton(
                  onPressed: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                          builder: (_) => SectionEditor(service, book, section))),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> edit(WidgetTester tester) async {
      await activate(tester, 'para 1');
      controller(tester).replaceText(0, 0, 'Y', null);
      await tester.pump();
    }

    testWidgets('nothing edited: leaves without asking', (tester) async {
      await openEditor(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(SectionEditor), findsNothing);
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('Save keeps the edit and leaves', (tester) async {
      await openEditor(tester);
      await edit(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(section.p[1], '<p>Ypara 1</p>');
      expect(find.byType(SectionEditor), findsNothing);
    });

    testWidgets("Don't save leaves without saving", (tester) async {
      await openEditor(tester);
      await edit(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't save"));
      await tester.pumpAndSettle();
      expect(service.saves, 0);
      expect(find.byType(SectionEditor), findsNothing);
    });

    testWidgets('Cancel stays in the editor', (tester) async {
      await openEditor(tester);
      await edit(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.saves, 0);
      expect(find.byType(SectionEditor), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('the system back gesture asks too', (tester) async {
      await openEditor(tester);
      await edit(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await dispose(tester);
    });
  });

  testWidgets('export includes the paragraph being edited', (tester) async {
    await pump(tester, paras(2));
    await activate(tester, 'para 1');
    controller(tester).replaceText(0, 0, 'Y', null);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pump();
    await tester.pump();
    expect(service.exportedParagraphs.single[1], '<p>Ypara 1</p>');
    await dispose(tester);
  });

  testWidgets('a cancelled export shows no message', (tester) async {
    service.exportResult = null;
    await pump(tester, paras(2));
    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('help and export buttons', (tester) async {
    await pump(tester, paras(2));
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.byType(SectionEditor), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('/exported/path.fb2'), findsOneWidget);
  });

  testWidgets('bold and italic wrap the selection in tags', (tester) async {
    await pump(tester, paras(2));
    await activate(tester, 'para 1');
    final c = controller(tester);
    // without a selection nothing happens
    await tester.tap(toolbarIcon(Icons.format_bold));
    await tester.pump();
    expect(c.document.toPlainText(), 'para 1\n');

    c.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4), ChangeSource.local);
    await tester.pump();
    await tester.tap(toolbarIcon(Icons.format_bold));
    await tester.pump();
    expect(c.document.toPlainText(), '<strong>para</strong> 1\n');

    c.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 8), ChangeSource.local);
    await tester.pump();
    await tester.tap(toolbarIcon(Icons.format_italic));
    await tester.pump();
    expect(c.document.toPlainText(), contains('<emphasis>'));
    await dispose(tester);
  });

  testWidgets('cite asks for an author', (tester) async {
    await pump(tester, paras(2));
    await activate(tester, 'para 1');
    final c = controller(tester);
    c.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4), ChangeSource.local);
    await tester.pump();
    await tester.tap(toolbarIcon(Icons.format_quote));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enter Author Name:'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Me');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.document.toPlainText(),
        contains('<cite><p>para</p><text-author>Me</text-author></cite>'));

    // empty author gives a cite without text-author
    c.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2), ChangeSource.local);
    await tester.pump();
    await tester.tap(toolbarIcon(Icons.format_quote));
    await tester.pump(const Duration(milliseconds: 300));
    // type then clear so the prompt returns '' rather than null
    await tester.enterText(find.byType(TextField).last, 'a');
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.document.toPlainText(), contains('<cite><p><c</p></cite>'));
    await dispose(tester);
  });

  testWidgets('add section from the clipboard', (tester) async {
    await pump(tester, paras(2));
    // empty clipboard: nothing happens
    await tester.tap(toolbarIcon(Icons.book));
    await tester.pump();
    expect(book.section.length, 1);
    // clipboard with empty text
    clipboard = '';
    await tester.tap(toolbarIcon(Icons.book));
    await tester.pump();
    expect(book.section.length, 1);

    clipboard = 'one\ntwo';
    await tester.tap(toolbarIcon(Icons.book));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enter Section Name:'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Fresh');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(book.section.length, 2);
    expect(book.section.last.title, 'Fresh');
    expect(book.section.last.p.length, 2);
    expect(find.text('Fresh Created'), findsOneWidget);
    expect(service.saves, 1);

    // cancelling the prompt adds nothing
    clipboard = 'x';
    await tester.tap(toolbarIcon(Icons.book));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(book.section.length, 2);
  });

  testWidgets('add annotation from the clipboard', (tester) async {
    await pump(tester, paras(2));
    final before = book.annotation.length;
    await tester.tap(toolbarIcon(Icons.contact_page));
    await tester.pump();
    clipboard = '';
    await tester.tap(toolbarIcon(Icons.contact_page));
    await tester.pump();
    expect(book.annotation.length, before);

    clipboard = 'first\nsecond';
    await tester.tap(toolbarIcon(Icons.contact_page));
    await tester.pump();
    await tester.pump();
    expect(book.annotation.length, before + 2);
    expect(find.text('Annotation Added'), findsOneWidget);
  });

  Future<void> pickPicture(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('picked_image');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/pic.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 40)));
    pickedPath = file.uri.toString();
    await tester.runAsync(() async {
      await tester.tap(toolbarIcon(Icons.image));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the image button inserts a picture after the edited paragraph',
      (tester) async {
    await pump(tester, paras(3));
    await activate(tester, 'para 1');
    await pickPicture(tester);
    expect(section.p.length, 4);
    expect(section.p[1], '<p>para 1</p>');
    expect(imageHref(section.p[2]), isNotNull);
    expect(section.p[3], '<p>para 2</p>');
    expect(find.byType(Image), findsOneWidget);
    expect(service.saves, 1);
    expect(book.binaryResource.resources.single.contentType, 'image/png');
    await dispose(tester);
  });

  testWidgets('a second picture can follow the first, and without a '
      'paragraph in edit it goes to the end', (tester) async {
    await pump(tester, paras(2));
    await pickPicture(tester);
    await pickPicture(tester);
    expect(section.p.length, 4);
    expect(section.pictureRefs, hasLength(2));
    expect(imageHref(section.p[3]), isNotNull);
    await dispose(tester);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    await pump(tester, paras(2));
    await tester.tap(toolbarIcon(Icons.image));
    await tester.pump();
    await tester.pump();
    expect(section.p, paras(2));
    expect(service.saves, 0);
    await dispose(tester);
  });

  testWidgets('the delete button removes the picture and keeps the text',
      (tester) async {
    await pump(tester, paras(2));
    await pickPicture(tester);
    expect(section.p.length, 3);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(section.p, paras(2));
    expect(book.binaryResource.resources, isEmpty);
    await dispose(tester);
  });
}
