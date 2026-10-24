// The optional AI pass of the story map (ADR 0003). The model reads the Sections as Markdown and
// proposes places, events and lore the map lacks, and labels for Ties; it answers in Markdown.
// Every proposal is checked against the book text here, and nothing reaches the map until the
// user accepts it.
import 'dart:math';

import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/book_ask.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';

/// A place, event or piece of lore the map does not have yet. [perUnit] is counted from the text.
class EntityProposal {
  final String name, note;
  final EntityKind kind;
  final List<int> perUnit;
  const EntityProposal(this.name, this.kind, this.note, this.perUnit);
  int get mentions => perUnit.fold(0, (a, b) => a + b);

  EntityProposal edited({String? name, EntityKind? kind, String? note}) =>
      EntityProposal(name ?? this.name, kind ?? this.kind, note ?? this.note, perUnit);
}

/// A label for the Tie between two entities, named as the map (or an [EntityProposal]) names them.
class TieProposal {
  final String a, b, label;

  /// The map already has a Tie between them (drawn or counted); accepting only labels it.
  final bool exists;
  const TieProposal(this.a, this.b, this.label, {required this.exists});

  TieProposal edited({String? a, String? b, String? label}) =>
      TieProposal(a ?? this.a, b ?? this.b, label ?? this.label, exists: exists);
}

class StoryMapSuggestions {
  final List<EntityProposal> entities;
  final List<TieProposal> ties;
  const StoryMapSuggestions(this.entities, this.ties);
  bool get isEmpty => entities.isEmpty && ties.isEmpty;
}

/// What a run will cost, worked out before anything is sent.
class StoryMapAiPlan {
  final List<String> batches;
  final int characters;
  const StoryMapAiPlan(this.batches, this.characters);
  int get requests => batches.length;
}

class StoryMapAi {
  /// Most unlabeled Ties offered for a label in one request, strongest first.
  static const maxTies = 30;

  /// Most new entities kept from one run.
  static const maxEntities = 60;
  static const _overhead = 1800;

  static String systemPrompt(String language) =>
      'You help build a story map of a fiction book. You get Sections of the book as Markdown '
      '("## S3: title"), the people and things already on the map, and Ties that have no label yet.\n'
      'Propose:\n'
      '1. Places, events and pieces of lore that matter to the story and are not on the map yet.\n'
      '2. A short label for how two entities are tied, where the text shows it.\n'
      'Answer in Markdown, one block per item and nothing else:\n'
      '## entity\n'
      'name: the name as it is written in the text\n'
      'kind: place | event | lore\n'
      'note: one short sentence in ${languageName(language)}\n'
      '## tie\n'
      'a: a name from the map or from your entities\n'
      'b: another name\n'
      'label: two or three words in ${languageName(language)}, like "brother of" or "lives in"\n'
      'Use only what the text says. Do not repeat what is already on the map. Do not add people. '
      'Skip anything you are not sure of. Never invent a name.';

  /// The part of every request that describes the map.
  static String context(StoryMap m) {
    final b = StringBuffer('Already on the map:\n');
    for (final e in m.cast.take(80)) {
      b.writeln('- ${e.name} (${e.kind.name})');
    }
    final open = [for (final t in m.ties) if (t.label.isEmpty) t]..sort((x, y) => y.weight - x.weight);
    if (open.isNotEmpty) {
      b.writeln('\nTies without a label:');
      for (final t in open.take(maxTies)) {
        b.writeln('- ${m.cast[t.a].name} — ${m.cast[t.b].name}');
      }
    }
    return b.toString();
  }

  /// Groups [sections] into requests of at most [limit] characters, each starting with the map.
  static StoryMapAiPlan plan(StoryMap m, List<AskSection> sections, int limit) {
    final head = context(m);
    final room = max(1000, limit - _overhead - head.length);
    final batches = <String>[];
    var current = StringBuffer();
    var size = 0, total = 0;
    void flush() {
      if (size == 0) return;
      final text = '$head\n${current.toString()}';
      batches.add(text);
      total += text.length;
      current = StringBuffer();
      size = 0;
    }

    for (final s in sections) {
      if (s.paragraphs.isEmpty) continue;
      for (final p in BookAsk.pieces(s, room)) {
        final n = p.markdown.length + 2;
        if (size + n > room) flush();
        current.write('${p.markdown}\n\n');
        size += n;
      }
    }
    flush();
    return StoryMapAiPlan(batches, total);
  }

  // ---- reading the answer ----

  static final _head = RegExp(r'^#{1,6}[ \t]*(entity|tie)\b.*$', multiLine: true, caseSensitive: false);

  static String _field(String block, String name) {
    final m = RegExp('^[\\s>*\\-]*\\**$name\\**[ \\t]*:[ \\t]*\\**[ \\t]*(.+)\$', multiLine: true, caseSensitive: false)
        .firstMatch(block);
    return m == null ? '' : m.group(1)!.replaceAll(RegExp(r'^[\s"“«*`]+|[\s"”»*`]+$'), '');
  }

  /// A pattern for [name] that survives Russian endings: each word loses its last letters.
  static RegExp _pattern(String name) {
    String stem(String w) => w.length >= 6 ? w.substring(0, w.length - 2) : (w.length >= 5 ? w.substring(0, w.length - 1) : w);
    final words = name.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => RegExp.escape(stem(w)));
    return RegExp(words.join(r'\p{L}*\s+'), unicode: true);
  }

  /// The proposals in [answer] that the book and the map stand behind. [sections] is the whole
  /// text of the book, in the order of the map's units.
  static StoryMapSuggestions parse(String answer, StoryMap m, List<AskSection> sections) {
    final text = answer.replaceAll(RegExp(r'```\w*'), '');
    final heads = _head.allMatches(text).toList();
    final onMap = {for (final e in m.cast) e.name.toLowerCase()};
    final lowered = [for (final s in sections) s.text.toLowerCase()];
    final entities = <String, EntityProposal>{};
    final rawTies = <(String, String, String)>[];
    for (var i = 0; i < heads.length; i++) {
      final end = i + 1 < heads.length ? heads[i + 1].start : text.length;
      final block = text.substring(heads[i].end, end);
      if (heads[i].group(1)!.toLowerCase() == 'entity') {
        final name = _field(block, 'name');
        final kind = switch (RegExp(r'^(place|event|lore)', caseSensitive: false).firstMatch(_field(block, 'kind'))?.group(1)?.toLowerCase()) {
          'place' => EntityKind.place,
          'event' => EntityKind.event,
          'lore' => EntityKind.lore,
          _ => null,
        };
        final key = name.toLowerCase();
        if (kind == null || name.length < 2 || name.length > 60 || onMap.contains(key) || entities.containsKey(key)) continue;
        final pattern = _pattern(name);
        final perUnit = [for (final t in lowered) pattern.allMatches(t).length];
        if (perUnit.every((n) => n == 0)) continue; // the book never says it
        var note = _field(block, 'note');
        if (note.length > 160) note = '${note.substring(0, 160)}…';
        if (entities.length < maxEntities) entities[key] = EntityProposal(name, kind, note, perUnit);
      } else {
        final label = _field(block, 'label');
        if (label.isNotEmpty && label.length <= 40) rawTies.add((_field(block, 'a'), _field(block, 'b'), label));
      }
    }
    final known = {...onMap, ...entities.keys};
    final seen = <String>{};
    final ties = <TieProposal>[];
    for (final (a, b, label) in rawTies) {
      final x = a.toLowerCase(), y = b.toLowerCase();
      if (x == y || !known.contains(x) || !known.contains(y)) continue;
      final ia = m.cast.indexWhere((e) => e.name.toLowerCase() == x);
      final ib = m.cast.indexWhere((e) => e.name.toLowerCase() == y);
      final tie = ia >= 0 && ib >= 0 ? m.tieBetween(ia, ib) : null;
      if (tie != null && tie.label.isNotEmpty) continue; // the user's own label stays
      if (!seen.add(([x, y]..sort()).join('|'))) continue;
      ties.add(TieProposal(ia >= 0 ? m.cast[ia].name : entities[x]!.name,
          ib >= 0 ? m.cast[ib].name : entities[y]!.name, label,
          exists: tie != null));
    }
    return StoryMapSuggestions(entities.values.toList(), ties);
  }

  // ---- applying one proposal ----

  /// Adds the entity with the mentions counted from the text. Returns its index.
  static int accept(StoryMap m, EntityProposal p) {
    final c = m.addEntity(p.name, p.kind, Role.minor, p.note);
    for (var u = 0; u < min(m.unitCount, p.perUnit.length); u++) {
      m.cast[c].perUnit[u] = p.perUnit[u];
    }
    m.recompute();
    return c;
  }

  /// Labels (or draws) the Tie. False while one of its two entities is not on the map yet.
  static bool acceptTie(StoryMap m, TieProposal t) {
    final a = m.cast.indexWhere((e) => e.name.toLowerCase() == t.a.toLowerCase());
    final b = m.cast.indexWhere((e) => e.name.toLowerCase() == t.b.toLowerCase());
    if (a < 0 || b < 0) return false;
    m.setTie(a, b, t.label);
    return true;
  }
}

/// Sends the planned requests in turn and collects what the model proposes.
class StoryMapAiRunner {
  final LlmClient client;
  final String language;
  StoryMapAiRunner(this.client, this.language);

  /// Stops at the first failure with an [LlmException]; [onRequest] reports how many are done.
  Future<StoryMapSuggestions> run(StoryMapAiPlan plan, StoryMap m, List<AskSection> sections,
      {void Function(int done)? onRequest}) async {
    final entities = <String, EntityProposal>{};
    final labels = <String, TieProposal>{};
    var done = 0;
    for (final user in plan.batches) {
      final response = await client
          .complete(LlmRequest(system: StoryMapAi.systemPrompt(language), user: user, maxOutputTokens: 4000));
      final got = StoryMapAi.parse(response.text, m, sections);
      for (final e in got.entities) {
        entities.putIfAbsent(e.name.toLowerCase(), () => e);
      }
      for (final t in got.ties) {
        labels.putIfAbsent(([t.a.toLowerCase(), t.b.toLowerCase()]..sort()).join('|'), () => t);
      }
      onRequest?.call(++done);
    }
    // a Tie proposed in one request may name an entity found in another; keep only resolvable ones
    final names = {for (final e in m.cast) e.name.toLowerCase(), ...entities.keys};
    return StoryMapSuggestions(entities.values.toList(), [
      for (final t in labels.values)
        if (names.contains(t.a.toLowerCase()) && names.contains(t.b.toLowerCase())) t
    ]);
  }
}
