import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:xml/xml.dart';

String _book(String title, {String id = 'n1', String pic = 'p.jpg', String cover = 'cover.jpg'}) => '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><author><first-name>A</first-name><last-name>B</last-name></author>
<book-title>$title</book-title><coverpage><image l:href="#$cover"/></coverpage></title-info></description>
<body><title><p>$title</p></title>
<section section-id="s1"><title><p>$title ch1</p></title>
<image l:href="#$pic"/><p>see<a l:href="#$id" type="note">[1]</a></p></section></body>
<body name="notes"><section id="$id"><title><p>1</p></title><p>note of $title</p></section></body>
<binary content-type="image/jpeg" id="$cover">Q09WRVI=</binary>
<binary content-type="image/png" id="$pic">UElD</binary>
</FictionBook>''';

Future<ProjectModel> _load(String xml) async =>
    ProjectModel.fromJson(await Fb2Service().convertXmlToJson(xml));

Iterable<XmlElement> _all(XmlDocument d, String n) =>
    d.rootElement.descendants.whereType<XmlElement>().where((e) => e.name.local == n);

String? _href(XmlElement e) =>
    e.attributes.where((a) => a.name.local == 'href').firstOrNull?.value;

void main() {
  test('chapters, pictures and footnotes of both books stay separate and linked', () async {
    final a = await _load(_book('One'));
    final b = await _load(_book('Two'));
    expect(a.mergeFrom(b), 2);

    final out = XmlDocument.parse(a.getBookXml() as String);
    final body = out.rootElement.findElements('body').first;
    expect(body.findElements('section').map((s) => s.getElement('title')!.innerText),
        ['One ch1', 'Two', 'Two ch1']);

    // every link points at something that exists, and ids are unique
    final ids = [
      ..._all(out, 'binary').map((e) => e.getAttribute('id')!),
      ..._all(out, 'section').map((e) => e.getAttribute('id')).whereType<String>(),
    ];
    expect(ids.toSet().length, ids.length);
    final refs = [..._all(out, 'image'), ..._all(out, 'a')].map(_href).whereType<String>();
    for (final r in refs) {
      expect(ids, contains(r.substring(1)), reason: 'dangling $r');
    }
    expect(refs.toSet().length, 5); // cover + two pictures + two notes, none shared
    expect(_all(out, 'section').where((e) => e.getAttribute('id') != null).length, 2);
    expect(out.rootElement.findElements('body').length, 3);
  });

  test('the merged book keeps its own cover and drops the other one', () async {
    final a = await _load(_book('One'));
    final coverId = a.binaryResource.findBySectionId('cover').id;
    a.mergeFrom(await _load(_book('Two')));
    expect(a.binaryResource.findBySectionId('cover').id, coverId);
    expect(a.binaryResource.resources.where((r) => r.sectionId == 'cover').length, 1);
    expect(a.binaryResource.resources.any((r) => r.id.endsWith('cover.jpg') && r.id.startsWith('m')), isFalse);
    // changing the cover afterwards must not touch the merged pictures
    a.updateInfo({
      'bookCoverPage': '',
      'authorFirst': 'A', 'authorMid': '', 'authorLast': 'B', 'authorHomePage': '',
      'bookTitle': 'One', 'genre': _I([]), 'sequence': _I([]), 'annotation': _I([]),
    });
    expect(a.binaryResource.resources.where((r) => r.id.startsWith('m1_')).length, 1);
  });

  test('merging twice uses a new prefix each time', () async {
    final a = await _load(_book('One'));
    a.mergeFrom(await _load(_book('Two')));
    a.mergeFrom(await _load(_book('Three')));
    final out = XmlDocument.parse(a.getBookXml() as String);
    final ids = _all(out, 'binary').map((e) => e.getAttribute('id')!).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.where((i) => i.startsWith('m1_')).length, 1);
    expect(ids.where((i) => i.startsWith('m2_')).length, 1);
  });

  test('a book without notes or pictures merges too, and the result reloads', () async {
    const plain = '''<?xml version="1.0"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info><book-title>Plain</book-title></title-info></description>
<body><section><title><p>C</p></title><p>text</p></section></body></FictionBook>''';
    final a = await _load(_book('One'));
    expect(a.mergeFrom(await _load(plain)), 2);
    final again = await _load(a.getBookXml() as String);
    expect(again.section.map((s) => s.title), ['One ch1', 'Plain', 'C']);
  });
}

class _I {
  final List items;
  _I(this.items);
}
