import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/pages/settings_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
import 'package:quill_fb2/services/voice/voice_availability.dart';

import '../support/form_harness.dart';

void main() {
  late AppService service;

  setUp(() {
    mockDocumentsDir();
    service = AppService();
    service.providerStore = ProviderStore(
        getSettings: () => service.getSettings(),
        setSettings: (m) => service.setSettings(m),
        session: MemoryKeyVault(),
        persistent: MemoryKeyVault(),
        isWeb: false);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(service)));
  }

  Future<void> tapSave(WidgetTester tester, Finder button) async {
    await tester.tap(button);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title and the settings form', (tester) async {
    await pump(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Editing'), findsOneWidget);
  });

  testWidgets('offers Voice input, off by default, and saves the switch',
      (tester) async {
    await pump(tester);
    expect(find.text('Voice input'), findsOneWidget);
    expect(service.getSettings()['voice-input'], isNull);
    expect(voiceInputEnabled(service.getSettings()), isFalse);

    await tester.tap(find.text('Dictate with the microphone'));
    await tester.pump();
    await tapSave(tester, find.text('Save'));

    expect(service.getSettings()['voice-input'], isTrue);
    expect(voiceInputEnabled(service.getSettings()), isTrue);
  });

  testWidgets('shows Voice input switched on from the saved setting',
      (tester) async {
    service.getSettings()['voice-input'] = true;
    await pump(tester);
    final tile = tester.widget<SwitchListTile>(find.ancestor(
        of: find.text('Dictate with the microphone'),
        matching: find.byType(SwitchListTile)));
    expect(tile.value, isTrue);
  });

  testWidgets('shows Voice input in Russian', (tester) async {
    service.getSettings()['language'] = 'ru';
    await pump(tester);
    expect(find.text('Голосовой ввод'), findsOneWidget);
  });

  testWidgets('hides Voice input off Android and keeps the setting untouched',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(tester);
      expect(find.text('Voice input'), findsNothing);

      await tapSave(tester, find.byType(FloatingActionButton));
      expect(service.getSettings().containsKey('voice-input'), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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

  testWidgets('adds an AI provider and keeps its key out of the settings',
      (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Add provider'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Work');
    await tester.enterText(fields.at(2), 'SECRET');
    await tester.pump();
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 5; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Work'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Work'), findsOneWidget);
    expect(service.getSettings().toString(), isNot(contains('SECRET')));
    final saved = await tester.runAsync(() => service.providerStore.list());
    expect(saved!.single.apiKey, 'SECRET');
  });
}
