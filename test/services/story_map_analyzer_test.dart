import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';

import '../support/story_fixtures.dart';

StorySection _sec(String id, List<String> text) => StorySection(id, 'T$id', [for (final t in text) '<p>$t</p>']);

void main() {
  group('analyze', () {
    final story = sampleStory();
    final map = analyze(story);

    test('finds the people, most mentioned first, and folds first name + surname', () {
      expect(map.cast.map((c) => c.name), [
        'Артур Рэйм', 'Эвелин Ларк', 'Гидеон Кросс', 'Габриэль Вейн', 'Мэтью', 'Капитан Брент', 'Исайя', 'Сивилла Векс'
      ]);
      expect(map.cast.every((c) => c.kind == EntityKind.person), isTrue);
    });

    test('one unit per section, three acts cut on section boundaries', () {
      expect(map.unitIds, [for (final s in story) s.id]);
      expect(map.acts.map((a) => a.sections), [3, 3, 3]);
      expect(map.unitAct, [0, 0, 0, 1, 1, 1, 2, 2, 2]);
    });

    test('counts who appears in which act, and gaps show as zeros', () {
      final kross = map.cast[indexOfEntity(map, 'Гидеон Кросс')];
      expect(kross.perAct[1], 0);
      expect(kross.perAct[0], greaterThan(0));
      expect(kross.perAct[2], greaterThan(0));
      final vane = map.cast[indexOfEntity(map, 'Габриэль Вейн')];
      expect(vane.perAct[0], 0);
    });

    test('ranks the roles: the most mentioned is the protagonist', () {
      expect(map.cast.first.role, Role.protagonist);
      expect(map.cast[1].role, Role.major);
      expect(map.cast.last.role, Role.minor);
    });

    test('ties come from shared paragraphs; the busiest pair first', () {
      final a = indexOfEntity(map, 'Артур Рэйм'), e = indexOfEntity(map, 'Эвелин Ларк');
      final tie = map.tieBetween(a, e)!;
      expect(tie.manual, isFalse);
      expect(tie.weight, greaterThan(0));
      expect(map.ties.first.weight, greaterThanOrEqualTo(map.ties.last.weight));
    });

    test('flags an important person who drops out of an act', () {
      final texts = map.flags.map((f) => f.text);
      expect(texts, contains('Гидеон Кросс: not mentioned in Act 2'));
      expect(texts, contains('Габриэль Вейн: not mentioned in Act 1'));
    });

    test('keeps a snippet of the text where each person first shows up in an act', () {
      final a = map.cast[indexOfEntity(map, 'Артур Рэйм')];
      expect(a.snippet[0], contains('Артур Рэйм'));
    });
  });

  group('names', () {
    test('Russian endings fold into one person', () {
      final m = analyze([
        _sec('1', [
          'Вчера Артур пришёл рано.',
          'Потом мы видели Артура у моста.',
          'Мы сказали Артуру правду.',
          'С Артуром все согласны.',
        ]),
      ]);
      expect(m.cast.single.name, 'Артур');
      expect(m.cast.single.total, 4);
    });

    test('a word that is only capitalised at the start of a sentence is not a name', () {
      final m = analyze([
        _sec('1', ['Дождь шёл. Дождь не кончался. Дождь был сильный. Вдруг дождь затих.']),
      ]);
      expect(m.cast, isEmpty);
    });

    test('a surname shared by two first names stays separate from both', () {
      final m = analyze([
        _sec('1', [
          'Тогда Анна Вейн вошла. Потом Борис Вейн вышел. Рядом Анна Вейн ждала, а Борис Вейн молчал.',
          'Позже Анна Вейн ушла, и Борис Вейн остался. Наутро Анна Вейн вернулась, а Борис Вейн уехал.',
        ]),
      ]);
      final names = m.cast.map((c) => c.name).toList();
      expect(names, containsAll(['Анна', 'Борис']));
    });

    test('latin names work too', () {
      final m = analyze([
        _sec('1', ['Then Arthur left. Later he saw Arthur again, and Arthur smiled. Nobody knew Arthur.']),
      ]);
      expect(m.cast.single.name, 'Arthur');
    });
  });

  group('edge cases', () {
    test('a book with no sections gives an empty map', () {
      final m = analyze([]);
      expect(m.cast, isEmpty);
      expect(m.unitCount, 0);
    });

    test('empty sections stay in the map as units', () {
      final m = analyze([_sec('1', []), _sec('2', []), _sec('3', [])]);
      expect(m.unitIds, ['1', '2', '3']);
      expect(m.acts.map((a) => a.sections).fold<int>(0, (x, y) => x + y), 3);
    });

    test('one or two sections still make a map', () {
      final m = analyze([_sec('1', ['Тут Артур. Там Артур. Здесь Артур.'])]);
      expect(m.unitCount, 1);
      expect(m.acts.length, 1);
      expect(m.cast.single.perAct, [3]);
    });

    test('tags and entities in the text are ignored', () {
      final m = analyze([
        StorySection('1', 'T', ['<p>Сегодня <strong>Артур</strong> &amp; <emphasis>Артур</emphasis> и Артур</p>']),
      ]);
      expect(m.cast.single.name, 'Артур');
    });
  });
}
