import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/library_view.dart';
import 'package:quill_fb2/ui/widgets.dart';

Map _book(String id, String title, String author,
        {String cover = '', String updated = '2026-10-23 10:00:00'}) =>
    {
      'projectId': id,
      'title': title,
      'author': author,
      'cover': cover,
      'updated': updated,
    };

String _png() => base64Encode(img.encodePng(img.Image(width: 4, height: 4)));

class _Calls {
  int openFile = 0, settings = 0, newBook = 0;
  final opened = <Map>[], removed = <Map>[];
  late final HomeActions actions = HomeActions(
    () async => openFile++,
    (b) async => opened.add(b),
    (b) async => removed.add(b),
    () => settings++,
    newBook: () async => newBook++,
  );
}

Future<void> _pump(WidgetTester tester, AppService service, _Calls calls) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(home: LibraryView(service, calls.actions)));
}

void main() {
  late AppService service;
  late _Calls calls;

  setUp(() {
    service = AppService();
    service.workspace['history'] = [
      _book('1', 'Dune', 'Frank Herbert'),
      _book('2', 'Neuromancer', 'William Gibson', updated: '2025-01-05 00:00:00'),
    ];
    calls = _Calls();
  });

  testWidgets('the New book tile calls newBook', (tester) async {
    await _pump(tester, service, calls);
    await tester.tap(find.text('New book'));
    expect(calls.newBook, 1);
    expect(calls.openFile, 0);
  });

  testWidgets('shows the load tile and books, newest history entry first',
      (tester) async {
    await _pump(tester, service, calls);
    expect(find.text('Your library'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'Dune' || d == 'Neuromancer')
        .toList();
    // Neuromancer was added last, so it is listed first.
    expect(titles.first, 'Neuromancer');
  });

  testWidgets('formats the date as dd-mm-yyyy next to the author',
      (tester) async {
    await _pump(tester, service, calls);
    expect(find.text('William Gibson · 05-01-2025'), findsOneWidget);
    expect(find.text('Frank Herbert · 23-10-2026'), findsOneWidget);
  });

  testWidgets('shows only the load tile for an empty library', (tester) async {
    service.workspace['history'] = [];
    await _pump(tester, service, calls);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
  });

  testWidgets('search filters by title and author, case-insensitively',
      (tester) async {
    await _pump(tester, service, calls);
    await tester.enterText(find.byType(TextField), 'dUnE');
    await tester.pump();
    expect(find.text('Neuromancer'), findsNothing);
    expect(find.textContaining('Frank Herbert'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gibson');
    await tester.pump();
    expect(find.textContaining('William Gibson'), findsOneWidget);
    expect(find.textContaining('Frank Herbert'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('tapping the load tile calls openFile', (tester) async {
    await _pump(tester, service, calls);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    expect(calls.openFile, 1);
  });

  testWidgets('tapping a book calls openBook with that entry', (tester) async {
    await _pump(tester, service, calls);
    await tester.tap(find.textContaining('Frank Herbert'));
    expect(calls.opened.single['projectId'], '1');
  });

  testWidgets('menu "Remove from list" calls removeBook for that entry',
      (tester) async {
    await _pump(tester, service, calls);
    // Menu buttons follow display order: Neuromancer first.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from list'));
    await tester.pumpAndSettle();
    expect(calls.removed.single['projectId'], '2');
    expect(calls.opened, isEmpty);
  });

  testWidgets('settings button calls openSettings', (tester) async {
    await _pump(tester, service, calls);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    expect(calls.settings, 1);
  });

  testWidgets('uses Russian strings when the language is ru', (tester) async {
    service.workspace['workspaceSettings'] = {'language': 'ru'};
    await _pump(tester, service, calls);
    expect(find.text('Ваша библиотека'), findsOneWidget);
    expect(find.text('Your library'), findsNothing);
  });

  group('BookCover', () {
    Future<void> pumpCover(WidgetTester tester, Map book) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: BookCover(book, service))));

    testWidgets('draws the title on a generated tile without a cover',
        (tester) async {
      await pumpCover(tester, _book('1', 'Dune', 'F'));
      expect(find.text('Dune'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('draws the image when a cover exists', (tester) async {
      await pumpCover(tester, _book('1', 'Dune', 'F', cover: _png()));
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Dune'), findsNothing);
    });

    testWidgets('uses "?" when the title is missing', (tester) async {
      await pumpCover(tester, {'cover': ''});
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('tr', () {
    test('returns English by default and Russian for ru', () {
      expect(tr(service, 'a', 'б'), 'a');
      service.workspace['workspaceSettings'] = {'language': 'ru'};
      expect(tr(service, 'a', 'б'), 'б');
    });
  });
}
