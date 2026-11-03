import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/widgets/section_editor/note_chips.dart';

void main() {
  const mark = '<a l:href="#n1" type="note">[1]</a>';

  test('links become chips and come back unchanged', () {
    const text = 'a${mark}b<strong>c</strong><a xlink:href="#p">x</a>';
    final doc = Document.fromJson(noteOps(text));
    expect(doc.length, 'abc<strong>c</strong>'.length - 1 + 2 + 1);
    expect(serializeNotes(doc), text);
    expect(serializeNotes(Document.fromJson(noteOps(''))), '');
  });

  test('closed paragraphs show only the label', () {
    expect(showNoteLabels('tea$mark <em>x</em>'), 'tea[1] <em>x</em>');
  });

  test('chip id, label and the chip near the cursor', () {
    expect(noteChipId(mark), 'n1');
    expect(noteChipLabel('<a l:href="#n1"><sup>2</sup></a>'), '2');
    expect(noteChipId('nothing'), '');
    final doc = Document.fromJson(noteOps('tea$mark!'));
    expect(noteChipNear(doc, 3)?.offset, 3);
    expect(noteChipNear(doc, 4)?.xml, mark);
    expect(noteChipNear(doc, 1), isNull);
    expect(noteChipNear(doc, 5), isNull);
  });
}
