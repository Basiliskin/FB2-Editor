import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/forms/settings.form.dart';

import '../support/form_harness.dart';

void main() {
  late AppService service;
  late StreamController<void> trigger;

  setUp(() {
    mockDocumentsDir();
    service = AppService();
    trigger = StreamController<void>.broadcast();
    addTearDown(trigger.close);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SettingsComponent(
                service, service.getSettings(), trigger.stream))));
  }

  testWidgets('the save trigger confirms with a snack bar and hides the loader',
      (tester) async {
    await pump(tester);
    trigger.add(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Settings Saved'), findsOneWidget);
    expect(find.text('Loading'), findsNothing);
  });

  testWidgets('the show-image switch is saved with the settings',
      (tester) async {
    await pump(tester);
    expect(service.getSettings()['show-image'], isNot(true));
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settleIO(tester);
    expect(service.getSettings()['show-image'], isTrue);
  });
}
