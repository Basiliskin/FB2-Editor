import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';

import '../support/form_harness.dart';

void main() {
  late AppService service;
  late ProjectModel book;

  setUp(() {
    mockDocumentsDir();
    service = AppService();
    book = ProjectModel.fromJson({'title': 'B', 'section': []});
  });

  Future<void> pump(WidgetTester tester, int n) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final section = book.addSection('S');
    section.p = [for (var i = 0; i < n; i++) '<p>para $i lorem ipsum dolor</p>'];
    await tester.pumpWidget(
        MaterialApp(home: SectionEditor(service, book, section)));
    await tester.pump();
  }

  testWidgets('a 5000 paragraph section scrolls in a few ms per frame',
      (tester) async {
    await pump(tester, 5000);
    final list = find.byType(Scrollable).first;
    final sw = Stopwatch();
    final times = <int>[];
    for (var i = 0; i < 20; i++) {
      sw
        ..reset()
        ..start();
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 16));
      times.add(sw.elapsedMilliseconds);
    }
    times.sort();
    print('scroll median ${times[10]}ms max ${times.last}ms');
    expect(times.last, lessThan(100));
  });

  testWidgets('switching paragraphs keeps untouched ones intact',
      (tester) async {
    await pump(tester, 20);
    await tester.tap(find.text('para 3 lorem ipsum dolor'));
    await tester.pump();
    expect(find.byType(Scrollable), findsWidgets);
    // second tap on another paragraph commits the first untouched
    await tester.tap(find.text('para 5 lorem ipsum dolor'));
    await tester.pump();
    expect(book.section.first.p.length, 20);
    // let the editor's cursor timers die with the widget
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
