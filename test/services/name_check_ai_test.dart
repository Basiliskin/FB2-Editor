import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/name_check.dart';
import 'package:quill_fb2/services/name_check_ai.dart';

NameFinding _pair(String a, String b, {String qa = 'qa', String qb = 'qb'}) => NameFinding([
      NameVariant(a, 12, [NameLocation(0, 0, '$qa $a')]),
      NameVariant(b, 1, [NameLocation(0, 1, '$qb $b')]),
    ], NameFindingKind.similar);

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

NameCheckStore _store([Map? settings]) {
  final m = settings ?? {};
  return NameCheckStore(getSettings: () => m, setSettings: (u) async => m.addAll(u));
}

void main() {
  group('NameMarkdown.request', () {
    test('lists the spellings and quotes for each numbered pair', () {
      final md = NameMarkdown.request([_pair('Артур', 'Артор'), _pair('Анна', 'Ана')]);
      expect(md, contains('## 1'));
      expect(md, contains('## 2'));
      expect(md, contains('- "Артур" (12 times)'));
      expect(md, contains('> Артор: "qb Артор"'));
    });
  });

  group('NameMarkdown.parse', () {
    test('reads a well-formed answer', () {
      final a = NameMarkdown.parse('## 1\nverdict: same\ncanonical: Артур\nreason: A typo.\n\n## 2\nverdict: different\nreason: Two people.');
      expect(a[1]!.verdict, NameVerdict.same);
      expect(a[1]!.canonical, 'Артур');
      expect(a[1]!.reason, 'A typo.');
      expect(a[2]!.verdict, NameVerdict.different);
    });

    test('copes with fences, bold, bullets and chatter around the blocks', () {
      final a = NameMarkdown.parse('Sure! Here you go:\n```markdown\n### Pair 1\n- **verdict**: **Same**\n- **canonical**: "Артур"\n- **reason**: typo\n```\nHope that helps.');
      expect(a[1]!.verdict, NameVerdict.same);
      expect(a[1]!.canonical, 'Артур');
    });

    test('a block without a clear verdict is left out', () {
      final a = NameMarkdown.parse('## 1\nverdict: maybe\n\n## 2\nreason: only a reason\n\n## 3\nverdict: unsure');
      expect(a.keys, [3]);
    });

    test('rubbish gives no answers instead of an error', () {
      expect(NameMarkdown.parse('{"verdict": "same"}'), isEmpty);
      expect(NameMarkdown.parse(''), isEmpty);
    });
  });

  group('NameVerifier', () {
    test('plans requests within the limit and skips certain findings', () {
      final certain = NameFinding([const NameVariant('Иван', 3, []), const NameVariant('Ivan', 2, [])], NameFindingKind.script);
      final pairs = [for (var i = 0; i < 6; i++) _pair('Артур$i', 'Артор$i', qa: 'x' * 200)];
      final one = NameMarkdown.request([pairs[0]]).length;
      final plan = NameVerifier.plan([certain, ...pairs], _store(), one * 3);
      expect(plan.pairs, 6);
      expect(plan.requests, 2);
      expect(plan.characters, one * 6);
    });

    test('never asks about more than the cap', () {
      final many = [for (var i = 0; i < 60; i++) _pair('Артур$i', 'Артор$i')];
      expect(NameVerifier.plan(many, _store(), 1 << 30).pairs, NameVerifier.maxPairs);
    });

    test('applies verdicts, only proposes a spelling the book has, and remembers them', () async {
      final f = _pair('Артур', 'Артор');
      final settings = {};
      final store = _store(settings);
      final fake = _Fake(['## 1\nverdict: same\ncanonical: Артур\nreason: typo']);
      await NameVerifier(fake, store).run(NameVerifier.plan([f], store, 1 << 30));
      expect((f.verdict, f.canonical, f.reason), (NameVerdict.same, 'Артур', 'typo'));

      final g = _pair('Артур', 'Артор');
      NameVerifier.apply(g, const NameAnswer(NameVerdict.same, 'Артурий', ''));
      expect(g.canonical, '');

      // the same pair with the same quotes costs nothing the next time
      final again = _pair('Артур', 'Артор');
      final plan = NameVerifier.plan([again], _store(settings), 1 << 30);
      expect(plan.pairs, 0);
      expect(again.verdict, NameVerdict.same);
    });

    test('changed quotes ask again', () async {
      final settings = {};
      final store = _store(settings);
      await store.saveVerdicts({_pair('Артур', 'Артор'): const NameAnswer(NameVerdict.same, '', '')});
      final changed = _pair('Артур', 'Артор', qb: 'другой текст');
      expect(NameVerifier.plan([changed], store, 1 << 30).pairs, 1);
    });

    test('an unsure or missing verdict is kept as unsure and the run goes on', () async {
      final a = _pair('Артур', 'Артор'), b = _pair('Анна', 'Ана');
      final store = _store();
      await NameVerifier(_Fake(['## 2\nverdict: different']), store).run(NameVerifier.plan([a, b], store, 1 << 30));
      expect(a.verdict, isNull);
      expect(b.verdict, NameVerdict.different);
    });
  });

  group('NameCheckStore', () {
    test('dismissed findings stay dismissed, per book', () async {
      final settings = {};
      final store = _store(settings);
      await store.dismiss('book', _pair('Артур', 'Артор'));
      expect(_store(settings).dismissed('book'), [_pair('Артур', 'Артор').key]);
      expect(store.dismissed('other'), isEmpty);
    });
  });
}
