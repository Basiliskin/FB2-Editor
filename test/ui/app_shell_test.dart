import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/main.dart' as app;
import 'package:quill_fb2/main.dart' show MyApp;
import 'package:quill_fb2/pages/home_page.dart';
import 'package:quill_fb2/pages/start_page.dart';
import 'package:quill_fb2/routes.dart';
import 'package:quill_fb2/ui/theme.dart';

void main() {
  test('Routes keep stable names', () {
    expect(Routes.screenStart, 'SCREEN_START');
    expect(Routes.screenHome, 'SCREEN_HOME');
  });

  test('Keys exposes one shared navigator key', () {
    expect(Keys.navKey, isA<GlobalKey<NavigatorState>>());
    expect(identical(Keys.navKey, Keys.navKey), isTrue);
  });

  group('appTheme', () {
    final theme = appTheme();
    test('is Material 3 with a blue seeded scheme', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.primary,
          ColorScheme.fromSeed(seedColor: Colors.blue).primary);
    });
    test('app bar uses the primary colours, centred and flat', () {
      final bar = theme.appBarTheme;
      expect(bar.backgroundColor, theme.colorScheme.primary);
      expect(bar.foregroundColor, theme.colorScheme.onPrimary);
      expect(bar.centerTitle, isTrue);
      expect(bar.elevation, 0);
    });
    test('cards are flat and rounded with an outline', () {
      final card = theme.cardTheme;
      expect(card.elevation, 0);
      expect(card.color, theme.colorScheme.surfaceContainerLowest);
      final shape = card.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
      expect(shape.side.color, theme.colorScheme.outlineVariant);
    });
    test('inputs have a rounded outline border', () {
      final border = theme.inputDecorationTheme.border as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(12));
    });
  });

  testWidgets('MyApp starts on the start screen with the home route',
      (tester) async {
    await tester.pumpWidget(MyApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'FB2 Editor');
    expect(app.theme!.useMaterial3, isTrue);
    expect(find.byType(StartScreen), findsOneWidget);

    final home = app.routes![Routes.screenHome]!;
    late Widget built;
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) => built = home(c))));
    expect(built, isA<HomeScreen>());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('main() runs the app', (tester) async {
    app.main();
    await tester.pump();
    expect(find.byType(MyApp), findsOneWidget);
    expect(find.byType(StartScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
