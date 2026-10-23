import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/pages/book_page.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/pages/home_page.dart';
import 'package:quill_fb2/pages/settings_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/open_failure.dart';
import 'package:quill_fb2/ui/library_view.dart';

class _FakeService extends AppService {
  dynamic openResult;
  dynamic loadBookResult;
  int openCalls = 0;
  final loaded = <Map>[];
  dynamic addResult;
  bool convertThrows = false;
  Object? openThrows;
  Object? convertFailure;
  final addCalls = <List>[];
  final removed = <Map>[];

  @override
  convertXmlToJson(xml) async {
    if (convertFailure != null) throw convertFailure!;
    if (convertThrows) throw StateError('bad xml');
    return {};
  }

  @override
  addProject(projectData, fileInfo, book) async {
    addCalls.add([fileInfo, book]);
    return addResult;
  }

  @override
  removeProject(model) async {
    removed.add(model);
    workspace['history'] = [];
  }

  @override
  openFile(Map extensionNames) async {
    openCalls++;
    expect(extensionNames, {'fb2': true, 'zip': true});
    if (openThrows != null) throw openThrows!;
    return openResult;
  }

  @override
  loadBook(Map book) async {
    loaded.add(book);
    return loadBookResult;
  }
}

void main() {
  late _FakeService service;

  setUp(() {
    service = _FakeService();
    service.workspace['history'] = [
      {'projectId': '1', 'title': 'Dune', 'author': 'Herbert', 'cover': ''},
    ];
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(service)));
  }

  testWidgets('renders the library', (tester) async {
    await pumpHome(tester);
    expect(find.byType(LibraryView), findsOneWidget);
    // generated cover tile + caption
    expect(find.text('Dune'), findsNWidgets(2));
  });

  Future<void> tapAdd(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('cancelling the picker shows no error', (tester) async {
    service.openResult = null;
    await pumpHome(tester);
    await tapAdd(tester);
    expect(service.openCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Loading'), findsNothing);
  });

  group('open errors are explained', () {
    testWidgets('unsupported file type', (tester) async {
      service.openThrows = const OpenFailure(OpenFailureKind.unsupportedType, 'txt');
      await pumpHome(tester);
      await tapAdd(tester);
      expect(find.textContaining('Unsupported file type'), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('zip without a book', (tester) async {
      service.openThrows = const OpenFailure(OpenFailureKind.noFb2InZip);
      await pumpHome(tester);
      await tapAdd(tester);
      expect(find.text('No .fb2 book found in the archive.'), findsOneWidget);
    });

    testWidgets('not an FB2 document', (tester) async {
      service.openResult = FileInfo('<nothing/>', '/tmp/x.fb2');
      service.convertFailure = const OpenFailure(OpenFailureKind.notFb2);
      await pumpHome(tester);
      await tapAdd(tester);
      expect(find.textContaining('not a valid FB2 book'), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('timeout', (tester) async {
      service.openResult = FileInfo('<x/>', '/tmp/x.fb2');
      service.convertFailure = const OpenFailure(OpenFailureKind.timeout);
      await pumpHome(tester);
      await tapAdd(tester);
      expect(find.textContaining('took too long'), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('any other error is reported as unreadable', (tester) async {
      service.openResult = FileInfo('<x/>', '/tmp/x.fb2');
      service.convertThrows = true;
      await pumpHome(tester);
      await tapAdd(tester);
      expect(find.text('The file could not be read.'), findsOneWidget);
    });
  });

  testWidgets('does not show the snackbar when opening a saved book fails',
      (tester) async {
    service.loadBookResult = null;
    await pumpHome(tester);
    await tester.tap(find.text('Dune').last);
    await tester.pump();
    await tester.pump();
    expect(service.loaded.single['projectId'], '1');
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Loading'), findsNothing);
  });

  group('with a parsed book', () {
    late ProjectModel model;
    final info = FileInfo('<xml/>', '/tmp/x.fb2');

    setUp(() {
      model = ProjectModel.fromJson({'title': 'Dune', 'section': []});
      service.addResult = model;
    });

    testWidgets('picking a file opens the book page and returns to the list',
        (tester) async {
      service.openResult = info;
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsOneWidget);
      expect(service.addCalls.single, [info, null]);

      Navigator.of(tester.element(find.byType(BookPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
      expect(find.byType(LibraryView), findsOneWidget);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('an unreadable picked file is reported and stays on the list',
        (tester) async {
      service.openResult = info;
      service.convertThrows = true;
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('no book page when the project could not be created',
        (tester) async {
      service.openResult = info;
      service.addResult = null;
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('opening a saved book passes its history entry',
        (tester) async {
      service.loadBookResult = info;
      await pumpHome(tester);
      await tester.tap(find.text('Dune').last);
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsOneWidget);
      expect(service.addCalls.single[1]['projectId'], '1');

      Navigator.of(tester.element(find.byType(BookPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(LibraryView), findsOneWidget);
    });

    testWidgets('a saved book that fails to parse leaves the list shown',
        (tester) async {
      service.loadBookResult = info;
      service.convertThrows = true;
      await pumpHome(tester);
      await tester.tap(find.text('Dune').last);
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets('no book page when a saved book yields no project',
        (tester) async {
      service.loadBookResult = info;
      service.addResult = null;
      await pumpHome(tester);
      await tester.tap(find.text('Dune').last);
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsNothing);
    });
  });

  testWidgets('removing a book from the list refreshes the library',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from list'));
    await tester.pumpAndSettle();
    expect(service.removed.single['projectId'], '1');
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('the settings button opens settings and returns',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(LibraryView), findsOneWidget);
  });

  testWidgets('the help button opens the help screen', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets('survives lifecycle changes and hot reload', (tester) async {
    await pumpHome(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.reassembleApplication();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(LibraryView), findsOneWidget);
  });

  testWidgets('the history change stream listener swallows events',
      (tester) async {
    await pumpHome(tester);
    final state = tester.state(find.byType(HomeScreen)) as dynamic;
    state.changeController.add(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing history update is caught and logged', (tester) async {
    final logged = <String>[];
    await runZoned(() async {
      await pumpHome(tester);
      final state = tester.state(find.byType(HomeScreen)) as dynamic;
      state.changeController.add(null);
      await tester.pump();
    },
        zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
          if (line.contains('update history list')) throw StateError('no log');
          logged.add(line);
        }));
    expect(logged, contains(contains('no log')));
    expect(tester.takeException(), isNull);
  });
}
