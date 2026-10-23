// Builds a story map from the text of a book with no user input and no network: who appears
// in which section and who shares scenes with whom.
//
// Heuristic: a name is a capitalised word that keeps its capital in the middle of a sentence
// ("Артур", "Arthur"). Russian endings are trimmed so "Артура" and "Артуру" count as "Артур".
// A surname that is almost always preceded by one first name is folded into it ("Артур Рэйм").
// Only people are found; places, events and lore are added by hand. Known limits: a surname
// shared by two first names, titles ("Лорд"), nicknames.
import 'dart:math';

import 'package:quill_fb2/models/story_map.model.dart';

/// The text of one section, as the analyzer needs it.
class StorySection {
  final String id; // the book's sectionId; keeps a saved map attached to the right section
  final String title;
  final List<String> paragraphs; // raw FB2 blocks, tags are stripped here
  const StorySection(this.id, this.title, this.paragraphs);
}

/// [analyze] as a one-argument function, so it can run in an isolate with `compute`.
StoryMap analyzeSections(List<StorySection> sections) => analyze(sections);

class _Tok {
  final String surface, stem;
  final bool cap, sentenceStart, adjacentToPrev;
  const _Tok(this.surface, this.stem, this.cap, this.sentenceStart, this.adjacentToPrev);
}

final _word = RegExp(r'[\p{L}][\p{L}\-]*', unicode: true);
final _tag = RegExp(r'<[^>]+>');
final _ruEnd = RegExp(r'(ами|ями|ов|ев|ей|ом|ем|ой|ам|ям|ах|ях|ы|и|а|я|у|ю|е|о)$');
const _stop = {'the', 'and', 'but', 'mr', 'mrs', 'dr', 'это', 'что', 'как', 'если', 'когда'};

String plain(String block) => block
    .replaceAll(_tag, '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

String _stem(String w) {
  var s = w.toLowerCase();
  if (s.endsWith("'s") || s.endsWith('’s')) s = s.substring(0, s.length - 2);
  if (RegExp(r'[а-яё]').hasMatch(s) && s.length > 4) s = s.replaceFirst(_ruEnd, '');
  return s;
}

List<_Tok> _tokens(String text) {
  final out = <_Tok>[];
  int prevEnd = -10;
  for (final m in _word.allMatches(text)) {
    final w = m.group(0)!;
    // sentence start: only quotes/dashes/spaces before it back to a terminator or the start
    var i = m.start - 1;
    while (i >= 0 && ' \t«»"“„\'—–-(['.contains(text[i])) {
      i--;
    }
    final start = i < 0 || '.!?…:'.contains(text[i]);
    final cap = w[0] != w[0].toLowerCase() && w[0] == w[0].toUpperCase();
    out.add(_Tok(w, _stem(w), cap, start, m.start - prevEnd == 1));
    prevEnd = m.end;
  }
  return out;
}

StoryMap analyze(List<StorySection> sections, {int maxCast = 12}) {
  // 1. one unit per section, empty ones included, so the map lines up with the book
  final units = <({String id, String title, List<String> paras})>[
    for (final s in sections)
      (id: s.id, title: s.title, paras: [for (final p in s.paragraphs) plain(p).trim()].where((p) => p.isNotEmpty).toList())
  ];

  // 2. first pass: which capitalised words behave like names, which pairs are first+surname
  final midCap = <String, int>{}, lower = <String, int>{};
  final surfaces = <String, Map<String, int>>{};
  final adj = <String, Map<String, int>>{}; // adj[y][x]: x directly before y
  final toks = [for (final u in units) [for (final p in u.paras) _tokens(p)]];
  for (final unit in toks) {
    for (final para in unit) {
      for (var i = 0; i < para.length; i++) {
        final t = para[i];
        if (t.stem.length < 3 || _stop.contains(t.stem)) continue;
        if (!t.cap) {
          lower[t.stem] = (lower[t.stem] ?? 0) + 1;
        } else if (!t.sentenceStart) {
          midCap[t.stem] = (midCap[t.stem] ?? 0) + 1;
          final sf = surfaces.putIfAbsent(t.stem, () => {});
          sf[t.surface] = (sf[t.surface] ?? 0) + 1;
          if (i > 0 && t.adjacentToPrev && para[i - 1].cap) {
            final m = adj.putIfAbsent(t.stem, () => {});
            m[para[i - 1].stem] = (m[para[i - 1].stem] ?? 0) + 1;
          }
        }
      }
    }
  }
  final names = {
    for (final e in midCap.entries)
      if (e.value >= 2 && e.value / (e.value + (lower[e.key] ?? 0)) >= 0.7) e.key
  };
  final alias = <String, String>{}; // surname stem -> first name stem
  for (final y in names) {
    final preds = adj[y];
    if (preds == null) continue;
    final best = preds.entries.where((e) => names.contains(e.key) && e.key != y).fold<MapEntry<String, int>?>(
        null, (a, e) => a == null || e.value > a.value ? e : a);
    if (best != null && best.value >= 2 && best.value >= 0.6 * midCap[y]!) alias[y] = best.key;
  }
  String root(String s) {
    for (var i = 0; i < 4 && alias.containsKey(s); i++) {
      s = alias[s]!;
    }
    return s;
  }

  final groups = {for (final n in names) n: root(n)};

  // 3. second pass: mentions per group per unit, paragraph co-occurrence
  final perUnit = <String, List<int>>{};
  final unitSnippet = <String, List<String?>>{};
  final paraGroups = <({int unit, String text, Set<String> g})>[];
  for (var u = 0; u < units.length; u++) {
    for (var p = 0; p < units[u].paras.length; p++) {
      final toksP = toks[u][p];
      final here = <String>{};
      for (var i = 0; i < toksP.length; i++) {
        final t = toksP[i];
        final g = t.cap ? groups[t.stem] : null;
        if (g == null) continue;
        if (i > 0 && t.adjacentToPrev && toksP[i - 1].cap && groups[toksP[i - 1].stem] == g) continue;
        perUnit.putIfAbsent(g, () => List.filled(units.length, 0))[u]++;
        unitSnippet.putIfAbsent(g, () => List.filled(units.length, null))[u] ??= units[u].paras[p];
        here.add(g);
      }
      if (here.isNotEmpty) paraGroups.add((unit: u, text: units[u].paras[p], g: here));
    }
  }

  // 4. acts: cut the book in thirds by length, on unit boundaries
  final nActs = min(3, units.length);
  final lens = [for (final u in units) max(1, u.paras.fold<int>(0, (a, p) => a + p.length))];
  final totalLen = max(1, lens.fold<int>(0, (a, b) => a + b));
  final actOf = <int>[];
  var cum = 0;
  for (final l in lens) {
    actOf.add(min(nActs - 1, ((cum + l / 2) * nActs / totalLen).floor()));
    cum += l;
  }
  final actCounts = List.filled(max(1, nActs), 0);
  for (final a in actOf) {
    actCounts[a]++;
  }
  final acts = [for (var a = 0; a < nActs; a++) ActInfo('Act ${a + 1}', actCounts[a])];

  // 5. cast: top groups by mentions
  final ranked = perUnit.entries.map((e) => (e.key, e.value.fold<int>(0, (a, b) => a + b))).where((e) => e.$2 >= 3).toList()
    ..sort((a, b) => b.$2 - a.$2);
  final top = ranked.take(maxCast).toList();
  final cast = <StoryEntity>[];
  final index = <String, int>{};
  for (var i = 0; i < top.length; i++) {
    final (g, total) = top[i];
    final perAct = List.filled(max(1, nActs), 0);
    final snip = List<String?>.filled(max(1, nActs), null);
    for (var u = 0; u < units.length; u++) {
      perAct[actOf[u]] += perUnit[g]![u];
      snip[actOf[u]] ??= unitSnippet[g]![u];
    }
    String surf(String stem) {
      final m = surfaces[stem]!;
      return m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    final surname = alias.entries
        .where((e) => root(e.key) == g && names.contains(e.key))
        .fold<MapEntry<String, String>?>(null, (a, e) => a == null || midCap[e.key]! > midCap[a.key]! ? e : a);
    final name = surname == null ? surf(g) : '${surf(g)} ${surf(surname.key)}';
    final role = i == 0
        ? Role.protagonist
        : (total >= top[0].$2 * 0.5 ? Role.major : Role.minor);
    cast.add(StoryEntity(name, role, List.of(perUnit[g]!), perAct, snip));
    index[g] = i;
  }

  // 6. ties
  final tieW = <int, int>{};
  final tieAct = <int, List<int>>{};
  final tieSnip = <int, String>{};
  for (final p in paraGroups) {
    final ids = [for (final g in p.g) if (index.containsKey(g)) index[g]!]..sort();
    for (var x = 0; x < ids.length; x++) {
      for (var y = x + 1; y < ids.length; y++) {
        final k = ids[x] * 100 + ids[y];
        tieW[k] = (tieW[k] ?? 0) + 1;
        tieAct.putIfAbsent(k, () => List.filled(max(1, nActs), 0))[actOf[p.unit]]++;
        tieSnip.putIfAbsent(k, () => p.text);
      }
    }
  }
  final ties = [
    for (final e in tieW.entries) Tie(e.key ~/ 100, e.key % 100, e.value, tieAct[e.key]!, tieSnip[e.key])
  ]..sort((a, b) => b.weight - a.weight);

  return StoryMap(acts, cast, ties, [for (final u in units) u.id],
      [for (var i = 0; i < units.length; i++) units[i].title.trim().isEmpty ? 'Section ${i + 1}' : units[i].title.trim()],
      actOf);
}
