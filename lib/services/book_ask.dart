// Read-only questions about the book: a summary of a range of Sections, or an answer to a
// question. When the range fits one request the model reads the text itself; otherwise each
// Section is first boiled down to a Digest (cached, so asking again costs less) and the
// answer is built from the Digests. Nothing here changes the book.
import 'package:quill_fb2/services/llm/improvement.dart' show translationLanguages;
import 'package:quill_fb2/services/llm/llm_client.dart';

enum AskMode { summarise, question }

/// One Section as the model reads it: its place in the book (from 1) and its plain text.
class AskSection {
  final int number;
  final String title;
  final List<String> paragraphs;
  const AskSection(this.number, this.title, this.paragraphs);

  String get text => paragraphs.join('\n\n');
}

/// A Section, or a part of one that is too long for a single request.
class AskPiece {
  final int section;
  final String title;
  final int part, parts;
  final String text;
  const AskPiece(this.section, this.title, this.part, this.parts, this.text);

  String get header => parts > 1 ? '## S$section (part $part of $parts): $title' : '## S$section: $title';
  String get markdown => '$header\n$text';
}

class AskEvidence {
  final int section;
  final String quote;

  /// The quote really stands in that Section of the text that was sent.
  final bool verified;
  const AskEvidence(this.section, this.quote, this.verified);
}

class AskAnswer {
  final String body;
  final List<AskEvidence> evidence;

  /// Built from Digests, so it is less exact than reading the text.
  final bool fromDigests;

  /// The model ran out of room and the answer is cut off.
  final bool truncated;
  const AskAnswer(this.body, this.evidence, {this.fromDigests = false, this.truncated = false});
}

/// What a run will do and cost, worked out before anything is sent.
class AskPlan {
  final AskMode mode;
  final String question;
  final List<AskPiece> pieces;
  final int limit;

  /// True when the whole range goes to the model in one request.
  final bool direct;

  /// Pieces that have no cached Digest yet.
  final List<AskPiece> toDigest;
  final int requests, characters;
  const AskPlan(this.mode, this.question, this.pieces, this.limit, this.direct, this.toDigest, this.requests,
      this.characters);
}

/// English name of a language [code] ("ru", "ru-RU"); an unknown code is returned as written.
String languageName(String code) {
  final c = code.trim().toLowerCase().split(RegExp(r'[-_]')).first;
  for (final l in translationLanguages) {
    if (l.code == c) return l.name;
  }
  return c.isEmpty ? 'English' : c;
}

class BookAsk {
  /// What one Digest is taken to cost when planning, in characters.
  static const digestEstimate = 700;
  static const _digestTokens = 600;
  static const _answerTokens = 2000;

  static const _rules = 'Use only the text you are given. If it does not say, write "Not stated in the text." '
      'Do not guess. Cite the Sections you rely on like [S3] or [S3, S5].';

  static String digestSystem(String language) =>
      'You summarise one part of a fiction book for later use.\n'
      'Write 3 to 5 sentences (under 120 words) in ${languageName(language)}: who is there, what happens, '
      'what changes. Keep names as written. Answer with the summary only.';

  static String mergeSystem(String language) =>
      'You merge numbered summaries of parts of a fiction book into one shorter summary.\n'
      'Write in ${languageName(language)}, keep names as written, keep the order of events, and keep the '
      'Section markers like [S3] where you use a part. Answer with the summary only.';

  static String summariseSystem(String language) =>
      'You summarise a part of a fiction book.\n$_rules\n'
      'Answer in Markdown in ${languageName(language)}: a "## Answer" heading, a short overview paragraph, '
      'then bullet points for the main developments in order.';

  static String questionSystem({required bool withEvidence}) =>
      'You answer questions about a fiction book.\n$_rules\n'
      'Answer in Markdown in the language of the question: a "## Answer" heading and the answer.'
      '${withEvidence ? '\nThen a "## Evidence" heading and one line per quote, written exactly as\n'
          '- S3: "short exact quote from the text"\n'
          'Copy quotes word for word from the text. Never invent one.' : ''}';

  /// Cuts [s] into pieces that each fit [limit] characters, on paragraph breaks where it can.
  static List<AskPiece> pieces(AskSection s, int limit) {
    final chunks = <String>[];
    var current = StringBuffer();
    void flush() {
      if (current.isNotEmpty) chunks.add(current.toString());
      current = StringBuffer();
    }

    for (final p in s.paragraphs) {
      var rest = p;
      while (rest.length > limit) {
        flush();
        var cut = rest.lastIndexOf(' ', limit);
        if (cut < limit ~/ 2) cut = limit;
        chunks.add(rest.substring(0, cut));
        rest = rest.substring(cut).trimLeft();
      }
      if (current.length + rest.length + 2 > limit) flush();
      if (current.isNotEmpty) current.write('\n\n');
      current.write(rest);
    }
    flush();
    return [for (var i = 0; i < chunks.length; i++) AskPiece(s.number, s.title, i + 1, chunks.length, chunks[i])];
  }

  /// Works out the requests and characters for [sections], reading Digests from [digests].
  static AskPlan plan(List<AskSection> sections, AskMode mode, String question, int limit, DigestStore digests,
      String language) {
    final all = [for (final s in sections) ...pieces(s, limit - 200)];
    final total = all.fold<int>(0, (n, p) => n + p.markdown.length + 2);
    if (total + question.length <= limit) {
      return AskPlan(mode, question, all, limit, true, const [], 1, total + question.length);
    }
    final missing = [for (final p in all) if (digests.get(p.text, language) == null) p];
    var chars = missing.fold<int>(0, (n, p) => n + p.markdown.length);
    var requests = missing.length;
    var size = all.length * digestEstimate;
    while (size > limit - 200) {
      final groups = (size / (limit - 200)).ceil();
      final next = groups * digestEstimate;
      if (next >= size) break; // a limit this small cannot shrink them; the run stops merging too
      requests += groups;
      chars += size;
      size = next;
    }
    requests += 1;
    chars += size + question.length;
    return AskPlan(mode, question, all, limit, false, missing, requests, chars);
  }

  // ---- reading the answer ----

  static final _evidenceLine = RegExp(r'^[\s>*\-]*S(\d+)[^:\n]*:\s*["“«]?(.+?)["”»]?\s*$', multiLine: true);
  static final _heading = RegExp(r'^#{1,6}[ \t]*(.*?)[ \t]*$', multiLine: true);

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s"“”«»„]+'), ' ').trim();

  /// Splits [text] into the answer and its evidence, and checks both against what was sent:
  /// a quote must stand in the Section it names, and a citation must point into the range.
  static AskAnswer parse(String text, List<AskSection> sent, {bool fromDigests = false, bool truncated = false}) {
    final cleaned = text.replaceAll(RegExp(r'```\w*'), '').trim();
    final heads = _heading.allMatches(cleaned).toList();
    String body = cleaned;
    String evidenceText = '';
    for (var i = 0; i < heads.length; i++) {
      final name = heads[i].group(1)!.toLowerCase();
      final end = i + 1 < heads.length ? heads[i + 1].start : cleaned.length;
      if (name.startsWith('evidence')) {
        evidenceText = cleaned.substring(heads[i].end, end);
      }
    }
    final answerHead = heads.where((h) => h.group(1)!.toLowerCase().startsWith('answer')).firstOrNull;
    final evidenceHead = heads.where((h) => h.group(1)!.toLowerCase().startsWith('evidence')).firstOrNull;
    if (answerHead != null) {
      final next = heads.where((h) => h.start > answerHead.start).firstOrNull;
      body = cleaned.substring(answerHead.end, next?.start ?? cleaned.length);
    } else if (evidenceHead != null) {
      body = cleaned.substring(0, evidenceHead.start); // an answer written before its evidence
    }
    final byNumber = {for (final s in sent) s.number: _norm(s.text)};
    final evidence = <AskEvidence>[];
    for (final m in _evidenceLine.allMatches(evidenceText)) {
      final n = int.parse(m.group(1)!);
      final quote = m.group(2)!.trim();
      final q = _norm(quote.replaceAll('…', ' '));
      evidence.add(AskEvidence(n, quote, q.isNotEmpty && (byNumber[n]?.contains(q) ?? false)));
    }
    return AskAnswer(_checkCitations(body.trim(), byNumber.keys.toSet()), evidence,
        fromDigests: fromDigests, truncated: truncated);
  }

  /// Drops citations of Sections that were not part of the request.
  static String _checkCitations(String body, Set<int> allowed) {
    return body.replaceAllMapped(RegExp(r'\[(S\d+(?:\s*[,;]\s*S?\d+)*)\]'), (m) {
      final kept = [
        for (final d in RegExp(r'\d+').allMatches(m.group(1)!))
          if (allowed.contains(int.parse(d.group(0)!))) 'S${d.group(0)}'
      ];
      return kept.isEmpty ? '' : '[${kept.join(', ')}]';
    });
  }
}

/// Digests kept in the workspace, so the same text is never boiled down twice.
class DigestStore {
  static const _itemsKey = 'ask-digests';
  static const _orderKey = 'ask-digest-order';
  static const maxDigests = 500;
  final Map Function() _get;
  final Future<void> Function(Map) _set;
  DigestStore({required Map Function() getSettings, required Future<void> Function(Map) setSettings})
      : _get = getSettings,
        _set = setSettings;

  static String keyFor(String text, String language) {
    var h = 0x811c9dc5;
    for (final c in text.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return '$language:${text.length}:${h.toRadixString(16)}';
  }

  String? get(String text, String language) => ((_get()[_itemsKey] as Map?) ?? const {})[keyFor(text, language)] as String?;

  Future<void> put(String text, String language, String digest) async {
    final items = Map.of((_get()[_itemsKey] as Map?) ?? const {});
    final order = [for (final k in (_get()[_orderKey] as List?) ?? const []) '$k'];
    final key = keyFor(text, language);
    order.remove(key);
    order.add(key);
    items[key] = digest;
    while (order.length > maxDigests) {
      items.remove(order.removeAt(0));
    }
    await _set({_itemsKey: items, _orderKey: order});
  }
}

class BookAskRunner {
  final LlmClient client;
  final DigestStore digests;
  final String language;
  BookAskRunner(this.client, this.digests, this.language);

  /// Runs [plan] over [sections]. [onRequest] reports how many requests are done.
  /// A failure leaves the Digests made so far in the cache.
  Future<AskAnswer> run(AskPlan plan, List<AskSection> sections, {void Function(int done)? onRequest}) async {
    var done = 0;
    Future<LlmResponse> ask(LlmRequest r) async {
      final res = await client.complete(r);
      onRequest?.call(++done);
      return res;
    }

    final withEvidence = plan.mode == AskMode.question && plan.direct;
    final system = plan.mode == AskMode.summarise
        ? BookAsk.summariseSystem(language)
        : BookAsk.questionSystem(withEvidence: withEvidence);
    String userFor(String material) => plan.mode == AskMode.summarise
        ? 'Summarise this text.\n\n$material'
        : 'Question: ${plan.question}\n\n$material';

    if (plan.direct) {
      final material = [for (final p in plan.pieces) p.markdown].join('\n\n');
      final res = await ask(LlmRequest(system: system, user: userFor(material), maxOutputTokens: BookAsk._answerTokens));
      return BookAsk.parse(res.text, sections, truncated: res.truncated);
    }

    // Digest every piece (cached ones are free), then merge until the Digests fit one request
    var parts = <String>[];
    for (final p in plan.pieces) {
      var d = digests.get(p.text, language);
      if (d == null) {
        final res = await ask(LlmRequest(
            system: BookAsk.digestSystem(language), user: p.markdown, maxOutputTokens: BookAsk._digestTokens));
        d = res.text.trim();
        if (!res.truncated) await digests.put(p.text, language, d);
      }
      parts.add('## S${p.section}${p.parts > 1 ? ' (part ${p.part} of ${p.parts})' : ''}: ${p.title}\n$d');
    }
    final room = plan.limit - 200;
    while (parts.fold<int>(0, (n, s) => n + s.length + 2) > room && parts.length > 1) {
      final merged = <String>[];
      var group = <String>[];
      var size = 0;
      Future<void> flush() async {
        if (group.isEmpty) return;
        if (group.length == 1) {
          merged.add(group.first);
        } else {
          final res = await ask(LlmRequest(
              system: BookAsk.mergeSystem(language), user: group.join('\n\n'), maxOutputTokens: BookAsk._digestTokens));
          merged.add(res.text.trim());
        }
        group = [];
        size = 0;
      }

      for (final s in parts) {
        if (size + s.length > room && group.isNotEmpty) await flush();
        group.add(s);
        size += s.length + 2;
      }
      await flush();
      if (merged.length >= parts.length) break; // nothing shrank: stop instead of looping
      parts = merged;
    }
    final res = await ask(LlmRequest(
        system: system, user: userFor(parts.join('\n\n')), maxOutputTokens: BookAsk._answerTokens));
    return BookAsk.parse(res.text, sections, fromDigests: true, truncated: res.truncated);
  }
}
