import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/pages/home_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/library_view.dart';

class _FakeService extends AppService {
  dynamic openResult;
  dynamic loadBookResult;
  int openCalls = 0;
  final loaded = <Map>[];

  @override
  openFile(Map extensionNames) async {
    openCalls++;
    expect(extensionNames, {'fb2': true, 'zip': true});
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

  testWidgets('shows a snackbar when the picked file has no FB2 book',
      (tester) async {
    service.openResult = null;
    await pumpHome(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    await tester.pump();
    expect(service.openCalls, 1);
    expect(find.text('No FB2 book found in the selected file'), findsOneWidget);
    expect(find.text('Loading'), findsNothing);
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
}
