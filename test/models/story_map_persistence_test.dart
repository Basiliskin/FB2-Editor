import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/fb2.service.dart';

import '../support/story_fixtures.dart';

Future<ProjectModel> _reopen(ProjectModel book) async =>
    ProjectModel.fromJson(await Fb2Service().convertXmlToJson(book.getBookXml() as String));

void main() {
  test('loading builds the map from the text and does not touch the book', () async {
    final book = await storyBook();
    final before = book.getBookXml();
    final m = await book.loadStoryMap();
    expect(m.cast, isNotEmpty);
    expect(book.getBookXml(), before);
    expect(book.getBookXml(), isNot(contains('story-map')));
  });

  test('the same map comes back every time while the book is open', () async {
    final book = await storyBook();
    final m = await book.loadStoryMap();
    expect(identical(await book.loadStoryMap(), m), isTrue);
    expect(identical(book.loadedStoryMap, m), isTrue);
  });

  test('a saved map is written as FB2 custom-info and survives save and reopen', () async {
    final book = await storyBook();
    final m = await book.loadStoryMap();
    final port = m.addEntity('Порт "Старый" & <co>', EntityKind.place, Role.minor, 'заметка');
    m.togglePresence(port, 1);
    m.setTie(0, port, 'родился в');
    book.saveStoryMap(m);

    final xml = book.getBookXml() as String;
    expect(xml, contains('<custom-info info-type="story-map">'));
    // the description is the only place it lives, and the file is still well-formed
    expect(xml.indexOf('story-map'), lessThan(xml.indexOf('<body>')));

    final again = await _reopen(book);
    for (var i = 0; i < book.section.length; i++) {
      again.section[i].sectionId = book.section[i].sectionId;
    }
    final back = await again.loadStoryMap();
    expect(back.cast.length, m.cast.length);
    expect(back.cast[port].name, 'Порт "Старый" & <co>');
    expect(back.cast[port].note, 'заметка');
    expect(back.cast[port].perUnit[1], 1);
    expect(back.tieBetween(0, port)!.label, 'родился в');
  });

  test('saving twice keeps a single copy', () async {
    final book = await storyBook();
    final m = await book.loadStoryMap();
    book.saveStoryMap(m);
    m.addEntity('X', EntityKind.lore, Role.minor, '');
    book.saveStoryMap(m);
    expect('story-map'.allMatches(book.getBookXml() as String).length, 1);
  });

  test('other custom-info parts of the book are left alone', () async {
    final book = await storyBook();
    book.descriptionExtras.add({'name': 'custom-info', 'xml': '<custom-info info-type="mine">keep me</custom-info>'});
    book.saveStoryMap(await book.loadStoryMap());
    book.discardStoryMap();
    final xml = book.getBookXml() as String;
    expect(xml, contains('keep me'));
    expect(xml, isNot(contains('story-map')));
  });

  test('discarding drops the saved map and the next load builds a fresh one', () async {
    final book = await storyBook();
    final m = await book.loadStoryMap();
    m.addEntity('Лишнее', EntityKind.lore, Role.minor, '');
    book.saveStoryMap(m);
    book.discardStoryMap();
    expect(book.getBookXml(), isNot(contains('story-map')));
    expect((await book.loadStoryMap()).cast.any((c) => c.name == 'Лишнее'), isFalse);
  });

  test('a broken saved map is ignored and the map is built from the text', () async {
    final book = await storyBook();
    book.descriptionExtras.add({'name': 'custom-info', 'xml': '<custom-info info-type="story-map">not json</custom-info>'});
    final m = await book.loadStoryMap();
    expect(m.cast, isNotEmpty);
  });

  test('sections added, removed or reordered after saving are lined up on load', () async {
    final book = await storyBook();
    final m = await book.loadStoryMap();
    final port = m.addEntity('Порт', EntityKind.place, Role.minor, '');
    m.togglePresence(port, 0);
    book.saveStoryMap(m);

    final again = await _reopen(book);
    for (var i = 0; i < book.section.length; i++) {
      again.section[i].sectionId = book.section[i].sectionId;
    }
    again.section.removeAt(5);
    again.addSection('Новая');
    final back = await again.loadStoryMap();
    expect(back.unitCount, again.section.length);
    expect(back.unitIds, [for (final s in again.section) s.sectionId]);
    expect(back.cast[port].perUnit[0], 1);
  });

  test('a section added after the map was loaded shows up when it is read again', () async {
    final book = await storyBook();
    await book.loadStoryMap();
    book.addSection('Ещё');
    expect(book.loadedStoryMap!.unitCount, book.section.length);
  });
}
