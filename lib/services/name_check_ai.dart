// The optional AI step of the names check. The model gets only the unclear pairs, each with
// a few quotes, as Markdown, and answers in Markdown; nothing is applied to the book.
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/name_check.dart';

/// The model's answer for one pair.
class NameAnswer {
  final NameVerdict verdict;
  final String canonical, reason;
  const NameAnswer(this.verdict, this.canonical, this.reason);
}

/// Converts between pairs of spellings and the Markdown the model reads and writes.
class NameMarkdown {
  static const systemPrompt = 'You help check a fiction book for names written in more than one way.\n'
      'You get numbered pairs of spellings, each with quotes from the book. '
      'For every pair decide whether both spellings name the same person, place or thing.\n'
      'Answer in Markdown, one block per pair and nothing else:\n'
      '## 1\n'
      'verdict: same | different | unsure\n'
      'canonical: the spelling to keep (only when the verdict is same)\n'
      'reason: one short sentence\n'
      'Say unsure when the quotes do not settle it. Never invent quotes.';

  /// The request text for [pairs], numbered from 1.
  static String request(List<NameFinding> pairs) {
    final b = StringBuffer();
    for (var i = 0; i < pairs.length; i++) {
      b.writeln('## ${i + 1}');
      for (final v in pairs[i].variants) {
        b.writeln('- "${v.surface}" (${v.count} times)');
      }
      for (final v in pairs[i].variants) {
        for (final w in v.where.take(2)) {
          b.writeln('> ${v.surface}: "${w.quote.replaceAll('\n', ' ')}"');
        }
      }
      b.writeln();
    }
    return b.toString();
  }

  static final _head = RegExp(r'^#{1,6}[ \t]*(?:pair|candidate)?[ \t]*(\d+)\b.*$', multiLine: true, caseSensitive: false);

  static String _field(String block, String name) {
    final m = RegExp('^[\\s>*\\-]*\\**$name\\**[ \\t]*:[ \\t]*\\**[ \\t]*(.+)\$', multiLine: true, caseSensitive: false)
        .firstMatch(block);
    return m == null ? '' : m.group(1)!.replaceAll(RegExp(r'^[\s"“«*`]+|[\s"”»*`]+$'), '');
  }

  /// The answers by pair number. A block without a clear verdict is left out, which
  /// means "unsure"; text around the blocks is ignored.
  static Map<int, NameAnswer> parse(String answer) {
    final text = answer.replaceAll(RegExp(r'```\w*'), '');
    final heads = _head.allMatches(text).toList();
    final out = <int, NameAnswer>{};
    for (var i = 0; i < heads.length; i++) {
      final end = i + 1 < heads.length ? heads[i + 1].start : text.length;
      final block = text.substring(heads[i].end, end);
      final v = _field(block, 'verdict').toLowerCase();
      final verdict = switch (RegExp(r'^(same|different|unsure)').firstMatch(v)?.group(1)) {
        'same' => NameVerdict.same,
        'different' => NameVerdict.different,
        'unsure' => NameVerdict.unsure,
        _ => null,
      };
      if (verdict == null) continue;
      var reason = _field(block, 'reason');
      if (reason.length > 200) reason = '${reason.substring(0, 200)}…';
      out[int.parse(heads[i].group(1)!)] = NameAnswer(verdict, _field(block, 'canonical'), reason);
    }
    return out;
  }
}

/// Verdicts the user already has, and findings they dismissed, kept in the workspace.
class NameCheckStore {
  static const _verdictsKey = 'namecheck-verdicts';
  static const _dismissedKey = 'namecheck-dismissed';
  final Map Function() _get;
  final Future<void> Function(Map) _set;
  NameCheckStore({required Map Function() getSettings, required Future<void> Function(Map) setSettings})
      : _get = getSettings,
        _set = setSettings;

  Map get _verdicts => Map.of((_get()[_verdictsKey] as Map?) ?? const {});

  /// What the model said about [f] when it saw exactly these quotes, if it did.
  NameAnswer? verdictFor(NameFinding f) {
    final r = _verdicts[cacheKey(f)];
    if (r == null) return null;
    return NameAnswer(NameVerdict.values.byName(r['v']), r['c'] ?? '', r['r'] ?? '');
  }

  Future<void> saveVerdicts(Map<NameFinding, NameAnswer> answers) async {
    if (answers.isEmpty) return;
    final all = _verdicts;
    answers.forEach((f, a) => all[cacheKey(f)] = {'v': a.verdict.name, 'c': a.canonical, 'r': a.reason});
    await _set({_verdictsKey: all});
  }

  /// Names the pair and the exact quotes sent, so a changed text asks again.
  static String cacheKey(NameFinding f) {
    var h = 0x811c9dc5;
    for (final v in f.variants) {
      for (final w in v.where.take(2)) {
        for (final c in w.quote.codeUnits) {
          h = ((h ^ c) * 0x01000193) & 0xffffffff;
        }
      }
    }
    return '${f.key}#${h.toRadixString(16)}';
  }

  List<String> dismissed(String bookId) =>
      [for (final k in (((_get()[_dismissedKey] as Map?) ?? const {})[bookId] as List?) ?? const []) '$k'];

  Future<void> dismiss(String bookId, NameFinding f) async {
    final all = Map.of((_get()[_dismissedKey] as Map?) ?? const {});
    all[bookId] = [...dismissed(bookId), f.key];
    await _set({_dismissedKey: all});
  }
}

/// What a run of the AI step would cost, before anything is sent.
class NameVerifyPlan {
  final List<List<NameFinding>> batches;
  final int characters;
  const NameVerifyPlan(this.batches, this.characters);
  int get requests => batches.length;
  int get pairs => batches.fold(0, (n, b) => n + b.length);
}

class NameVerifier {
  /// Most pairs one run asks about.
  static const maxPairs = 40;

  final LlmClient client;
  final NameCheckStore store;
  NameVerifier(this.client, this.store);

  /// Applies verdicts the store already has and plans requests for the rest, each
  /// within [limit] characters.
  static NameVerifyPlan plan(List<NameFinding> findings, NameCheckStore store, int limit) {
    final pending = <NameFinding>[];
    for (final f in findings) {
      if (f.certain || f.verdict != null) continue;
      final known = store.verdictFor(f);
      if (known != null) {
        apply(f, known);
      } else if (pending.length < maxPairs) {
        pending.add(f);
      }
    }
    final batches = <List<NameFinding>>[];
    var current = <NameFinding>[];
    var size = 0, total = 0;
    for (final f in pending) {
      final n = NameMarkdown.request([f]).length;
      if (size + n > limit && current.isNotEmpty) {
        batches.add(current);
        current = [];
        size = 0;
      }
      current.add(f);
      size += n;
      total += n;
    }
    if (current.isNotEmpty) batches.add(current);
    return NameVerifyPlan(batches, total);
  }

  static void apply(NameFinding f, NameAnswer a) {
    f.verdict = a.verdict;
    f.reason = a.reason;
    // only a spelling the book really has can be proposed as the one to keep
    final c = a.canonical.toLowerCase();
    f.canonical = f.variants.any((v) => v.surface.toLowerCase() == c)
        ? f.variants.firstWhere((v) => v.surface.toLowerCase() == c).surface
        : '';
  }

  /// Sends the planned batches in turn. [onBatch] reports how many are done. Stops at the
  /// first failure, keeping what was learned.
  Future<void> run(NameVerifyPlan plan, {void Function(int done)? onBatch}) async {
    var done = 0;
    for (final batch in plan.batches) {
      final response = await client.complete(LlmRequest(
          system: NameMarkdown.systemPrompt,
          user: NameMarkdown.request(batch),
          maxOutputTokens: 200 + 150 * batch.length));
      final answers = NameMarkdown.parse(response.text);
      final learned = <NameFinding, NameAnswer>{};
      for (var i = 0; i < batch.length; i++) {
        final a = answers[i + 1];
        if (a == null) continue;
        apply(batch[i], a);
        learned[batch[i]] = a;
      }
      await store.saveVerdicts(learned);
      onBatch?.call(++done);
    }
  }
}
