import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/widgets/forms/label.dart';

import '../support/form_harness.dart';

void main() {
  late FormHarness harness;
  setUp(() => harness = FormHarness());

  Future<void> pump(WidgetTester tester, List<String> items,
      {LabelDataChanged<LabelData?>? onUpdate}) {
    return harness.pump(
        tester,
        LabelFormField(
            name: 'genre',
            initialValue: LabelData('Add genre', items),
            onUpdate: onUpdate));
  }

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  List<String> saved() => (harness.lastValues['genre'] as LabelData).items;

  testWidgets('shows existing items as capitalised chips', (tester) async {
    await pump(tester, ['prose', 'sf']);
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.text('Prose'), findsOneWidget);
    expect(find.text('Sf'), findsOneWidget);
  });

  testWidgets('shows the hint and no chips when empty', (tester) async {
    await pump(tester, []);
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Add genre'), findsOneWidget);
  });

  testWidgets('submitting text adds a chip and clears the input',
      (tester) async {
    await pump(tester, ['prose']);
    await submit(tester, 'sf');
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await harness.save(tester);
    expect(saved(), ['prose', 'sf']);
  });

  testWidgets('adding a duplicate ignores case and moves it to the end',
      (tester) async {
    await pump(tester, ['prose', 'sf']);
    await submit(tester, 'PROSE');
    await harness.save(tester);
    expect(saved(), ['sf', 'PROSE']);
  });

  testWidgets('deleting a chip removes it', (tester) async {
    var updates = 0;
    await pump(tester, ['prose', 'sf'], onUpdate: (_) => updates++);
    await tester.tap(find.descendant(
        of: find.widgetWithText(InputChip, 'Prose'),
        matching: find.byIcon(Icons.clear)));
    await tester.pumpAndSettle();
    expect(find.text('Prose'), findsNothing);
    expect(updates, 1);
    await harness.save(tester);
    expect(saved(), ['sf']);
  });
}
