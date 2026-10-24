// Finds names that the book writes in more than one way ("Ivan" and "Иван", "Фёдор" and
// "Федор", "Артур" and "Артор"), with no network. Every location is cut from the text, so a
// quote it reports is always really there.
//
// Certain: the two spellings reduce to the same name once ё/е, hyphens and the script are
// ignored. Possible: they differ by a letter or two and one is much rarer than the other,
// which may be a typo or may be two people; the AI step or the user decides.
import 'dart:math';

import 'package:quill_fb2/services/story_map_analyzer.dart';

enum NameFindingKind { script, spelling, similar }

enum NameVerdict { same, different, unsure }

/// Where a name stands: the section, the paragraph (from 0) and a quote around it.
class NameLocation {
  final int unit;
  final int paragraph;
  final String quote;
  const NameLocation(this.unit, this.paragraph, this.quote);
}

class NameVariant {
  final String surface;
  final int count;

  /// The first few places it appears.
  final List<NameLocation> where;
  const NameVariant(this.surface, this.count, this.where);
}

class NameFinding {
  final List<NameVariant> variants; // most used first
  final NameFindingKind kind;

  /// Set by the AI step.
  NameVerdict? verdict;
  String canonical = '';
  String reason = '';
  NameFinding(this.variants, this.kind);

  /// The spellings reduce to one name; nothing to guess.
  bool get certain => kind != NameFindingKind.similar;

  int get total => variants.fold(0, (n, v) => n + v.count);

  /// Identifies the same set of spellings between runs.
  String get key => ([for (final v in variants) v.surface.toLowerCase()]..sort()).join('|');
}

const _cyr = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh', 'з': 'z',
  'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r',
  'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh',
  'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
};

String _fold(String stem) => stem.replaceAll('ё', 'е').replaceAll(RegExp(r"[-'’]"), '');

bool _isCyrillic(String s) => RegExp(r'[а-яё]').hasMatch(s);

/// One rough Latin spelling for a Russian or English name, for comparing across scripts.
String transliterate(String name) {
  var s = _fold(name.toLowerCase());
  s = [for (final c in s.split('')) _cyr[c] ?? c].join();
  s = s
      .replaceAll('ph', 'f')
      .replaceAll('ck', 'k')
      .replaceAll('x', 'ks')
      .replaceAll('j', 'y')
      .replaceAll('w', 'v')
      .replaceAll('q', 'k')
      .replaceAllMapped(RegExp(r'c(?!h)'), (_) => 'k')
      .replaceAll(RegExp(r'(ey|ei)$'), 'ey')
      .replaceAll(RegExp(r'(iy|ii|yi)$'), 'i');
  return s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
}

/// Edit distance, or [limit] + 1 as soon as it is known to be larger.
int _distance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var prev = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List.filled(b.length + 1, 0)..[0] = i;
    var best = cur[0];
    for (var j = 1; j <= b.length; j++) {
      cur[j] = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
      best = min(best, cur[j]);
    }
    if (best > limit) return limit + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// A stretch of [text] around [at], cut at spaces and marked with … where it was shortened.
String quoteAround(String text, int at, int length, {int span = 70}) {
  var from = max(0, at - span), to = min(text.length, at + length + span);
  if (from > 0) {
    final sp = text.indexOf(' ', from);
    if (sp >= 0 && sp < at) from = sp + 1;
  }
  if (to < text.length) {
    final sp = text.lastIndexOf(' ', to);
    if (sp > at + length) to = sp;
  }
  return '${from > 0 ? '…' : ''}${text.substring(from, to)}${to < text.length ? '…' : ''}';
}

/// Whether [quote] (with its … marks) really stands in the paragraph it points to.
bool quoteInText(String quote, List<StorySection> sections, NameLocation at) {
  if (at.unit >= sections.length || at.paragraph >= sections[at.unit].paragraphs.length) return false;
  final text = plain(sections[at.unit].paragraphs[at.paragraph]).trim();
  return text.contains(quote.replaceAll('…', ''));
}

class _Name {
  final String stem, surface;
  final int count;
  final List<NameLocation> where;
  final String key; // transliterated
  final bool cyrillic;
  _Name(this.stem, this.surface, this.count, this.where)
      : key = transliterate(stem),
        cyrillic = _isCyrillic(stem);
}

/// [checkNames] as a one-argument function, so it can run in an isolate with `compute`.
List<NameFinding> checkNamesIn(List<StorySection> sections) => checkNames(sections);

List<NameFinding> checkNames(List<StorySection> sections, {int maxFindings = 200, int shown = 5}) {
  final mid = <String, int>{}, lower = <String, int>{}, all = <String, int>{};
  final surfaces = <String, Map<String, int>>{};
  final where = <String, List<NameLocation>>{};
  for (var u = 0; u < sections.length; u++) {
    final paras = sections[u].paragraphs;
    for (var p = 0; p < paras.length; p++) {
      final text = plain(paras[p]).trim();
      if (text.isEmpty) continue;
      for (final t in nameTokens(text)) {
        if (t.stem.length < 4 || nameStopWords.contains(t.stem)) continue;
        if (!t.cap) {
          lower[t.stem] = (lower[t.stem] ?? 0) + 1;
          continue;
        }
        all[t.stem] = (all[t.stem] ?? 0) + 1;
        if (!t.sentenceStart) mid[t.stem] = (mid[t.stem] ?? 0) + 1;
        final sf = surfaces.putIfAbsent(t.stem, () => {});
        sf[t.surface] = (sf[t.surface] ?? 0) + 1;
        final list = where.putIfAbsent(t.stem, () => []);
        if (list.length < shown) list.add(NameLocation(u, p, quoteAround(text, t.start, t.surface.length)));
      }
    }
  }
  final names = <_Name>[
    for (final e in mid.entries)
      if (e.value / (e.value + (lower[e.key] ?? 0)) >= 0.7)
        _Name(e.key, surfaces[e.key]!.entries.reduce((a, b) => a.value >= b.value ? a : b).key, all[e.key]!, where[e.key]!)
  ];

  // certain: group the names that reduce to one spelling
  final parent = List.generate(names.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  final kindOf = <int, NameFindingKind>{}; // by group root
  void join(int a, int b, NameFindingKind k) {
    final ra = find(a), rb = find(b);
    final merged = {kindOf[ra], kindOf[rb], k}.contains(NameFindingKind.script)
        ? NameFindingKind.script
        : NameFindingKind.spelling;
    if (ra != rb) parent[rb] = ra;
    kindOf[find(a)] = merged;
  }

  final byKey = <String, List<int>>{};
  for (var i = 0; i < names.length; i++) {
    byKey.putIfAbsent(names[i].key, () => []).add(i);
  }
  for (final group in byKey.values) {
    for (var x = 1; x < group.length; x++) {
      final a = names[group[0]], b = names[group[x]];
      join(group[0], group[x], a.cyrillic != b.cyrillic ? NameFindingKind.script : NameFindingKind.spelling);
    }
  }
  final groups = <int, List<int>>{};
  for (var i = 0; i < names.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(i);
  }
  NameVariant variant(_Name n) => NameVariant(n.surface, n.count, n.where);
  final out = <NameFinding>[];
  for (final e in groups.entries) {
    if (e.value.length < 2) continue;
    final members = [for (final i in e.value) names[i]]..sort((a, b) => b.count - a.count);
    if (members.fold<int>(0, (n, m) => n + m.count) < 3) continue;
    out.add(NameFinding([for (final m in members) variant(m)], kindOf[e.key]!));
  }

  // possible: one letter or two apart, and one much rarer than the other
  final seen = <String>{};
  final reps = [for (final g in groups.values) names[g.reduce((a, b) => names[a].count >= names[b].count ? a : b)]];
  for (var i = 0; i < reps.length; i++) {
    for (var j = i + 1; j < reps.length; j++) {
      final a = reps[i], b = reps[j];
      final shortest = min(a.key.length, b.key.length);
      if (shortest < 5) continue;
      final limit = shortest >= 8 ? 2 : 1;
      if (_distance(a.key, b.key, limit) > limit) continue;
      final hi = max(a.count, b.count), lo = min(a.count, b.count);
      if (lo > 3 && lo > hi * 0.2) continue; // two well-used names: most likely two people
      if (hi + lo < 3) continue;
      final f = NameFinding(
          [for (final n in (a.count >= b.count ? [a, b] : [b, a])) variant(n)], NameFindingKind.similar);
      if (seen.add(f.key)) out.add(f);
    }
  }
  out.sort((a, b) {
    if (a.certain != b.certain) return a.certain ? -1 : 1;
    return b.total - a.total;
  });
  return out.take(maxFindings).toList();
}
