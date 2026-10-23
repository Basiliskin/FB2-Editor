import 'dart:convert';
import 'dart:math';

/// How important a person is to the story. Only meaningful for [EntityKind.person].
enum Role { protagonist, major, minor }

/// What an entity is. Only people are found automatically; places, events and lore are
/// added by hand. Every kind shares presence-per-section, notes and ties.
enum EntityKind { person, place, event, lore }

/// One person, place, event or piece of lore on the story map.
class StoryEntity {
  String name;
  EntityKind kind;
  Role role;
  String note;

  /// Mentions per section; a mark made by hand counts as 1.
  List<int> perUnit;

  /// Derived from [perUnit] by [StoryMap.recompute].
  List<int> perAct;

  /// The first paragraph naming it, per act (automatic entities only).
  final List<String?> snippet;

  StoryEntity(this.name, this.role, this.perUnit, this.perAct, this.snippet,
      {this.kind = EntityKind.person, this.note = ''});

  int get total => perUnit.fold(0, (a, b) => a + b);
  String get short => name.split(' ').first;
}

/// A link between two entities: counted from shared paragraphs, or drawn by hand.
class Tie {
  final int a, b; // indexes into StoryMap.cast
  int weight; // paragraphs where both appear (1 for a tie drawn by hand)
  List<int> perAct;
  final String? snippet;
  String label; // "brother of", "happens at" ...
  final bool manual;
  Tie(this.a, this.b, this.weight, this.perAct, this.snippet, {this.label = '', this.manual = false});
}

class ActInfo {
  final String label;
  final int sections;
  const ActInfo(this.label, this.sections);
}

/// What [StoryMap.removeEntity] took away, so the removal can be undone.
class RemovedEntity {
  final int index;
  final StoryEntity entity;

  /// The ties it had, each with its place in [StoryMap.ties].
  final List<(int, Tie)> ties;
  const RemovedEntity(this.index, this.entity, this.ties);
}

/// Who and what appears in which section of a book, and how they are tied together.
/// Built by the analyzer, then managed by hand; saved inside the FB2 (see [encode]).
class StoryMap {
  List<ActInfo> acts;
  final List<StoryEntity> cast;
  List<Tie> ties;
  List<({int who, int act, String text})> flags = [];

  /// The book's sectionId for every unit (one unit per section), so a saved map stays
  /// attached to the right section when sections are added, removed or reordered.
  List<String> unitIds;
  List<String> unitTitles;

  /// Act index of every unit, non-decreasing.
  List<int> unitAct;
  int get unitCount => unitIds.length;

  StoryMap(this.acts, this.cast, this.ties, this.unitIds, this.unitTitles, this.unitAct) {
    recompute();
  }

  // ---- entities ----

  int addEntity(String name, EntityKind kind, Role role, String note) {
    cast.add(StoryEntity(name, role, List.filled(unitCount, 0, growable: true), List.filled(max(1, acts.length), 0),
        List.filled(max(1, acts.length), null),
        kind: kind, note: note));
    recompute();
    return cast.length - 1;
  }

  void updateEntity(int c, {String? name, EntityKind? kind, Role? role, String? note}) {
    final e = cast[c];
    if (name != null) e.name = name;
    if (kind != null) e.kind = kind;
    if (role != null) e.role = role;
    if (note != null) e.note = note;
    recompute();
  }

  RemovedEntity removeEntity(int c) {
    final entity = cast.removeAt(c);
    final gone = [for (var i = 0; i < ties.length; i++) if (ties[i].a == c || ties[i].b == c) (i, ties[i])];
    ties = [
      for (final t in ties)
        if (t.a != c && t.b != c)
          Tie(t.a > c ? t.a - 1 : t.a, t.b > c ? t.b - 1 : t.b, t.weight, t.perAct, t.snippet,
              label: t.label, manual: t.manual)
    ];
    recompute();
    return RemovedEntity(c, entity, gone);
  }

  /// Puts back what [removeEntity] took, at the same place with the same ties.
  void restoreEntity(RemovedEntity r) {
    ties = [
      for (final t in ties)
        Tie(t.a >= r.index ? t.a + 1 : t.a, t.b >= r.index ? t.b + 1 : t.b, t.weight, t.perAct, t.snippet,
            label: t.label, manual: t.manual),
    ];
    for (final (at, tie) in r.ties) {
      ties.insert(at, tie); // ascending, so each lands where it was
    }
    cast.insert(r.index, r.entity);
    recompute();
  }

  /// Marks an entity as present (1 mention) or absent in one section.
  void togglePresence(int c, int unit) {
    cast[c].perUnit[unit] = cast[c].perUnit[unit] > 0 ? 0 : 1;
    recompute();
  }

  // ---- ties ----

  Tie? tieBetween(int a, int b) {
    for (final t in ties) {
      if ((t.a == a && t.b == b) || (t.a == b && t.b == a)) return t;
    }
    return null;
  }

  /// Adds a tie between two entities, or relabels the one that exists.
  void setTie(int a, int b, String label) {
    final t = tieBetween(a, b);
    if (t != null) {
      t.label = label;
    } else {
      ties.add(Tie(min(a, b), max(a, b), 1, List.filled(max(1, acts.length), 0), null, label: label, manual: true));
    }
    recompute();
  }

  void removeTie(Tie t) {
    ties.remove(t);
    recompute();
  }

  List<Tie> tiesOf(int c) =>
      ties.where((t) => t.a == c || t.b == c).toList()..sort((x, y) => y.weight - x.weight);
  int other(Tie t, int c) => t.a == c ? t.b : t.a;

  // ---- derived data ----

  /// Re-derives per-act counts, hand-drawn ties' activity and the "worth a look" flags.
  void recompute() {
    for (final c in cast) {
      c.perAct = List.filled(max(1, acts.length), 0);
      for (var u = 0; u < unitCount; u++) {
        c.perAct[unitAct[u]] += c.perUnit[u];
      }
    }
    for (final t in ties) {
      if (!t.manual) continue;
      t.perAct = [
        for (var a = 0; a < max(1, acts.length); a++) cast[t.a].perAct[a] > 0 && cast[t.b].perAct[a] > 0 ? 1 : 0
      ];
      t.weight = max(1, t.perAct.fold<int>(0, (x, y) => x + y));
    }
    flags = [];
    final people = [for (var c = 0; c < cast.length; c++) if (cast[c].kind == EntityKind.person) c];
    if (people.isEmpty) return;
    final top = people.map((c) => cast[c].total).fold<int>(1, max);
    for (final c in people.take(8)) {
      if (flags.length >= 4) break;
      final ch = cast[c];
      if (ch.total < top * 0.2) continue;
      final present = [for (var a = 0; a < acts.length; a++) if (ch.perAct[a] > 0) a];
      if (present.isEmpty) continue;
      for (var a = 0; a < acts.length; a++) {
        if (ch.perAct[a] == 0 && (a > present.first || present.length == 1 || a < present.last)) {
          flags.add((who: c, act: a, text: '${ch.name}: not mentioned in Act ${a + 1}'));
          break;
        }
      }
    }
  }

  /// Re-aligns to the book's current sections (added, removed or reordered since the map
  /// was made). New sections start empty and join the act of the section before them.
  void realign(List<String> ids, List<String> titles) {
    if (_same(ids, unitIds)) {
      unitTitles = titles;
      return;
    }
    final old = {for (var i = 0; i < unitIds.length; i++) unitIds[i]: i};
    final act = <int>[];
    var last = 0;
    for (final id in ids) {
      final o = old[id];
      if (o != null) last = unitAct[o];
      act.add(last);
    }
    for (final c in cast) {
      final u = [for (final id in ids) old[id] == null ? 0 : c.perUnit[old[id]!]];
      c.perUnit = u;
    }
    acts = [for (var a = 0; a < acts.length; a++) ActInfo(acts[a].label, act.where((x) => x == a).length)];
    if (acts.isEmpty) acts = [ActInfo('Act 1', ids.length)];
    unitIds = ids;
    unitTitles = titles;
    unitAct = act;
    recompute();
  }

  static bool _same(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- saved form: a JSON string kept inside the book ----

  String encode() => jsonEncode({
        'v': 1,
        'units': unitIds,
        'act': unitAct,
        'acts': [for (final a in acts) a.label],
        'cast': [
          for (final c in cast)
            {
              'n': c.name,
              'k': c.kind.name,
              'r': c.role.name,
              if (c.note.isNotEmpty) 'note': c.note,
              'u': c.perUnit,
              's': [for (final s in c.snippet) s == null ? null : _cut(s)],
            }
        ],
        'ties': [
          for (final t in ties)
            {
              'a': t.a,
              'b': t.b,
              'w': t.weight,
              'pa': t.perAct,
              if (t.label.isNotEmpty) 'l': t.label,
              if (t.manual) 'm': 1,
              if (t.snippet != null) 's': _cut(t.snippet!),
            }
        ],
      });

  static String _cut(String s) => s.length > 200 ? s.substring(0, 200) : s;

  /// Null when [text] is not a map this version understands.
  static StoryMap? decode(String text, List<String> ids, List<String> titles) {
    try {
      final j = jsonDecode(text) as Map;
      if (j['v'] != 1) return null;
      final acts = [for (final l in j['acts'] as List) ActInfo(l as String, 0)];
      final cast = [
        for (final c in j['cast'] as List)
          StoryEntity(
              c['n'] as String,
              Role.values.byName(c['r'] as String),
              [for (final x in c['u'] as List) x as int],
              List.filled(max(1, acts.length), 0),
              [for (final s in c['s'] as List) s as String?],
              kind: EntityKind.values.byName(c['k'] as String),
              note: (c['note'] as String?) ?? '')
      ];
      final ties = [
        for (final t in j['ties'] as List)
          Tie(t['a'] as int, t['b'] as int, t['w'] as int, [for (final x in t['pa'] as List) x as int], t['s'] as String?,
              label: (t['l'] as String?) ?? '', manual: t['m'] == 1)
      ];
      final saved = [for (final x in j['units'] as List) x as String];
      final m = StoryMap(acts, cast, ties, saved, saved, [for (final x in j['act'] as List) x as int]);
      m.realign(ids, titles);
      return m;
    } catch (e) {
      return null;
    }
  }
}
