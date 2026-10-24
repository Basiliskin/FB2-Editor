import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/book_ask.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/story_map_ai.dart';

StoryMap _map() {
  final m = StoryMap([const ActInfo('Act 1', 2)], [], [], ['a', 'b'], ['One', 'Two'], [0, 0]);
  final a = m.addEntity('Артур', EntityKind.person, Role.major, '');
  final b = m.addEntity('Эвелин', EntityKind.person, Role.major, '');
  m.cast[a].perUnit = [2, 1];
  m.cast[b].perUnit = [1, 1];
  m.ties.add(Tie(a, b, 2, [2], null));
  m.recompute();
  return m;
}

const _sections = [
  AskSection(1, 'One', ['Артур пришёл в Хейвене к порту.', 'Эвелин ждала в Хейвене.']),
  AskSection(2, 'Two', ['Праздник Фонарей начался.', 'Артур молчал.']),
];

class _Fake implements LlmClient {
  final List<String> answers;
  final seen = <LlmRequest>[];
  _Fake(this.answers);
  @override
  Future<LlmResponse> complete(LlmRequest r) async {
    seen.add(r);
    return LlmResponse(answers[seen.length - 1]);
  }
}

void main() {
  group('plan', () {
    test('puts the map and the sections into one request when they fit', () {
      final plan = StoryMapAi.plan(_map(), _sections, 24000);
      expect(plan.requests, 1);
      expect(plan.batches.single, contains('- Артур (person)'));
      expect(plan.batches.single, contains('Ties without a label:\n- Артур — Эвелин'));
      expect(plan.batches.single, contains('## S2: Two'));
    });

    test('splits the text over several requests under a small limit', () {
      final long = [AskSection(1, 'Long', [for (var i = 0; i < 40; i++) 'Абзац номер $i ${'слово ' * 40}'])];
      final plan = StoryMapAi.plan(_map(), long, 4000);
      expect(plan.requests, greaterThan(1));
      expect(plan.characters, greaterThan(plan.requests * 1000));
    });

    test('a book without text needs no request', () {
      expect(StoryMapAi.plan(_map(), const [AskSection(1, 'Empty', [])], 24000).requests, 0);
    });
  });

  group('parse', () {
    test('keeps entities the text mentions, with counts per section, and drops invented ones', () {
      final got = StoryMapAi.parse(
          '## entity\nname: Хейвен\nkind: place\nnote: A port city.\n\n'
          '## entity\nname: Праздник Фонарей\nkind: event\nnote: A feast.\n\n'
          '## entity\nname: Атлантида\nkind: place\nnote: Made up.',
          _map(),
          _sections);
      expect(got.entities.map((e) => e.name), ['Хейвен', 'Праздник Фонарей']);
      expect(got.entities.first.perUnit, [2, 0]); // "Хейвене" twice, found by its stem
      expect(got.entities.last.perUnit, [0, 1]);
      expect(got.entities.first.kind, EntityKind.place);
    });

    test('skips what is on the map, repeats, people and unknown kinds', () {
      final got = StoryMapAi.parse(
          '## entity\nname: Артур\nkind: lore\n\n## entity\nname: Хейвен\nkind: place\n\n## entity\nname: хейвен\nkind: place\n\n'
          '## entity\nname: Порт\nkind: person',
          _map(),
          _sections);
      expect(got.entities.map((e) => e.name), ['Хейвен']);
    });

    test('labels a tie between map names and between a map name and a new entity', () {
      final got = StoryMapAi.parse(
          '## tie\na: Артур\nb: Эвелин\nlabel: brother of\n\n## entity\nname: Хейвен\nkind: place\n\n'
          '## tie\na: артур\nb: Хейвен\nlabel: lives in',
          _map(),
          _sections);
      expect(got.ties.length, 2);
      expect(got.ties[0].exists, isTrue);
      expect(got.ties[1].exists, isFalse);
      expect(got.ties[1].b, 'Хейвен');
    });

    test('drops a tie to an unknown name, a self tie, a label that is empty, and a tie already labelled', () {
      final m = _map();
      final got = StoryMapAi.parse(
          '## tie\na: Артур\nb: Никто\nlabel: x\n\n## tie\na: Артур\nb: Артур\nlabel: x\n\n## tie\na: Артур\nb: Эвелин\nlabel:',
          m,
          _sections);
      expect(got.ties, isEmpty);
      m.setTie(0, 1, 'mine');
      expect(StoryMapAi.parse('## tie\na: Артур\nb: Эвелин\nlabel: theirs', m, _sections).ties, isEmpty);
    });

    test('rubbish and chatter give no proposals', () {
      expect(StoryMapAi.parse('{"entities": []}', _map(), _sections).isEmpty, isTrue);
      expect(StoryMapAi.parse('Sure!\n```markdown\n### Entity 1\n- **name**: Хейвен\n- **kind**: **Place**\n```', _map(), _sections).entities.length, 1);
    });
  });

  group('accept', () {
    test('adds the entity with its mentions, and labels the tie', () {
      final m = _map();
      final c = StoryMapAi.accept(m, const EntityProposal('Хейвен', EntityKind.place, 'A port.', [2, 0]));
      expect(m.cast[c].kind, EntityKind.place);
      expect(m.cast[c].perUnit, [2, 0]);
      expect(StoryMapAi.acceptTie(m, const TieProposal('Артур', 'Хейвен', 'lives in', exists: false)), isTrue);
      expect(m.tieBetween(0, c)!.label, 'lives in');
      expect(StoryMapAi.acceptTie(m, const TieProposal('Артур', 'Нет', 'x', exists: false)), isFalse);
    });
  });

  group('runner', () {
    test('merges the answers of several requests and keeps only resolvable ties', () async {
      final m = _map();
      final fake = _Fake([
        '## entity\nname: Хейвен\nkind: place\n\n## tie\na: Артур\nb: Хейвен\nlabel: lives in',
        '## entity\nname: Хейвен\nkind: place\n\n## tie\na: Артур\nb: Нигде\nlabel: x',
      ]);
      final seen = <int>[];
      final got = await StoryMapAiRunner(fake, 'en')
          .run(StoryMapAiPlan(['one', 'two'], 6), m, _sections, onRequest: seen.add);
      expect(got.entities.length, 1);
      expect(got.ties.length, 1);
      expect(seen, [1, 2]);
      expect(fake.seen.first.system, contains('in English'));
    });

    test('the system prompt asks for the answer in the book language', () {
      expect(StoryMapAi.systemPrompt('ru'), contains('in Russian'));
    });
  });
}
