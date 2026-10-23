import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/widgets/forms/annotation.dart';

import '../support/form_harness.dart';

void main() {
  late FormHarness harness;
  setUp(() => harness = FormHarness());

  Future<void> pump(WidgetTester tester, List<String> items) => harness.pump(
      tester,
      AnnotationFormField(
          name: 'annotation',
          initialValue: AnnotationData('Annotation', items)));

  List<String> saved() =>
      (harness.lastValues['annotation'] as AnnotationData).items;

  testWidgets('lists existing paragraphs', (tester) async {
    await pump(tester, ['one', 'two']);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('shows no divider when empty', (tester) async {
    await pump(tester, []);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('Add appends the paragraph and clears the input',
      (tester) async {
    await pump(tester, ['one']);
    await tester.enterText(find.byType(TextField), 'two');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await harness.save(tester);
    expect(saved(), ['one', 'two']);
  });

  testWidgets('Add ignores blank input', (tester) async {
    await pump(tester, ['one']);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await harness.save(tester);
    expect(saved(), ['one']);
  });

  testWidgets('adding an existing paragraph case-insensitively moves it',
      (tester) async {
    await pump(tester, ['one', 'two']);
    await tester.enterText(find.byType(TextField), 'ONE');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await harness.save(tester);
    expect(saved(), ['two', 'ONE']);
  });

  testWidgets('the close button removes that paragraph only', (tester) async {
    await pump(tester, ['one', 'two', 'three']);
    await tester.tap(find.byIcon(Icons.close).at(1));
    await tester.pumpAndSettle();
    await harness.save(tester);
    expect(saved(), ['one', 'three']);
  });
}
