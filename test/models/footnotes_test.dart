import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/footnotes.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:xml/xml.dart';

const _plainNote = '<section id="n1"><title><p>1</p></title><p>Tea urn.</p><p>Russian.</p></section>';
const _richNote = '<section id="n2"><title><p>2</p></title><p>A <emphasis>fancy</emphasis> note</p></section>';
const _orphan = '<section id="n9"><title><p>9</p></title><p>Never marked.</p></section>';

String _book({String text = 'samovar<a l:href="#n1" type="note">[1]</a> and<a l:href="#n2" type="note">[2]</a>',
        String notes = '$_plainNote$_richNote$_orphan'}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><book-title>T</book-title></title-info></description>
<body><section><title><p>Ch</p></title><p>$text</p></section></body>
<body name="notes"><title><p>Notes</p></title>$notes</body>
<body name="comments"><section id="c1"><p>keep me</p></section></body>
</FictionBook>''';

Future<ProjectModel> _load(String xml) async =>
    ProjectModel.fromJson(await Fb2Service().convertXmlToJson(xml));

List<String> _savedNoteIds(ProjectModel b) {
  final doc = XmlDocument.parse(b.getBookXml() as String);
  final notes = doc.rootElement.findElements('body').where((e) => e.getAttribute('name') == 'notes');
  return [for (final n in notes) for (final s in n.findElements('section')) s.getAttribute('id')!];
}

void main() {
  group('reading', () {
    test('plain notes are editable, formatted ones are not, other bodies are ignored', () {
      final notes = readFootnotes([
        '<body name="notes"><title><p>Notes</p></title>$_plainNote$_richNote<section><p>no id</p></section></body>',
        '<body name="comments"><section id="c1"><p>x</p></section></body>',
        '<body name="notes"><broken',
      ]);
      expect(notes.map((n) => (n.id, n.label, n.text, n.editable)), [
        ('n1', '1', 'Tea urn.\nRussian.', true),
        ('n2', '2', 'A fancy note', false),
      ]);
    });

    test('a note with extra attributes, a styled title or a poem stays read-only', () {
      for (final sec in [
        '<section id="a" lang="en"><p>x</p></section>',
        '<section id="a"><title><p><strong>1</strong></p></title><p>x</p></section>',
        '<section id="a"><poem><stanza><v>x</v></stanza></poem></section>',
        '<section id="a">loose text<p>x</p></section>',
      ]) {
        expect(readFootnotes(['<body name="notes">$sec</body>']).single.editable, isFalse, reason: sec);
      }
      expect(readFootnotes(['<body name="notes"><section id="a"><p>x</p></section></body>']).single.label, '');
    });

    test('findFootnote returns null for an unknown id', () {
      expect(findFootnote(['<body name="notes">$_plainNote</body>'], 'zz'), isNull);
    });
  });

  group('writing', () {
    test('put replaces in place, appends, or creates the notes body', () {
      var bodies = ['<body name="notes">$_plainNote</body>'];
      bodies = putFootnote(bodies, 'n1', '1', 'New <text> & more\n\n line two ');
      expect(findFootnote(bodies, 'n1')!.text, 'New <text> & more\nline two');
      bodies = putFootnote(bodies, 'n5', '*', 'star');
      expect(readFootnotes(bodies).map((n) => n.id), ['n1', 'n5']);
      expect(putFootnote(['<body name="comments"/>'], 'x', '', 'hi'),
          ['<body name="comments"/>', '<body name="notes"><section id="x"><p>hi</p></section></body>']);
    });

    test('remove drops only the listed notes and leaves other bodies untouched', () {
      const other = '<body name="comments"><section id="n1"/></body>';
      final out = removeFootnotes(['<body name="notes">$_plainNote$_richNote</body>', other], {'n1'});
      expect(readFootnotes(out).map((n) => n.id), ['n2']);
      expect(out[1], same(other));
      final same_ = ['<body name="notes">$_plainNote</body>'];
      expect(removeFootnotes(same_, {}), same(same_));
    });
  });

  group('marks', () {
    test('next label is one past the highest number', () {
      expect(nextFootnoteLabel([]), '1');
      expect(nextFootnoteLabel(const [Footnote('a', '[3]', ''), Footnote('b', '*', ''), Footnote('c', '12', '')]), '13');
    });

    test('new ids skip taken ones', () {
      expect(newFootnoteId({}), 'note_1');
      expect(newFootnoteId({'note_1', 'note_2'}), 'note_3');
    });

    test('mark xml escapes and is found by offset', () {
      final mark = noteMarkXml('n"1', '<1>');
      expect(mark, '<a l:href="#n&quot;1" type="note">[&lt;1&gt;]</a>');
      final text = 'ab<a l:href="#n1" type="note">[1]</a>cd<a l:href="#pic">x</a>';
      final end = text.indexOf('cd');
      expect(noteMarkAt(text, 2, {'n1'}), (start: 2, end: end, id: 'n1'));
      expect(noteMarkAt(text, end, {'n1'})?.id, 'n1');
      expect(noteMarkAt(text, 1, {'n1'}), isNull);
      expect(noteMarkAt(text, text.length - 2, {'n1'}), isNull); // not a note
    });

    test('lists linked ids', () {
      expect(linkedIds('<image l:href="#p"/><a l:href="#n">').toList(), ['p', 'n']);
    });
  });

  group('book', () {
    test('a loaded book lists its footnotes and saves unchanged when untouched', () async {
      final b = await _load(_book());
      expect(b.footnotes.map((n) => n.id), ['n1', 'n2', 'n9']);
      expect(_savedNoteIds(b), ['n1', 'n2', 'n9']);
      expect(b.getBookXml(), contains('keep me'));
    });

    test('add, update and delete', () async {
      final b = await _load(_book());
      final id = b.addFootnote('3', 'new note');
      expect(id, 'note_1');
      expect(b.footnote(id)!.text, 'new note');
      expect(b.updateFootnote('n1', '1', 'fixed'), isTrue);
      expect(b.footnote('n1')!.text, 'fixed');
      expect(b.updateFootnote('n2', '2', 'nope'), isFalse);
      expect(b.footnote('n2')!.text, 'A fancy note');
      b.deleteFootnote('n1');
      expect(b.footnoteIds, {'n2', 'n9', id});
    });

    test('a note whose mark is gone is dropped on save; one never marked is kept', () async {
      final b = await _load(_book());
      final newId = b.addFootnote('3', 'unused');
      b.section.first.p = ['<p>no marks left</p>'];
      expect(_savedNoteIds(b), ['n9']);
      // still there in memory, so undo can bring the mark back
      expect(b.footnoteIds, containsAll(['n1', 'n2', newId]));
    });

    test('a note pointed at only from another note is kept', () async {
      final b = await _load(_book(
          notes: '$_plainNote<section id="n2"><p>see<a l:href="#n1">[1]</a></p></section>',
          text: 'x<a l:href="#n2" type="note">[2]</a>'));
      b.section.first.p = ['<p>x<a l:href="#n2" type="note">[2]</a></p>'];
      expect(_savedNoteIds(b), ['n1', 'n2']);
    });

    test('new ids avoid ids already used in the text', () async {
      final b = await _load(_book(text: '<a l:href="#note_1">[1]</a>', notes: '<section id="note_1"><p>x</p></section>'));
      expect(b.addFootnote('2', 'y'), 'note_2');
    });

    test('a book without notes gets a notes body for its first footnote', () async {
      final b = ProjectModel.fromJson({'title': 'B', 'section': []});
      final s = b.addSection('S');
      final id = b.addFootnote('1', 'hello');
      s.p = ['<p>hi${noteMarkXml(id, '1')}</p>'];
      expect(_savedNoteIds(b), [id]);
      final again = await _load(b.getBookXml() as String);
      expect(again.footnote(id)!.text, 'hello');
    });

    test('merged notes whose marks are removed are dropped too', () async {
      final a = await _load(_book(notes: _plainNote, text: 'a<a l:href="#n1" type="note">[1]</a>'));
      final b = await _load(_book(notes: _plainNote, text: 'b<a l:href="#n1" type="note">[1]</a>'));
      a.mergeFrom(b);
      expect(_savedNoteIds(a), hasLength(2));
      for (final s in a.section) {
        s.p = ['<p>none</p>'];
      }
      expect(_savedNoteIds(a), isEmpty);
    });
  });
}
