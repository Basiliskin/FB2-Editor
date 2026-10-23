import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
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

  testWidgets('the Improve bar asks for a provider, then offers presets',
      (tester) async {
    final Map llmSettings = {};
    service.providerStore = ProviderStore(
        getSettings: () => llmSettings,
        setSettings: (m) async => llmSettings.addAll(m),
        session: MemoryKeyVault(),
        persistent: MemoryKeyVault(),
        isWeb: false);
    await pump(tester, 4);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Add provider'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Add provider'), findsNothing);

    await service.providerStore.save(const Provider(
        id: 'p', name: 'Mine', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Proofread'), findsOneWidget);
    expect(find.text('Paragraph 1'), findsOneWidget);
    // tapping a later paragraph widens the chosen range instead of editing it
    await tester.tap(find.text('para 2 lorem ipsum dolor'));
    await tester.pump();
    expect(find.text('Paragraphs 1-3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a custom preset is saved from the bar and offered as a chip',
      (tester) async {
    final Map llmSettings = {};
    service.providerStore = ProviderStore(
        getSettings: () => llmSettings,
        setSettings: (m) async => llmSettings.addAll(m),
        session: MemoryKeyVault(),
        persistent: MemoryKeyVault(),
        isWeb: false);
    await service.providerStore.save(const Provider(
        id: 'p', name: 'Mine', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));
    await pump(tester, 3);
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('New preset'));
    await tester.tap(find.text('New preset'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Formal');
    await tester.enterText(fields.at(1), 'Make it formal');
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Formal'));
    expect(find.text('Formal'), findsOneWidget);
    expect(service.providerStore.customPresets().single.instruction, 'Make it formal');
    // long press edits it; delete removes it
    await tester.longPress(find.text('Formal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Formal'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
