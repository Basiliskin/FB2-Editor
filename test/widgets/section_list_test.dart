import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/section/list.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';

/// AppService that records saves instead of touching the disk.
class _FakeService extends AppService {
  int saves = 0;
  bool failSave = false;
  Map settings = {};

  @override
  saveProject(ProjectModel model) {
    saves++;
    // thrown synchronously so SectionList's try/catch sees it
    if (failSave) throw Exception('boom');
    return Future<void>.value();
  }

  @override
  getSettings() => settings;
}

void main() {
  late _FakeService service;
  late ProjectModel book;
  late StreamController<void> trigger;
  late List<Section> marked;
  var markResult = true;

  setUp(() {
    service = _FakeService();
    book = ProjectModel.fromJson({'title': 'B', 'section': []});
    for (var i = 0; i < 3; i++) {
      final s = book.addSection('Section $i');
      s.p = ['<p>a $i</p>', '<p>b $i</p>'];
    }
    trigger = StreamController<void>.broadcast();
    addTearDown(trigger.close);
    marked = [];
    markResult = true;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SectionList(service, book, trigger.stream, (s) {
          marked.add(s);
          return markResult;
        }),
      ),
    ));
    await tester.pump();
  }

  testWidgets('SectionTitle reports submitted text', (tester) async {
    String? got;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SectionTitle('Hello', (t) => got = t))));
    await tester.enterText(find.byType(TextFormField), 'World');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(got, 'World');
  });

  testWidgets('renders a tile per section with paragraph counts',
      (tester) async {
    await pump(tester);
    expect(find.byType(Dismissible), findsNWidgets(3));
    expect(find.text('2 paragraphs'), findsNWidgets(3));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('triggerSave saves the project, errors are swallowed',
      (tester) async {
    await pump(tester);
    trigger.add(null);
    await tester.pump();
    expect(service.saves, 1);
    service.failSave = true;
    trigger.add(null);
    await tester.pump();
    expect(service.saves, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the number toggles the delete mark', (tester) async {
    await pump(tester);
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(marked.single, book.section[0]);
    expect(find.byIcon(Icons.check), findsOneWidget);
    markResult = false;
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('editing a title commits on submit', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(book.section[0].title, 'Renamed');
  });

  testWidgets('dragging a handle reorders and saves', (tester) async {
    await pump(tester);
    final first = book.section[0];
    final handle = find.byIcon(Icons.drag_indicator).first;
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    await g.moveBy(const Offset(0, 200));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(book.section.last, first);
    expect(service.saves, 1);
  });

  testWidgets('swipe to dismiss asks, then removes the section', (tester) async {
    await pump(tester);
    await tester.fling(
        find.text('2 paragraphs').first, const Offset(700, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Delete section?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(book.section.length, 2);
  });

  testWidgets('cancelling the swipe keeps the section', (tester) async {
    await pump(tester);
    final before = book.section.length;
    await tester.fling(
        find.text('2 paragraphs').first, const Offset(700, 0), 2000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(book.section.length, before);
    expect(find.text('2 paragraphs'), findsWidgets);
  });

  testWidgets('edit button opens the editor and returns', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    expect(find.byType(SectionEditor), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(SectionEditor), findsNothing);
    expect(find.byType(SectionList), findsOneWidget);
  });

  testWidgets('lifecycle changes are handled', (tester) async {
    await pump(tester);
    service.settings = {'auto-save': true};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(SectionList), findsOneWidget);
  });
}
