import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/widgets/field.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';
import 'package:quill_fb2/widgets/logo_loader.dart';
import 'package:quill_fb2/widgets/wave.progress.dart';

void main() {
  group('QuillField', () {
    late QuillController controller;
    late FocusNode focus;
    late ScrollController scroll;

    setUp(() {
      controller = QuillController.basic();
      focus = FocusNode();
      scroll = ScrollController();
    });
    tearDown(() {
      controller.dispose();
      focus.dispose();
      scroll.dispose();
    });

    Widget host(QuillField f) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, height: 400, child: f)));

    testWidgets('renders the editor without a toolbar', (tester) async {
      await tester.pumpWidget(host(QuillField(
        controller: controller,
        focusNode: focus,
        scrollController: scroll,
        decoration: const InputDecoration(labelText: 'Notes'),
      )));
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.text('Notes'), findsWidgets);
    });

    testWidgets('toolbar follows focus and focus nodes can be swapped',
        (tester) async {
      Widget field(FocusNode node) => host(QuillField(
            controller: controller,
            focusNode: node,
            scrollController: scroll,
            readOnly: true,
            toolbar: const Text('toolbar'),
          ));
      await tester.pumpWidget(field(focus));
      Visibility vis() => tester.widget<Visibility>(find.ancestor(
          of: find.text('toolbar', skipOffstage: false),
          matching: find.byType(Visibility)));
      expect(vis().visible, isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(vis().visible, isTrue);

      final other = FocusNode();
      addTearDown(other.dispose);
      await tester.pumpWidget(field(other));
      expect(vis().visible, isFalse);
      other.requestFocus();
      await tester.pump();
      expect(vis().visible, isTrue);
    });
  });

  group('WaveProgress', () {
    testWidgets('animates and survives a hot reassemble', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: WaveProgress(100, Colors.blue, Colors.lightBlue, 60)));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(CustomPaint), findsWidgets);
      // reassemble replaces the controller (dev hot reload)
      final state =
          tester.state<WaveProgressState>(find.byType(WaveProgress));
      final replaced = state.controller;
      state.reassemble();
      replaced.dispose();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
    });

    test('clipper and painter repaint policies', () {
      final clip = CircleClipper();
      expect(clip.shouldReclip(CircleClipper()), isTrue);
      expect(clip.getClip(const Size(10, 10)).getBounds().width, 10);
    });
  });

  group('LogoLoader', () {
    testWidgets('paints through its whole cycle', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Center(child: LogoLoader(size: 100))));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(LogoLoader), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('loading dialog', () {
    testWidgets('ModalRoundedProgressBar shows its message', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: ModalRoundedProgressBar(0.9, 'Working'))));
      expect(find.text('Working'), findsOneWidget);
      expect(find.byType(LogoLoader), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Dialogs.showLoadingDialog opens a blocking dialog',
        (tester) async {
      final key = GlobalKey();
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      Dialogs.showLoadingDialog(ctx, key);
      await tester.pump();
      expect(find.text('Please Wait....'), findsOneWidget);
      expect(find.byKey(key), findsOneWidget);
      // not dismissible by back or barrier tap
      await tester.tapAt(const Offset(1, 1));
      await tester.pump();
      expect(find.text('Please Wait....'), findsOneWidget);
      final guard = tester
          .widget<WillPopScope>(find.byType(WillPopScope).last);
      expect(await guard.onWillPop!(), isFalse);
      Navigator.of(ctx).pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
    });

    test('ProgressBarHandler holds callbacks', () {
      var shown = 0;
      final h = ProgressBarHandler();
      h.show = () => shown++;
      h.dismiss = () {};
      h.show();
      h.dismiss();
      expect(shown, 1);
    });
  });
}
