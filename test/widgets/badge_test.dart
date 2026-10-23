import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/widgets/badge/badges.dart';

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('without child renders only the badge (slide)', (tester) async {
    await _pump(tester, Badge(key: UniqueKey(), badgeContent: const Text('1')));
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(BadgePositioned), findsNothing);
  });

  testWidgets('scale and fade animations', (tester) async {
    await _pump(
        tester,
        Badge(
            key: UniqueKey(),
            badgeContent: const Text('1'),
            animationType: BadgeAnimationType.scale));
    expect(find.byType(ScaleTransition), findsWidgets);
    await _pump(
        tester,
        Badge(
            key: UniqueKey(),
            badgeContent: const Text('1'),
            animationType: BadgeAnimationType.fade));
    expect(find.byType(FadeTransition), findsWidgets);
  });

  testWidgets('toAnimate false skips transitions', (tester) async {
    await _pump(tester,
        Badge(key: UniqueKey(), badgeContent: const Text('1'), toAnimate: false));
    for (final t in [SlideTransition, ScaleTransition]) {
      expect(
          find.descendant(
              of: find.byType(Badge), matching: find.byType(t)),
          findsNothing);
    }
  });

  testWidgets('square shape and unknown animation fallthrough',
      (tester) async {
    await _pump(
        tester,
        Badge(
            key: UniqueKey(),
          badgeContent: const Text('1'),
          shape: BadgeShape.square,
          borderRadius: 4,
        ));
    expect(find.text('1'), findsOneWidget);
    // null shape -> unknown branch; null animationType -> no transition
    await _pump(
        tester,
        Badge(
            key: UniqueKey(),
          badgeContent: const Text('1'),
          shape: null,
          animationType: null,
          showBadge: false,
        ));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0);
  });

  testWidgets('with child stacks badge at default and custom positions',
      (tester) async {
    await _pump(
        tester,
        Badge(
            key: UniqueKey(),
            badgeContent: const Text('1'),
            child: const Icon(Icons.mail)));
    expect(find.byIcon(Icons.mail), findsOneWidget);
    expect(find.byType(BadgePositioned), findsOneWidget);
    for (final p in [
      BadgePosition.topStart(),
      BadgePosition.topEnd(),
      BadgePosition.bottomEnd(),
      BadgePosition.bottomStart(),
    ]) {
      await _pump(
          tester,
          Badge(
              key: UniqueKey(),
              badgeContent: const Text('1'),
              position: p,
              child: const Icon(Icons.mail)));
      expect(find.byType(BadgePositioned), findsOneWidget);
    }
  });

  testWidgets('content change restarts animation, same content does not',
      (tester) async {
    Widget build(Widget content) => MaterialApp(
        home: Badge(badgeContent: content, child: const SizedBox()));
    await tester.pumpWidget(build(const Text('1')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(build(const Text('1')));
    await tester.pumpWidget(build(const Text('2')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(build(const Icon(Icons.add)));
    await tester.pumpWidget(build(const Icon(Icons.add)));
    await tester.pumpWidget(build(const Icon(Icons.remove)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.remove), findsOneWidget);
  });
}
