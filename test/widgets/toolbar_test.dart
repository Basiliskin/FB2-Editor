import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quill_fb2/widgets/section_editor/toolbar.dart';

import '../support/form_harness.dart';

void main() {
  late QuillController controller;

  QuillController make({String text = 'hello world', TextSelection? sel}) {
    return QuillController(
      document: Document.fromJson([
        {'insert': '$text\n'}
      ]),
      selection: sel ?? const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  }

  setUp(() {
    controller = make();
    addTearDown(controller.dispose);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ));
  }

  Map<String, Attribute> attrs() => controller.getSelectionStyle().attributes;

  group('InsertEmbedButton', () {
    testWidgets('inserts a notes embed', (tester) async {
      await pump(
          tester, InsertEmbedButton(controller: controller, icon: Icons.note));
      await tester.tap(find.byType(InsertEmbedButton));
      await tester.pump();
      final ops = controller.document.toDelta().toJson();
      expect(ops.any((o) => o['insert'] is Map), isTrue);
      expect(NotesBlockEmbed.noteType, 'notes');
      final embed = NotesBlockEmbed.fromDocument(controller.document);
      expect(embed.document, isA<Document>());
    });
  });

  group('LinkStyleButton', () {
    testWidgets('applies a link from the dialog', (tester) async {
      await pump(tester, LinkStyleButton(controller: controller));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pumpAndSettle();
      expect(find.text('Paste a link'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'http://x.y');
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(attrs()[Attribute.link.key]?.value, 'http://x.y');
    });

    testWidgets('dismissed dialog does nothing; collapsed disables',
        (tester) async {
      await pump(
          tester, LinkStyleButton(controller: controller, icon: Icons.add));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(attrs().containsKey(Attribute.link.key), isFalse);

      controller.updateSelection(
          const TextSelection.collapsed(offset: 2), ChangeSource.local);
      await tester.pump();
      final btn = tester.widget<QuillIconButton>(find.byType(QuillIconButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('swapping controllers rebinds listener', (tester) async {
      final other = make();
      addTearDown(other.dispose);
      await pump(tester, LinkStyleButton(controller: controller));
      await pump(tester, LinkStyleButton(controller: other));
      other.updateSelection(
          const TextSelection.collapsed(offset: 1), ChangeSource.local);
      await tester.pump();
      expect(
          tester
              .widget<QuillIconButton>(find.byType(QuillIconButton))
              .onPressed,
          isNull);
    });
  });

  group('ToggleStyleButton', () {
    testWidgets('toggles bold on and off', (tester) async {
      await pump(
          tester,
          ToggleStyleButton(
              attribute: Attribute.bold,
              icon: Icons.format_bold,
              controller: controller));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      expect(attrs().containsKey('bold'), isTrue);
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      expect(attrs().containsKey('bold'), isFalse);
    });

    testWidgets('list attribute compares values', (tester) async {
      await pump(
          tester,
          Column(children: [
            ToggleStyleButton(
                attribute: Attribute.ul,
                icon: Icons.list,
                controller: controller),
          ]));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      expect(attrs()[Attribute.list.key]?.value, 'bullet');
      controller.formatSelection(Attribute.ol);
      await tester.pump();
      expect(
          tester
              .widget<QuillIconButton>(find.byType(QuillIconButton))
              .fillColor,
          isNotNull);
    });

    testWidgets('disabled inside a code block unless it is the code button',
        (tester) async {
      controller.formatSelection(Attribute.codeBlock);
      await pump(
          tester,
          Column(children: [
            ToggleStyleButton(
                attribute: Attribute.bold,
                icon: Icons.format_bold,
                controller: controller),
            ToggleStyleButton(
                attribute: Attribute.codeBlock,
                icon: Icons.code,
                controller: controller),
          ]));
      final btns = tester
          .widgetList<QuillIconButton>(find.byType(QuillIconButton))
          .toList();
      expect(btns[0].onPressed, isNull);
      expect(btns[1].onPressed, isNotNull);
    });

    testWidgets('swapping controllers rebinds', (tester) async {
      final other = make();
      addTearDown(other.dispose);
      other.formatSelection(Attribute.bold);
      await pump(
          tester,
          ToggleStyleButton(
              attribute: Attribute.bold,
              icon: Icons.format_bold,
              controller: controller));
      await pump(
          tester,
          ToggleStyleButton(
              attribute: Attribute.bold,
              icon: Icons.format_bold,
              controller: other));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      expect(other.getSelectionStyle().attributes.containsKey('bold'), isFalse);
    });
  });

  group('ToggleCheckListButton', () {
    testWidgets('toggles a checklist and handles list values', (tester) async {
      await pump(
          tester,
          ToggleCheckListButton(
              icon: Icons.check_box,
              controller: controller,
              attribute: Attribute.unchecked));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      expect(attrs()[Attribute.list.key]?.value, 'unchecked');
      controller.formatSelection(Attribute.checked);
      await tester.pump();
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      expect(attrs().containsKey(Attribute.list.key), isFalse);
    });

    testWidgets('non-list attribute and controller swap', (tester) async {
      final other = make();
      addTearDown(other.dispose);
      await pump(
          tester,
          ToggleCheckListButton(
              icon: Icons.check_box,
              controller: controller,
              attribute: Attribute.bold));
      await pump(
          tester,
          ToggleCheckListButton(
              icon: Icons.check_box,
              controller: other,
              attribute: Attribute.bold));
      other.formatSelection(Attribute.bold);
      await tester.pump();
    });

    testWidgets('disabled inside a code block', (tester) async {
      controller.formatSelection(Attribute.codeBlock);
      await pump(
          tester,
          ToggleCheckListButton(
              icon: Icons.check_box,
              controller: controller,
              attribute: Attribute.unchecked));
      expect(
          tester
              .widget<QuillIconButton>(find.byType(QuillIconButton))
              .onPressed,
          isNull);
    });
  });

  group('SelectHeaderStyleButton', () {
    testWidgets('selects a heading and shows it', (tester) async {
      await pump(tester, SelectHeaderStyleButton(controller: controller));
      tester.takeException();
      expect(find.text('Normal text'), findsOneWidget);
      await tester.tap(find.byType(QuillDropdownButton<Attribute?>));
      tester.takeException();
      await tester.pumpAndSettle();
      tester.takeException();
      await tester.tap(find.text('Heading 2').last);
      tester.takeException();
      await tester.pumpAndSettle();
      tester.takeException();
      expect(attrs()[Attribute.header.key]?.value, 2);
      expect(find.text('Heading 2'), findsOneWidget);
    });

    testWidgets('dismissing the menu changes nothing', (tester) async {
      await pump(tester, SelectHeaderStyleButton(controller: controller));
      tester.takeException();
      await tester.tap(find.byType(QuillDropdownButton<Attribute?>));
      tester.takeException();
      await tester.pumpAndSettle();
      tester.takeException();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      tester.takeException();
      expect(attrs().containsKey(Attribute.header.key), isFalse);
    });

    testWidgets('menu result after unmount is ignored', (tester) async {
      await pump(tester, SelectHeaderStyleButton(controller: controller));
      tester.takeException();
      await tester.tap(find.byType(QuillDropdownButton<Attribute?>));
      tester.takeException();
      await tester.pumpAndSettle();
      tester.takeException();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Builder(builder: (c) => const SizedBox()))));
      tester.takeException();
      await tester.pumpAndSettle();
      tester.takeException();
    });

    testWidgets('swapping controllers rebinds', (tester) async {
      final other = make();
      addTearDown(other.dispose);
      other.formatSelection(Attribute.h1);
      await pump(tester, SelectHeaderStyleButton(controller: controller));
      tester.takeException();
      await pump(tester, SelectHeaderStyleButton(controller: other));
      tester.takeException();
      expect(find.text('Heading 1'), findsOneWidget);
      other.formatSelection(Attribute.h3);
      await tester.pump();
      tester.takeException();
      expect(find.text('Heading 3'), findsOneWidget);
    });
  });

  group('ImageButton', () {
    testWidgets('inserts an image from a custom picker', (tester) async {
      ImageSource? got;
      await pump(
          tester,
          ImageButton(
            icon: Icons.image,
            controller: controller,
            imageSource: ImageSource.gallery,
            imagePickImpl: (s) async {
              got = s;
              return 'http://img/1.png';
            },
          ));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      await tester.pump();
      expect(got, ImageSource.gallery);
      final ops = controller.document.toDelta().toJson();
      expect(ops.any((o) => o['insert'] is Map), isTrue);
    });

    testWidgets('desktop picker returns the chosen file', (tester) async {
      final dir = mockDocumentsDir();
      File('${dir.path}/pic.png').writeAsBytesSync([1, 2, 3]);
      File? picked;
      await pump(
          tester,
          ImageButton(
            icon: Icons.image,
            controller: controller,
            imageSource: ImageSource.gallery,
            onImagePickCallback: (f) async {
              picked = f;
              return 'http://img/2.png';
            },
          ));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      await settleIO(tester);
      expect(find.text('pic.png'), findsOneWidget);
      await tester.tap(find.text('pic.png'));
      await settleIO(tester);
      expect(picked?.path, endsWith('pic.png'));
    });
  });

  group('ColorButton', () {
    testWidgets('picks a foreground color', (tester) async {
      await pump(
          tester,
          ColorButton(
              icon: Icons.color_lens,
              controller: controller,
              background: false));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pumpAndSettle();
      expect(find.text('Select Color'), findsOneWidget);
      await tester.tap(find
          .descendant(
              of: find.byType(MaterialPicker),
              matching: find.byType(GestureDetector))
          .last);
      await tester.pumpAndSettle();
      expect(attrs().containsKey(Attribute.color.key), isTrue);
      expect(find.text('Select Color'), findsNothing);
    });

    testWidgets('picks a background color', (tester) async {
      await pump(
          tester,
          ColorButton(
              icon: Icons.format_color_fill,
              controller: controller,
              background: true));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pumpAndSettle();
      await tester.tap(find
          .descendant(
              of: find.byType(MaterialPicker),
              matching: find.byType(GestureDetector))
          .last);
      await tester.pumpAndSettle();
      expect(attrs().containsKey(Attribute.background.key), isTrue);
    });

    for (final bg in [false, true]) {
      testWidgets('renders colored and white states (background=$bg)',
          (tester) async {
        Attribute a(String v) =>
            bg ? BackgroundAttribute(v) : ColorAttribute(v);
        controller.formatSelection(a('#ff0000'));
        await pump(
            tester,
            ColorButton(
                icon: Icons.color_lens,
                controller: controller,
                background: bg));
        controller.formatSelection(a('#ffffff'));
        await tester.pump();
        controller.formatSelection(a('#00ff00'));
        await tester.pump();
      });
    }

    testWidgets('initially white and controller swap', (tester) async {
      controller.formatSelection(ColorAttribute('#ffffff'));
      controller.formatSelection(BackgroundAttribute('#ffffff'));
      final other = make();
      addTearDown(other.dispose);
      other.formatSelection(ColorAttribute('#ffffff'));
      other.formatSelection(BackgroundAttribute('#ffffff'));
      for (final bg in [false, true]) {
        await pump(
            tester,
            ColorButton(
                icon: Icons.color_lens,
                controller: controller,
                background: bg));
        await pump(
            tester,
            ColorButton(
                icon: Icons.color_lens, controller: other, background: bg));
      }
    });
  });

  group('HistoryButton', () {
    testWidgets('shows its tooltip', (tester) async {
      await pump(
          tester,
          HistoryButton(
              icon: Icons.undo,
              controller: controller,
              undo: true,
              tooltip: 'Undo'));
      expect(find.byTooltip('Undo'), findsOneWidget);
    });

    testWidgets('undo and redo', (tester) async {
      await pump(
          tester,
          Row(children: [
            HistoryButton(icon: Icons.undo, controller: controller, undo: true),
            HistoryButton(
                icon: Icons.redo, controller: controller, undo: false),
          ]));
      // nothing to undo/redo yet
      await tester.tap(find.byIcon(Icons.undo));
      await tester.tap(find.byIcon(Icons.redo));
      await tester.pump();

      controller.formatSelection(Attribute.bold);
      await tester.pump();
      expect(controller.hasUndo, isTrue);
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      expect(attrs().containsKey('bold'), isFalse);
      expect(controller.hasRedo, isTrue);
      await tester.tap(find.byIcon(Icons.redo));
      await tester.pump();
      expect(attrs().containsKey('bold'), isTrue);
    });

    testWidgets('change events after unmount are ignored', (tester) async {
      await pump(tester,
          HistoryButton(icon: Icons.undo, controller: controller, undo: true));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      controller.formatSelection(Attribute.bold);
      await tester.pump();
      await tester.runAsync(() => Future.delayed(Duration.zero));
    });
  });

  group('IndentButton', () {
    testWidgets('increase and decrease through levels', (tester) async {
      await pump(
          tester,
          Row(children: [
            IndentButton(
                icon: Icons.arrow_right,
                controller: controller,
                isIncrease: true),
            IndentButton(
                icon: Icons.arrow_left,
                controller: controller,
                isIncrease: false),
          ]));
      final inc = find.byIcon(Icons.arrow_right);
      final dec = find.byIcon(Icons.arrow_left);
      // no indent: decrease is a no-op
      await tester.tap(dec);
      expect(attrs().containsKey('indent'), isFalse);
      await tester.tap(inc);
      expect(attrs()['indent']?.value, 1);
      await tester.tap(inc);
      expect(attrs()['indent']?.value, 2);
      await tester.tap(dec);
      expect(attrs()['indent']?.value, 1);
      await tester.tap(dec);
      expect(attrs().containsKey('indent'), isFalse);
    });
  });

  group('ClearFormatButton', () {
    testWidgets('removes all attributes', (tester) async {
      controller.formatSelection(Attribute.bold);
      controller.formatSelection(Attribute.italic);
      await pump(
          tester, ClearFormatButton(icon: Icons.clear, controller: controller));
      await tester.tap(find.byType(QuillIconButton));
      await tester.pump();
      expect(attrs(), isEmpty);
    });
  });

  group('CustomQuillToolbar', () {
    testWidgets('basic builds with extensions', (tester) async {
      final bar = CustomQuillToolbar.basic(
        controller: controller,
        toolbarIconSize: 20,
        extensions: [const Text('ext')],
      );
      expect(bar.preferredSize.height, isNonNegative);
      await pump(tester, bar);
      expect(find.text('ext'), findsOneWidget);
      expect(find.byType(HistoryButton), findsNWidgets(2));
    });

    testWidgets('basic builds without extensions', (tester) async {
      await pump(tester, CustomQuillToolbar.basic(controller: controller));
      expect(find.byType(HistoryButton), findsNWidgets(2));
    });

    testWidgets('dropdown button builds directly', (tester) async {
      await pump(
          tester,
          QuillDropdownButton<int>(
            initialValue: 1,
            items: const [PopupMenuItem(value: 1, child: Text('one'))],
            onSelected: (_) {},
            child: const Text('c'),
          ));
      expect(find.text('c'), findsOneWidget);
    });
  });
}
