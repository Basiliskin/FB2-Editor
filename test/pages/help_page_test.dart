import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/library_view.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
}

void main() {
  late AppService service;
  setUp(() => service = AppService());

  testWidgets('lists every topic in English by default', (tester) async {
    await _pump(tester, HelpScreen(service));
    expect(find.text('Help'), findsOneWidget);
    for (final t in helpTopics) {
      expect(find.text(t.title.$1), findsOneWidget);
    }
  });

  testWidgets('shows Russian when the language setting is ru', (tester) async {
    service.getSettings()['language'] = 'ru';
    await _pump(tester, HelpScreen(service));
    expect(find.text('Справка'), findsOneWidget);
    for (final t in helpTopics) {
      expect(find.text(t.title.$2), findsOneWidget);
    }
  });

  testWidgets('a topic expands to show its tips', (tester) async {
    await _pump(tester, HelpScreen(service));
    final tip = helpTopics.first.tips.first.$1;
    expect(find.text(tip), findsNothing);
    await tester.tap(find.text(helpTopics.first.title.$1));
    await tester.pumpAndSettle();
    expect(find.text(tip), findsOneWidget);
  });

  testWidgets('every topic has tips in both languages', (tester) async {
    for (final t in helpTopics) {
      expect(t.tips, isNotEmpty);
      for (final tip in t.tips) {
        expect(tip.$1.trim(), isNotEmpty);
        expect(tip.$2.trim(), isNotEmpty);
      }
    }
  });

  testWidgets('library shows a help button only when openHelp is given',
      (tester) async {
    service.workspace['history'] = [];
    var helps = 0;
    await _pump(
        tester,
        LibraryView(service,
            HomeActions((() async {}), (_) async {}, (_) async {}, () {},
                openHelp: () => helps++)));
    await tester.tap(find.byIcon(Icons.help_outline));
    expect(helps, 1);

    await _pump(
        tester,
        LibraryView(service,
            HomeActions((() async {}), (_) async {}, (_) async {}, () {})));
    expect(find.byIcon(Icons.help_outline), findsNothing);
  });

  testWidgets('openHelp pushes the help screen', (tester) async {
    await _pump(
        tester,
        Builder(
            builder: (context) => TextButton(
                onPressed: () => openHelp(context, service),
                child: const Text('go'))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
  });
}
