import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/section/list.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';
import 'package:quill_fb2/widgets/story_map/section_sheet.dart';

import '../support/form_harness.dart';
import '../support/story_fixtures.dart';

class _Service extends AppService {
  @override
  saveProject(ProjectModel model) async {}
}

void main() {
  late AppService service;
  setUp(() {
    mockDocumentsDir();
    service = _Service();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('section cards', () {
    Future<void> pumpList(WidgetTester tester, ProjectModel book) async {
      phone(tester);
      final trigger = StreamController<void>.broadcast();
      addTearDown(trigger.close);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SectionList(service, book, trigger.stream, (s) => true))));
      await tester.pump();
    }

    testWidgets('show who is in the section once the story map has been opened', (tester) async {
      final book = (await tester.runAsync(() => storyBook()))!;
      await pumpList(tester, book);
      expect(find.text('Артур'), findsNothing); // no map yet
      await tester.runAsync(() => book.loadStoryMap());
      await pumpList(tester, book);
      expect(find.text('Артур'), findsWidgets);
      expect(find.text('Эвелин'), findsWidgets);
    });

    testWidgets('a long cast shows the first few and a count', (tester) async {
      final book = (await tester.runAsync(() => storyBook()))!;
      final m = (await tester.runAsync(() => book.loadStoryMap()))!;
      for (var i = 0; i < 6; i++) {
        final e = m.addEntity('Лишний$i', EntityKind.lore, Role.minor, '');
        m.togglePresence(e, 0);
      }
      await pumpList(tester, book);
      expect(find.text('+5'), findsOneWidget); // 3 people + 6 lore, four shown
    });

    testWidgets('a section with nobody in it shows nothing extra', (tester) async {
      final book = (await tester.runAsync(() => storyBook()))!;
      final m = (await tester.runAsync(() => book.loadStoryMap()))!;
      for (final c in m.cast) {
        c.perUnit[0] = 0;
      }
      m.recompute();
      await pumpList(tester, book);
      expect(find.byType(SectionCastLine), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('section editor', () {
    Future<void> pumpEditor(WidgetTester tester, ProjectModel book) async {
      phone(tester);
      await tester.runAsync(() => book.loadStoryMap());
      await tester.pumpWidget(MaterialApp(home: SectionEditor(service, book, book.section.first)));
      await tester.pump();
    }

    Future<void> close(WidgetTester tester) async {
      // let the editor's cursor timers die with the widget
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('the story map button shows who is in this section', (tester) async {
      final book = (await tester.runAsync(() => storyBook()))!;
      await pumpEditor(tester, book);
      await tester.tap(find.byTooltip('Story map'));
      await tester.pumpAndSettle();
      expect(find.text('IN THIS SECTION'), findsOneWidget);
      expect(find.text('1. Приезд'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Артур Рэйм'), findsOneWidget);
      await close(tester);
    });

    testWidgets('marking someone there is saved into the book', (tester) async {
      final book = (await tester.runAsync(() => storyBook()))!;
      await pumpEditor(tester, book);
      expect(book.getBookXml(), isNot(contains('story-map')));
      await tester.tap(find.byTooltip('Story map'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, 'Гидеон Кросс'));
      await tester.pump();
      final m = book.loadedStoryMap!;
      expect(m.cast[indexOfEntity(m, 'Гидеон Кросс')].perUnit[0], 1);
      expect(book.getBookXml(), contains('<custom-info info-type="story-map">'));
      await close(tester);
    });

    testWidgets('a section the map does not know does nothing', (tester) async {
      final book = (await tester.runAsync(() => storyBook()))!;
      await pumpEditor(tester, book);
      book.section.first.sectionId = 'unknown'; // as if the id changed under the map
      book.loadedStoryMap; // realigns: the old section is gone, 'unknown' is a new one
      await tester.tap(find.byTooltip('Story map'));
      await tester.pumpAndSettle();
      expect(find.text('IN THIS SECTION'), findsOneWidget); // it is a section of the book now
      await close(tester);
    });
  });
}
