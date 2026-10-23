import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/pages/story_map_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';

import '../support/story_fixtures.dart';

late AppService _service;

/// A phone-sized page on [book] with its map already loaded (loading runs an isolate, which
/// the test clock does not wait for).
Future<StoryMap> _open(WidgetTester tester, ProjectModel book) async {
  tester.view.physicalSize = const Size(390 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final map = (await tester.runAsync(() => book.loadStoryMap()))!;
  await tester.pumpWidget(MaterialApp(home: StoryMapPage(_service, book)));
  await tester.pump();
  await tester.pump();
  return map;
}

Future<ProjectModel> _book(WidgetTester tester, [List<StorySection>? story]) async =>
    (await tester.runAsync(() => storyBook(story)))!;

Future<void> _editMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle(); // the + button animates in; it ignores taps until it is done
}

/// The "Ар" title is Артур, the most mentioned person: the first column.
Finder get _artur => find.text('Ар');

void main() {
  setUp(() => _service = AppService());

  group('reading', () {
    testWidgets('sections run down the side, grouped by act, with the people across the top', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      expect(find.text('Приезд'), findsOneWidget);
      expect(find.textContaining('Act 1'), findsOneWidget);
      expect(find.text('9 sections\n8 items'), findsOneWidget);
      expect(_artur, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('columns are grouped by kind under a band per group', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      expect(find.textContaining('People'), findsWidgets);
      m.addEntity('Порт', EntityKind.place, Role.minor, '');
      await tester.pumpWidget(MaterialApp(home: StoryMapPage(_service, book)));
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.place_outlined), findsWidgets);
    });

    testWidgets('the legend names the people roles and the other kinds', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      for (final word in ['protagonist', 'major', 'minor', 'Place', 'Event', 'Lore']) {
        expect(find.text(word), findsOneWidget);
      }
    });

    testWidgets('speaks Russian when the language setting is ru', (tester) async {
      _service.getSettings()['language'] = 'ru';
      final book = await _book(tester);
      await _open(tester, book);
      expect(find.text('Карта истории'), findsOneWidget);
      expect(find.text('9 разделов\n8 объектов'), findsOneWidget);
    });

    testWidgets('zoom buttons step through the three levels', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      expect(find.text('Fit to width'), findsOneWidget); // 8 columns do not fit at the roomier levels
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pump();
      expect(find.text('Compact'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pump();
      expect(find.text('Comfortable'), findsOneWidget);
      expect(find.text('Артур'), findsOneWidget); // names instead of initials
      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.pump();
      expect(find.text('Fit to width'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the overview map is hidden until asked for', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      final without = find.byType(CustomPaint).evaluate().length;
      await tester.tap(find.byIcon(Icons.map_outlined));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CustomPaint).evaluate().length, greaterThan(without));
      await tester.tap(find.byIcon(Icons.map));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CustomPaint).evaluate().length, without);
    });

    testWidgets('folding an act hides its sections', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      expect(find.text('Приезд'), findsOneWidget);
      await tester.tap(find.textContaining('Act 1'));
      await tester.pump();
      expect(find.text('Приезд'), findsNothing);
      expect(find.text('Допрос'), findsOneWidget);
    });

    testWidgets('tapping a cell tells how often it is mentioned', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tapAt(Offset(tester.getCenter(_artur).dx, tester.getCenter(find.text('Приезд')).dy));
      await tester.pump();
      expect(find.textContaining('Артур Рэйм · Приезд: 3'), findsOneWidget);
    });

    testWidgets('the flag button lists people to check and opens them', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(find.byIcon(Icons.flag_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Гидеон Кросс: not mentioned in Act 2'), findsOneWidget);
      await tester.tap(find.text('Гидеон Кросс: not mentioned in Act 2'));
      await tester.pumpAndSettle();
      expect(find.text('Гидеон Кросс'), findsWidgets);
      expect(find.textContaining('Act 2 · none'), findsOneWidget);
    });

    testWidgets('a book with no names says so and still lets you add', (tester) async {
      final book = await _book(tester, [const StorySection('a', 'Глава', ['<p>тихо.</p>'])]);
      await _open(tester, book);
      expect(find.textContaining('No names found'), findsOneWidget);
      await _editMode(tester);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('finding things', () {
    testWidgets('search narrows the columns', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.enterText(find.byType(TextField), 'Арт');
      await tester.pump();
      expect(find.text('9 sections\n1 items'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('9 sections\n8 items'), findsOneWidget);
    });

    testWidgets('toggle titles, Apply keeps only those, Reset brings everything back', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(_artur);
      await tester.pump();
      await tester.tap(find.text('Эв'));
      await tester.pump();
      expect(find.text('2 toggled'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pump();
      expect(find.text('Showing 2 of 8'), findsOneWidget);
      expect(find.text('9 sections\n2 items'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(find.textContaining('Showing'), findsNothing);
      expect(find.text('9 sections\n8 items'), findsOneWidget);
    });

    testWidgets('Clear drops what was toggled without filtering', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(_artur);
      await tester.pump();
      expect(find.text('1 toggled'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.textContaining('toggled'), findsNothing);
      expect(find.text('9 sections\n8 items'), findsOneWidget);
    });

    testWidgets('the filter sheet lists every item with a checkbox; Apply and Reset work', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(find.text('Filter items'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(8));
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Apply (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 2 of 8'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget); // what was applied is still ticked
      await tester.tap(find.text('Reset').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Showing'), findsNothing);
    });

    testWidgets('Apply is off until something is ticked; "All" ticks a whole group', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply (0)')).onPressed, isNull);
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(find.text('8 selected'), findsOneWidget);
      await tester.tap(find.text('None'));
      await tester.pump();
      expect(find.text('0 selected'), findsOneWidget);
    });

    testWidgets('the sort button changes the order of the columns', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      double x(String initials) => tester.getCenter(find.text(initials)).dx;
      expect(x('Эв') < x('Га'), isTrue); // most mentioned first
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('By name'));
      await tester.pumpAndSettle();
      expect(x('Га') < x('Эв'), isTrue);
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First appearance'));
      await tester.pumpAndSettle();
      expect(x('Ар') < x('Га'), isTrue);
    });
  });

  group('details', () {
    testWidgets('a person sheet shows role, mentions per act, sections and connections', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(_artur);
      await tester.pump();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Артур Рэйм'), findsWidgets);
      expect(find.text('protagonist'), findsWidgets);
      expect(find.text('Act 1 · 7'), findsOneWidget);
      expect(find.text('Connected to'), findsOneWidget);
      expect(find.text('Sections'), findsOneWidget);
    });
  });

  group('add, change, remove', () {
    testWidgets('+ adds a place with a note; it shows in a new group and is saved in the book', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await _editMode(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Add to the map'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Старый порт');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Place'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Note'), 'где всё началось');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final i = indexOfEntity(m, 'Старый порт');
      expect(m.cast[i].kind, EntityKind.place);
      expect(m.cast[i].note, 'где всё началось');
      expect(find.text('9 sections\n9 items'), findsOneWidget);
      expect(book.getBookXml(), contains('Старый порт'));
    });

    testWidgets('a person can be added with a role; the role chips go away for other kinds', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await _editMode(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'protagonist'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Event'));
      await tester.pump();
      expect(find.widgetWithText(ChoiceChip, 'protagonist'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Person'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Лиора');
      await tester.tap(find.widgetWithText(ChoiceChip, 'major'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final e = m.cast[indexOfEntity(m, 'Лиора')];
      expect([e.kind, e.role], [EntityKind.person, Role.major]);
    });

    testWidgets('an empty name is not saved', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await _editMode(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Add to the map'), findsOneWidget);
      expect(m.cast.length, 8);
    });

    testWidgets('tapping a title in edit mode opens the editor; rename and change role', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await _editMode(tester);
      await tester.tap(find.text('Мэ'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsWidgets);
      expect(find.widgetWithText(TextField, 'Мэтью'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Матвей');
      await tester.tap(find.widgetWithText(ChoiceChip, 'major'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(m.cast.any((c) => c.name == 'Мэтью'), isFalse);
      final e = m.cast[indexOfEntity(m, 'Матвей')];
      expect(e.role, Role.major);
      expect(book.getBookXml(), contains('Матвей'));
    });

    testWidgets('remove asks nothing, says so, and Undo puts it back where it was', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      final before = m.encode();
      await _editMode(tester);
      await tester.tap(find.text('Мэ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(m.cast.any((c) => c.name == 'Мэтью'), isFalse);
      expect(find.text('Removed Мэтью'), findsOneWidget);
      expect(find.text('9 sections\n7 items'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(m.encode(), before);
      expect(find.text('9 sections\n8 items'), findsOneWidget);
    });

    testWidgets('in edit mode a cell marks or unmarks where something appears', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await _editMode(tester);
      final cell = Offset(tester.getCenter(_artur).dx, tester.getCenter(find.text('Приезд')).dy);
      expect(m.cast[0].perUnit[0], 3);
      await tester.tapAt(cell);
      await tester.pump();
      expect(m.cast[0].perUnit[0], 0);
      await tester.tapAt(cell);
      await tester.pump();
      expect(m.cast[0].perUnit[0], 1); // a hand mark counts as one mention
    });

    testWidgets('connections: add with a label, relabel, remove', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await _editMode(tester);
      await tester.tap(_artur);
      await tester.pumpAndSettle();
      final a = 0, brent = indexOfEntity(m, 'Капитан Брент');
      expect(m.tieBetween(a, brent), isNull);

      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Капитан Брент'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'враг');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(m.tieBetween(a, brent)!.label, 'враг');
      expect(m.tieBetween(a, brent)!.manual, isTrue);

      await tester.ensureVisible(find.text('враг'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('враг'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'союзник');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(m.tieBetween(a, brent)!.label, 'союзник');

      final remove = find.descendant(of: find.widgetWithText(ListTile, 'Капитан Брент'), matching: find.byTooltip('Remove connection'));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(m.tieBetween(a, brent), isNull);
      expect(m.ties.where((t) => t.manual), isEmpty);
    });

    testWidgets('an auto-detected tie can be labelled too', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await _editMode(tester);
      await tester.tap(_artur);
      await tester.pumpAndSettle();
      await tester.tap(find.text('no label — tap to add').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'друзья');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(m.ties.where((t) => t.label == 'друзья').single.manual, isFalse);
    });

    testWidgets('every edit is written into the book, so a save or export carries it', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      expect(book.getBookXml(), isNot(contains('story-map')));
      await _editMode(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Маяк');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(book.getBookXml(), contains('<custom-info info-type="story-map">'));
    });

    testWidgets('Rebuild from the text throws the edits away after asking', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      m.addEntity('Лишнее', EntityKind.lore, Role.minor, '');
      book.saveStoryMap(m);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rebuild from the text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(book.getBookXml(), contains('Лишнее'));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rebuild from the text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rebuild'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 800)));
      await tester.pumpAndSettle();
      expect(book.getBookXml(), isNot(contains('Лишнее')));
      expect(find.text('9 sections\n8 items'), findsOneWidget);
    });
  });

  group('one section', () {
    testWidgets('a section sheet shows who is in it and the connections among them', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(find.text('Приезд'));
      await tester.pumpAndSettle();
      expect(find.text('IN THIS SECTION'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Артур Рэйм'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Эвелин Ларк'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Гидеон Кросс'), findsNothing);
      expect(find.text('CONNECTIONS HERE'), findsOneWidget);
    });

    testWidgets('remove someone from a section and add someone else', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await tester.tap(find.text('Приезд'));
      await tester.pumpAndSettle();
      final mat = indexOfEntity(m, 'Мэтью'), kross = indexOfEntity(m, 'Гидеон Кросс');
      expect(m.cast[mat].perUnit[0], greaterThan(0));
      await tester.tap(find.descendant(of: find.widgetWithText(InputChip, 'Мэтью'), matching: find.byTooltip('Not in this section')));
      await tester.pump();
      expect(m.cast[mat].perUnit[0], 0);
      await tester.tap(find.widgetWithText(InkWell, 'Гидеон Кросс'));
      await tester.pump();
      expect(m.cast[kross].perUnit[0], 1);
      expect(book.getBookXml(), contains('story-map'));
    });

    testWidgets('the section sheet filters by kind and by search', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      m.addEntity('Маяк', EntityKind.place, Role.minor, '');
      await tester.tap(find.text('Приезд'));
      await tester.pumpAndSettle();
      expect(find.text('Маяк'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Places 1'));
      await tester.pump();
      expect(find.text('Маяк'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Артур Рэйм'), findsNothing);
      await tester.tap(find.widgetWithText(FilterChip, 'Places 1'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Find…'), 'гидеон');
      await tester.pump();
      expect(find.text('Гидеон Кросс'), findsOneWidget);
      expect(find.text('Маяк'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, 'Find…'), 'zzz');
      await tester.pump();
      expect(find.text('No match.'), findsNWidgets(2));
    });

    testWidgets('a section sheet can create a new entity and mark it present at once', (tester) async {
      final book = await _book(tester);
      final m = await _open(tester, book);
      await tester.tap(find.text('Приезд'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Библиотека');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Place'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final e = m.cast[indexOfEntity(m, 'Библиотека')];
      expect(e.perUnit[0], 1);
      expect(e.perUnit.skip(1).every((x) => x == 0), isTrue);
    });
  });

  group('leaving', () {
    Future<void> launch(WidgetTester tester, ProjectModel book, List<bool> results) async {
      tester.view.physicalSize = const Size(390 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => book.loadStoryMap());
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: Center(
                      child: TextButton(
                          onPressed: () async => results.add(await openStoryMap(context, _service, book)),
                          child: const Text('open')))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('going back without a change tells the book screen nothing changed', (tester) async {
      final book = await _book(tester);
      final results = <bool>[];
      await launch(tester, book, results);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets('going back after an edit tells the book screen the book changed', (tester) async {
      final book = await _book(tester);
      final results = <bool>[];
      await launch(tester, book, results);
      await _editMode(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Маяк');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(results, [true]);
    });
  });

  group('help', () {
    testWidgets('the help button opens the help on the Story map topic', (tester) async {
      final book = await _book(tester);
      await _open(tester, book);
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
      final topic = helpTopics.firstWhere((t) => t.id == 'story-map');
      expect(find.text(topic.title.$1), findsOneWidget);
      expect(find.text(topic.tips.first.$1), findsOneWidget); // already open
      expect(tester.getTopLeft(find.text(topic.title.$1)).dy, lessThan(150)); // it comes first
    });
  });
}
