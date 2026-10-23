import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/pages/settings_page.dart';
import 'package:quill_fb2/services/app.service.dart';

import '../support/form_harness.dart';

void main() {
  late AppService service;
  late Directory docs;

  setUp(() {
    docs = mockDocumentsDir();
    service = AppService();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(service)));
  }

  Map persisted() =>
      jsonDecode(File('${docs.path}/fb2_workspace.json').readAsStringSync())
          as Map;

  Future<void> choose(WidgetTester tester, String current, String option) async {
    await tester.tap(find.text(current).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title, groups and current values', (tester) async {
    await pump(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Editing'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('12'), findsOneWidget); // default font size
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('reads string-typed saved settings', (tester) async {
    service.workspace['workspaceSettings'] = {
      'auto-save': 'true',
      'show-image': 'true',
      'font-size': '16',
      'image-width': '800',
      'image-quality': 'best',
      'language': 'eng',
    };
    await pump(tester);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('800'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.every((s) => s.value), isTrue);
  });

  testWidgets('Save persists the changed values and confirms', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await choose(tester, '12', '20');
    await tester.tap(find.text('Save'));
    await settleIO(tester);

    final s = service.getSettings();
    expect(s['auto-save'], isTrue);
    expect(s['font-size'], 20);
    expect(persisted()['workspaceSettings']['font-size'], 20);
    expect(find.text('Settings Saved'), findsOneWidget);
  });

  testWidgets('changes are not stored until Save is pressed', (tester) async {
    await pump(tester);
    await choose(tester, '12', '20');
    expect(service.getSettings()['font-size'], 12);
  });

  testWidgets('Save keeps untouched values', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Save'));
    await settleIO(tester);
    final s = service.getSettings();
    expect(s['font-size'], 12);
    expect(s['language'], 'eng');
    expect(s['image-quality'], 100);
    expect(s['image-width'], 600);
  });

  testWidgets('switching the language to Russian is saved', (tester) async {
    await pump(tester);
    await choose(tester, 'English', 'Русский');
    await tester.tap(find.text('Save'));
    await settleIO(tester);
    expect(service.getSettings()['language'], 'ru');
    expect(service.workspace['language'], 'ru');
  });
}
