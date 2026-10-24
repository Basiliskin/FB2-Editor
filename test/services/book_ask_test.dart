import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/book_ask.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';

AskSection _sec(int n, List<String> paras, [String title = 'T']) => AskSection(n, '$title$n', paras);

DigestStore _store([Map? settings]) {
  final m = settings ?? {};
  return DigestStore(getSettings: () => m, setSettings: (u) async => m.addAll(u));
}

/// Answers from a script and keeps what it was asked. `!` marks a truncated answer.
class _Fake implements LlmClient {
  final List<String> answers;
  final seen = <LlmRequest>[];
  _Fake(this.answers);
  @override
  Future<LlmResponse> complete(LlmRequest r) async {
    seen.add(r);
    final a = answers[seen.length - 1];
    return a.startsWith('!') ? LlmResponse(a.substring(1), truncated: true) : LlmResponse(a);
  }
}

void main() {
  group('pieces', () {
    test('a Section that fits is one piece', () {
      final p = BookAsk.pieces(_sec(3, ['aaa', 'bbb']), 1000);
      expect(p.length, 1);
      expect(p.single.header, '## S3: T3');
      expect(p.single.text, 'aaa\n\nbbb');
    });

    test('a long Section is cut on paragraph breaks, each piece within the limit', () {
      final p = BookAsk.pieces(_sec(1, [for (var i = 0; i < 6; i++) 'x' * 40]), 100);
      expect(p.length, 3);
      expect(p.every((x) => x.text.length <= 100), isTrue);
      expect(p.first.header, '## S1 (part 1 of 3): T1');
      expect(p.map((x) => x.text).join('\n\n'), [for (var i = 0; i < 6; i++) 'x' * 40].join('\n\n'));
    });

    test('one paragraph longer than the limit is cut at a space', () {
      final p = BookAsk.pieces(_sec(1, [List.filled(40, 'word').join(' ')]), 50);
      expect(p.length, greaterThan(1));
      expect(p.every((x) => x.text.length <= 50 && !x.text.startsWith(' ')), isTrue);
    });
  });

  group('plan', () {
    final sections = [for (var i = 1; i <= 4; i++) _sec(i, ['y$i' * 750])];

    test('a range that fits goes in one request with the text itself', () {
      final plan = BookAsk.plan(sections.take(2).toList(), AskMode.question, 'Why?', 5000, _store(), 'en');
      expect(plan.direct, isTrue);
      expect(plan.requests, 1);
      expect(plan.toDigest, isEmpty);
    });

    test('a range that does not fit needs a Digest per piece, then one more request', () {
      final plan = BookAsk.plan(sections, AskMode.summarise, '', 4000, _store(), 'en');
      expect(plan.direct, isFalse);
      expect(plan.toDigest.length, 4);
      expect(plan.requests, 5);
    });

    test('cached Digests are not planned again', () async {
      final store = _store();
      for (final x in sections) {
        await store.put(x.text, 'en', 'digest');
      }
      final plan = BookAsk.plan(sections, AskMode.summarise, '', 4000, store, 'en');
      expect(plan.toDigest, isEmpty);
      expect(plan.requests, 1);
    });

    test('a Digest in another language is not reused', () async {
      final store = _store();
      for (final x in sections) {
        await store.put(x.text, 'ru', 'дайджест');
      }
      expect(BookAsk.plan(sections, AskMode.summarise, '', 4000, store, 'en').toDigest.length, 4);
    });
  });

  group('parse', () {
    final sent = [_sec(1, ['Артур вышел из порта на рассвете.']), _sec(2, ['Эвелин осталась дома.'])];

    test('splits the answer from its evidence and verifies quotes', () {
      final a = BookAsk.parse(
          '## Answer\nАртур ушёл на рассвете [S1].\n\n## Evidence\n- S1: "Артур вышел из порта на рассвете"\n- S2: "Артур вернулся"', sent);
      expect(a.body, 'Артур ушёл на рассвете [S1].');
      expect(a.evidence.map((e) => e.verified), [true, false]);
      expect(a.evidence.first.section, 1);
    });

    test('a quote must stand in the Section it names, not just anywhere', () {
      final a = BookAsk.parse('## Answer\nx\n## Evidence\n- S2: "Артур вышел из порта"', sent);
      expect(a.evidence.single.verified, isFalse);
    });

    test('quotes match across case, spacing and quote marks', () {
      final a = BookAsk.parse('## Answer\nx\n## Evidence\n- S1: «артур   вышел из ПОРТА»', sent);
      expect(a.evidence.single.verified, isTrue);
    });

    test('citations outside the range are dropped', () {
      final a = BookAsk.parse('## Answer\nОн ушёл [S1], потом вернулся [S9] и [S2, S7].', sent);
      expect(a.body, 'Он ушёл [S1], потом вернулся  и [S2].');
    });

    test('an answer with no headings is all body', () {
      final a = BookAsk.parse('Just text [S2].', sent);
      expect(a.body, 'Just text [S2].');
      expect(a.evidence, isEmpty);
    });

    test('fences and chatter do not break it', () {
      final a = BookAsk.parse('```markdown\n## Answer\nFine.\n```', sent);
      expect(a.body, 'Fine.');
    });

    test('answer text before an Evidence heading with no Answer heading is kept', () {
      final a = BookAsk.parse('Short answer.\n\n## Evidence\n- S1: "Артур вышел"', sent);
      expect(a.body, 'Short answer.');
      expect(a.evidence.single.verified, isTrue);
    });

    test('flags carry through', () {
      final a = BookAsk.parse('## Answer\nx', sent, fromDigests: true, truncated: true);
      expect((a.fromDigests, a.truncated), (true, true));
    });
  });

  group('DigestStore', () {
    test('keeps at most maxDigests, dropping the oldest', () async {
      final settings = {};
      final store = _store(settings);
      for (var i = 0; i < DigestStore.maxDigests + 3; i++) {
        await store.put('text $i', 'en', 'd$i');
      }
      expect(store.get('text 0', 'en'), isNull);
      expect(store.get('text 2', 'en'), isNull);
      expect(store.get('text 3', 'en'), 'd3');
      expect(store.get('text ${DigestStore.maxDigests + 2}', 'en'), isNotNull);
      expect((settings['ask-digests'] as Map).length, DigestStore.maxDigests);
    });

    test('putting a text again refreshes it instead of duplicating', () async {
      final settings = {};
      final store = _store(settings);
      await store.put('a', 'en', '1');
      await store.put('a', 'en', '2');
      expect(store.get('a', 'en'), '2');
      expect((settings['ask-digest-order'] as List).length, 1);
    });
  });

  group('BookAskRunner', () {
    final sections = [for (var i = 1; i <= 3; i++) _sec(i, ['Артур в разделе $i. ' * 20])];

    test('a range that fits is one request and keeps the evidence checks', () async {
      final fake = _Fake(['## Answer\nДа [S2].\n## Evidence\n- S2: "Артур в разделе 2."']);
      final plan = BookAsk.plan(sections, AskMode.question, 'Кто?', 100000, _store(), 'en');
      final a = await BookAskRunner(fake, _store(), 'en').run(plan, sections);
      expect(fake.seen.length, 1);
      expect(fake.seen.single.user, contains('Question: Кто?'));
      expect(fake.seen.single.user, contains('## S2: T2'));
      expect(fake.seen.single.system, contains('## Evidence'));
      expect(a.fromDigests, isFalse);
      expect(a.evidence.single.verified, isTrue);
    });

    test('a long range is digested piece by piece, then answered from the Digests', () async {
      final fake = _Fake(['d1', 'd2', 'd3', '## Answer\nThe whole story [S1, S3].']);
      final settings = {};
      final plan = BookAsk.plan(sections, AskMode.summarise, '', 600, _store(settings), 'en');
      final seen = <int>[];
      final a = await BookAskRunner(fake, _store(settings), 'en').run(plan, sections, onRequest: seen.add);
      expect(fake.seen.length, 4);
      expect(seen, [1, 2, 3, 4]);
      expect(fake.seen.last.user, allOf(contains('d1'), contains('d2'), contains('d3')));
      expect(fake.seen.last.system, isNot(contains('## Evidence')));
      expect(a.fromDigests, isTrue);
      expect(a.body, 'The whole story [S1, S3].');
    });

    test('Digests made once are reused the next time', () async {
      final settings = {};
      final first = _Fake(['d1', 'd2', 'd3', '## Answer\none']);
      await BookAskRunner(first, _store(settings), 'en')
          .run(BookAsk.plan(sections, AskMode.summarise, '', 600, _store(settings), 'en'), sections);
      final second = _Fake(['## Answer\ntwo']);
      final plan = BookAsk.plan(sections, AskMode.question, 'Q?', 600, _store(settings), 'en');
      expect(plan.requests, 1);
      final a = await BookAskRunner(second, _store(settings), 'en').run(plan, sections);
      expect(second.seen.length, 1);
      expect(second.seen.single.user, contains('d2'));
      expect(a.body, 'two');
    });

    test('a truncated Digest is used once but not cached', () async {
      final settings = {};
      final fake = _Fake(['!cut', 'd2', 'd3', '## Answer\nok']);
      await BookAskRunner(fake, _store(settings), 'en')
          .run(BookAsk.plan(sections, AskMode.summarise, '', 600, _store(settings), 'en'), sections);
      expect(_store(settings).get(sections[0].text, 'en'), isNull);
      expect(_store(settings).get(sections[1].text, 'en'), 'd2');
    });

    test('a failure keeps the Digests already made', () async {
      final settings = {};
      final fake = _Fake(['d1']); // the second request runs out of answers and throws
      await expectLater(
          BookAskRunner(fake, _store(settings), 'en')
              .run(BookAsk.plan(sections, AskMode.summarise, '', 600, _store(settings), 'en'), sections),
          throwsA(anything));
      expect(_store(settings).get(sections[0].text, 'en'), 'd1');
    });

    test('Digests too many for one request are merged first', () async {
      final many = [for (var i = 1; i <= 6; i++) _sec(i, ['z$i' * 200])];
      final digestOf = 'D' * 300;
      final fake = _Fake([for (var i = 0; i < 6; i++) digestOf, 'm1', 'm2', 'm3', '## Answer\nfin']);
      final plan = BookAsk.plan(many, AskMode.summarise, '', 1000, _store(), 'en');
      final a = await BookAskRunner(fake, _store(), 'en').run(plan, many);
      expect(a.body, 'fin');
      expect(fake.seen.sublist(6, 9).every((r) => r.system == BookAsk.mergeSystem('en')), isTrue);
      expect(fake.seen.last.user, allOf(contains('m1'), contains('m2'), contains('m3')));
    });

    test('a truncated answer is flagged', () async {
      final fake = _Fake(['!## Answer\nhalf a sent']);
      final plan = BookAsk.plan([sections[0]], AskMode.summarise, '', 100000, _store(), 'en');
      expect((await BookAskRunner(fake, _store(), 'en').run(plan, [sections[0]])).truncated, isTrue);
    });
  });
}
