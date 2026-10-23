import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';

import '../support/story_fixtures.dart';

StoryMap _map() => analyze(sampleStory());
final _ids = [for (final s in sampleStory()) s.id];
final _titles = [for (final s in sampleStory()) s.title];

void main() {
  group('entities', () {
    test('add: starts absent everywhere, with its kind, role and note', () {
      final m = _map();
      final n = m.cast.length;
      final i = m.addEntity('Старый порт', EntityKind.place, Role.minor, 'где всё началось');
      expect(i, n);
      final e = m.cast[i];
      expect([e.name, e.kind, e.note], ['Старый порт', EntityKind.place, 'где всё началось']);
      expect(e.perUnit, List.filled(m.unitCount, 0));
      expect(e.perAct, List.filled(m.acts.length, 0));
    });

    test('update: changes only what is given and re-derives the flags', () {
      final m = _map();
      final i = indexOfEntity(m, 'Мэтью');
      m.updateEntity(i, name: 'Матвей', note: 'друг');
      expect(m.cast[i].name, 'Матвей');
      expect(m.cast[i].note, 'друг');
      expect(m.cast[i].kind, EntityKind.person);
      expect(m.flags.any((f) => f.text.startsWith('Матвей')), isTrue);
    });

    test('changing a person into a place takes them out of the flags', () {
      final m = _map();
      final i = indexOfEntity(m, 'Гидеон Кросс');
      expect(m.flags.any((f) => f.who == i), isTrue);
      m.updateEntity(i, kind: EntityKind.place);
      expect(m.flags.any((f) => m.cast[f.who].name == 'Гидеон Кросс'), isFalse);
    });

    test('remove: the entity and its ties go, other ties keep pointing at the right people', () {
      final m = _map();
      final keep = indexOfEntity(m, 'Артур Рэйм'), other = indexOfEntity(m, 'Эвелин Ларк');
      final gone = indexOfEntity(m, 'Мэтью');
      final weight = m.tieBetween(keep, other)!.weight;
      m.removeEntity(gone);
      expect(m.cast.any((c) => c.name == 'Мэтью'), isFalse);
      expect(m.ties.every((t) => t.a < m.cast.length && t.b < m.cast.length), isTrue);
      final a = indexOfEntity(m, 'Артур Рэйм'), e = indexOfEntity(m, 'Эвелин Ларк');
      expect(m.tieBetween(a, e)!.weight, weight);
    });

    test('undo: removing then restoring gives back the same map', () {
      final m = _map();
      m.setTie(0, 2, 'враги');
      final before = m.encode();
      final removed = m.removeEntity(1);
      expect(m.encode(), isNot(before));
      m.restoreEntity(removed);
      expect(m.encode(), before);
    });

    test('undo works for the first and the last entity', () {
      final m = _map();
      final before = m.encode();
      m.restoreEntity(m.removeEntity(0));
      expect(m.encode(), before);
      m.restoreEntity(m.removeEntity(m.cast.length - 1));
      expect(m.encode(), before);
    });

    test('toggling presence marks and unmarks a section and updates the act counts', () {
      final m = _map();
      final i = m.addEntity('Маяк', EntityKind.place, Role.minor, '');
      m.togglePresence(i, 4);
      expect(m.cast[i].perUnit[4], 1);
      expect(m.cast[i].perAct[m.unitAct[4]], 1);
      m.togglePresence(i, 4);
      expect(m.cast[i].perUnit[4], 0);
      expect(m.cast[i].perAct, List.filled(m.acts.length, 0));
    });
  });

  group('ties', () {
    test('a new tie is drawn by hand and is active where both are present', () {
      final m = _map();
      final port = m.addEntity('Порт', EntityKind.place, Role.minor, '');
      m.togglePresence(port, 0);
      final a = indexOfEntity(m, 'Артур Рэйм');
      m.setTie(a, port, 'родился в');
      final t = m.tieBetween(port, a)!;
      expect(t.manual, isTrue);
      expect(t.label, 'родился в');
      expect(t.perAct, [1, 0, 0]);
      m.togglePresence(port, 8);
      expect(t.perAct, [1, 0, 1]);
    });

    test('setting a tie that exists relabels it instead of adding another', () {
      final m = _map();
      final a = indexOfEntity(m, 'Артур Рэйм'), e = indexOfEntity(m, 'Эвелин Ларк');
      final n = m.ties.length;
      m.setTie(a, e, 'сестра');
      expect(m.ties.length, n);
      expect(m.tieBetween(a, e)!.label, 'сестра');
      expect(m.tieBetween(a, e)!.manual, isFalse);
    });

    test('remove: the tie is gone, the people stay', () {
      final m = _map();
      final a = indexOfEntity(m, 'Артур Рэйм'), e = indexOfEntity(m, 'Эвелин Ларк');
      m.removeTie(m.tieBetween(a, e)!);
      expect(m.tieBetween(a, e), isNull);
      expect(m.cast.length, 8);
    });
  });

  group('saved form', () {
    test('survives encode and decode, hand edits included', () {
      final m = _map();
      final port = m.addEntity('Порт "Старый" & <co>', EntityKind.place, Role.minor, 'note');
      m.togglePresence(port, 1);
      m.setTie(0, port, 'родился в');
      final back = StoryMap.decode(m.encode(), _ids, _titles)!;
      expect(back.encode(), m.encode());
      expect(back.cast[port].name, 'Порт "Старый" & <co>');
      expect(back.tieBetween(0, port)!.manual, isTrue);
    });

    test('is rejected when it is not a map this version understands', () {
      expect(StoryMap.decode('nope', _ids, _titles), isNull);
      expect(StoryMap.decode('{"v":2}', _ids, _titles), isNull);
      expect(StoryMap.decode('{"v":1,"cast":"x"}', _ids, _titles), isNull);
    });
  });

  group('realign to the book', () {
    test('a removed section drops its column, the rest stay with their sections', () {
      final m = _map();
      final port = m.addEntity('Порт', EntityKind.place, Role.minor, '');
      m.togglePresence(port, 0);
      m.togglePresence(port, 2);
      m.realign([_ids[0], ..._ids.sublist(2)], [_titles[0], ..._titles.sublist(2)]);
      expect(m.unitCount, 8);
      expect(m.cast[port].perUnit.take(3), [1, 1, 0]);
    });

    test('reordered sections carry their marks along', () {
      final m = _map();
      final port = m.addEntity('Порт', EntityKind.place, Role.minor, '');
      m.togglePresence(port, 0);
      final order = [..._ids.reversed];
      m.realign(order, [..._titles.reversed]);
      expect(m.cast[port].perUnit.last, 1);
      expect(m.cast[port].perUnit.take(8), List.filled(8, 0));
    });

    test('a new section starts empty and joins the act of the section before it', () {
      final m = _map();
      m.realign([..._ids.take(4), 'new', ..._ids.skip(4)], [..._titles.take(4), 'Новая', ..._titles.skip(4)]);
      expect(m.unitCount, 10);
      expect(m.unitAct[4], m.unitAct[3]);
      expect(m.cast.every((c) => c.perUnit[4] == 0), isTrue);
      expect(m.acts.fold<int>(0, (a, b) => a + b.sections), 10);
    });

    test('a same list of sections only refreshes the titles', () {
      final m = _map();
      m.realign(_ids, [for (final t in _titles) '$t!']);
      expect(m.unitTitles.first, '${_titles.first}!');
    });

    test('an emptied map still lines up with a book that gets its first sections', () {
      final m = analyze([]);
      m.realign(['a', 'b'], ['A', 'B']);
      expect(m.unitCount, 2);
      expect(m.acts.single.sections, 2);
    });
  });
}
