import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';
import 'package:xml/xml.dart';

class _Service extends AppService {
  @override
  saveProject(ProjectModel model) async {}
  @override
  getSettings() => {};
}

String _plain(String xml) => XmlDocument.parse(xml).rootElement.innerText;

/// Random activate / edit / split / save sequences must never lose or garble text.
void main() {
  const start = [
    '<p>plain one</p>',
    '<p>two <strong>bold</strong> and <emphasis>italic</emphasis> end</p>',
    '<p>AT&amp;T &lt; 5</p>',
    '<p>see<a l:href="#n1" type="note">[1]</a> note</p>',
    '<p>  indented</p>',
    '<p>six</p>',
  ];

  for (final seed in [1, 2, 3]) {
    testWidgets('random edits keep every paragraph (seed $seed)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final service = _Service();
      final book = ProjectModel.fromJson({'title': 'B', 'section': []});
      final Section section = book.addSection('S');
      section.p = [...start];
      var expected = start.map(_plain).toList();
      var markup = start.map((p) => RegExp('<(strong|emphasis|a)[ >]').allMatches(p).length).fold<int>(0, (a, b) => a + b);
      await tester.pumpWidget(MaterialApp(home: SectionEditor(service, book, section)));
      await tester.pump();

      final rnd = Random(seed);
      int? active;
      for (var op = 0; op < 80; op++) {
        final tiles = find.descendant(
            of: find.byType(ListView), matching: find.byType(InkWell));
        final n = expected.length;
        switch (rnd.nextInt(4)) {
          case 0: // activate a paragraph
            final i = rnd.nextInt(n);
            final tileIndex = active != null && i > active! ? i - 1 : i;
            if (active == i) break;
            await tester.tap(tiles.at(tileIndex), warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            active = i;
          case 1: // type at the start of the active paragraph
            if (active == null) break;
            final c = tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
            c.replaceText(0, 0, '#$op ', null);
            expected[active!] = '#$op ${expected[active!]}';
            await tester.pump();
          case 2: // split the active paragraph with a new line at its end
            if (active == null || n >= 11) break;
            final c = tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
            c.replaceText(c.document.length - 1, 0, '\nsplit$op', null);
            await tester.pump();
            // the new line becomes its own paragraph once committed
            expected.insert(active! + 1, 'split$op');
            // keep the model aligned: commit now so indices match what is shown
            await tester.tap(find.byIcon(Icons.save_outlined));
            await tester.pump();
            await tester.pump();
            active = null;
          case 3: // save
            await tester.tap(find.byIcon(Icons.save_outlined));
            await tester.pump();
            await tester.pump();
            if (find.byType(QuillEditor).evaluate().isEmpty) active = null;
        }
      }
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pump();
      await tester.pump();

      expect(section.p.map(_plain).toList(), expected);
      for (final p in section.p) {
        expect(() => XmlDocument.parse(p), returnsNormally, reason: p);
      }
      final kept = section.p.fold<int>(
          0, (a, p) => a + RegExp('<(strong|emphasis|a)[ >]').allMatches(p).length);
      expect(kept, markup, reason: 'inline markup must survive edits');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
