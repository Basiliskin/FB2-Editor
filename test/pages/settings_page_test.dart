import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/pages/settings_page.dart';
import 'package:quill_fb2/services/app.service.dart';

import '../support/form_harness.dart';

void main() {
  late AppService service;

  setUp(() {
    mockDocumentsDir();
    service = AppService();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(service)));
  }

  testWidgets('shows the title and the settings form', (tester) async {
    await pump(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Editing'), findsOneWidget);
  });

  testWidgets('shows a Russian title when the language is ru', (tester) async {
    service.getSettings()['language'] = 'ru';
    await pump(tester);
    expect(find.text('Настройки'), findsOneWidget);
  });

  testWidgets('handles app lifecycle changes', (tester) async {
    service.getSettings()['auto-save'] = true;
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives hot reload, which closes the change stream',
      (tester) async {
    await pump(tester);
    tester.binding.reassembleApplication();
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
