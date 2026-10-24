import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/dictation_target.dart';

QuillController _quill(String text, [TextSelection? selection]) {
  return QuillController(
    document: Document.fromJson([
      {'insert': '$text\n'},
    ]),
    selection: selection ?? const TextSelection.collapsed(offset: 0),
  );
}

void main() {
  group('TextFieldDictationTarget', () {
    test('inserts at the cursor and moves the cursor after the words', () {
      final c = TextEditingController(text: 'Купить хлеб')
        ..selection = const TextSelection.collapsed(offset: 7);
      final target = TextFieldDictationTarget(c);

      expect(target.insert(target.anchor(), 'молоко и'), isTrue);

      expect(c.text, 'Купить молоко и хлеб');
      expect(c.selection, const TextSelection.collapsed(offset: 15));
    });

    test('replaces a selection', () {
      final c = TextEditingController(text: 'buy milk now')
        ..selection = const TextSelection(baseOffset: 4, extentOffset: 8);
      final target = TextFieldDictationTarget(c);

      target.insert(target.anchor(), 'bread');

      expect(c.text, 'buy bread now');
    });

    test('goes to the end when the field has no selection yet', () {
      final c = TextEditingController(text: 'abc');
      final target = TextFieldDictationTarget(c);

      expect(target.anchor(), (start: 3, end: 3));
      target.insert(target.anchor(), 'def');

      expect(c.text, 'abc def');
    });

    test('uses the saved anchor even if the cursor has moved since', () {
      final c = TextEditingController(text: 'ab')
        ..selection = const TextSelection.collapsed(offset: 1);
      final target = TextFieldDictationTarget(c);
      final anchor = target.anchor();
      c.selection = const TextSelection.collapsed(offset: 2);

      target.insert(anchor, 'x');

      expect(c.text, 'a x b');
    });

    test('clamps an anchor that is past the text after it was shortened', () {
      final c = TextEditingController(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 4, extentOffset: 6);
      final target = TextFieldDictationTarget(c);
      final anchor = target.anchor();
      c.text = 'ab';

      target.insert(anchor, 'x');

      expect(c.text, 'ab x');
    });

    test('inserts nothing for blank dictation', () {
      final c = TextEditingController(text: 'abc');
      final target = TextFieldDictationTarget(c);

      expect(target.insert(target.anchor(), '  '), isFalse);
      expect(c.text, 'abc');
    });
  });

  group('QuillDictationTarget', () {
    test('inserts at the cursor with spacing', () {
      final c = _quill('Hello.', const TextSelection.collapsed(offset: 5));
      final target = QuillDictationTarget(c);

      expect(target.insert(target.anchor(), 'world'), isTrue);

      expect(c.document.toPlainText(), 'Hello world.\n');
      expect(c.selection, const TextSelection.collapsed(offset: 11));
    });

    test('replaces a selection', () {
      final c = _quill(
          'buy milk now', const TextSelection(baseOffset: 4, extentOffset: 8));
      final target = QuillDictationTarget(c);

      target.insert(target.anchor(), 'bread');

      expect(c.document.toPlainText(), 'buy bread now\n');
    });

    test('appends to the end of an empty paragraph', () {
      final c = _quill('');
      final target = QuillDictationTarget(c);

      target.insert(target.anchor(), 'first words');

      expect(c.document.toPlainText(), 'first words\n');
    });

    test('never touches the trailing newline when dictating at the end', () {
      final c = _quill('abc', const TextSelection.collapsed(offset: 3));
      final target = QuillDictationTarget(c);

      target.insert(target.anchor(), 'def');

      expect(c.document.toPlainText(), 'abc def\n');
    });

    test('one undo takes the whole dictation back', () {
      final c = _quill('ab', const TextSelection.collapsed(offset: 1));
      final target = QuillDictationTarget(c);

      target.insert(target.anchor(), 'x');
      expect(c.document.toPlainText(), 'a x b\n');
      c.undo();

      expect(c.document.toPlainText(), 'ab\n');
    });

    test('takes the formatting at the cursor as if typed', () {
      final c = QuillController(
        document: Document.fromJson([
          {'insert': 'bold', 'attributes': {'bold': true}},
          {'insert': '\n'},
        ]),
        selection: const TextSelection.collapsed(offset: 4),
      );
      final target = QuillDictationTarget(c);

      target.insert(target.anchor(), 'more');

      expect(c.document.toPlainText(), 'bold more\n');
      final ops = c.document.toDelta().toJson();
      expect(ops.first['attributes'], {'bold': true});
    });

    test('uses the saved anchor and clamps it to a shortened text', () {
      final c = _quill('abcdef', const TextSelection.collapsed(offset: 6));
      final target = QuillDictationTarget(c);
      final anchor = target.anchor();
      c.replaceText(0, 5, '', const TextSelection.collapsed(offset: 0));

      target.insert(anchor, 'x');

      expect(c.document.toPlainText(), 'f x\n');
    });

    test('inserts nothing for blank dictation', () {
      final c = _quill('abc');
      final target = QuillDictationTarget(c);

      expect(target.insert(target.anchor(), ''), isFalse);
      expect(c.document.toPlainText(), 'abc\n');
    });

    test('without a valid selection it dictates at the end', () {
      final c = _quill('abc', const TextSelection.collapsed(offset: -1));
      final target = QuillDictationTarget(c);

      expect(target.anchor(), (start: 3, end: 3));
    });
  });
}
