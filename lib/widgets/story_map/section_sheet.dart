import 'package:flutter/material.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/story_map/entity_editor.dart';
import 'package:quill_fb2/widgets/story_map/entity_sheet.dart';
import 'package:quill_fb2/widgets/story_map/story_ui.dart';

/// Entry point from the section editor: who and what is in this section, editable.
/// Edits go straight into the book's story map.
Future<void> openSectionStory(BuildContext context, AppService s, ProjectModel book, Section section) async {
  final m = await book.loadStoryMap();
  if (!context.mounted) return;
  final unit = m.unitIds.indexOf(section.sectionId);
  if (unit < 0) return;
  await showSectionSheet(context, s, m, unit, () => book.saveStoryMap(m));
}

/// A small "who is here" line for a section card; empty until the story map has been opened.
class SectionCastLine extends StatelessWidget {
  final ProjectModel book;
  final Section section;
  const SectionCastLine(this.book, this.section, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = book.loadedStoryMap;
    final u = m?.unitIds.indexOf(section.sectionId) ?? -1;
    if (m == null || u < 0) return const SizedBox.shrink();
    final here = [for (final c in m.cast) if (c.perUnit[u] > 0) c];
    if (here.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 8, children: [
        for (final c in here.take(4))
          Row(mainAxisSize: MainAxisSize.min, children: [
            StoryMark(c, 9),
            const SizedBox(width: 3),
            Text(c.short, style: const TextStyle(fontSize: 11)),
          ]),
        if (here.length > 4) Text('+${here.length - 4}', style: const TextStyle(fontSize: 11)),
      ]),
    );
  }
}

/// Everything the map knows about one section; also where appearances are marked.
/// Used from the timeline and from the section editor. Kind filter and search work on
/// both lists, so a big cast stays manageable.
Future<void> showSectionSheet(BuildContext context, AppService s, StoryMap m, int unit, VoidCallback changed) {
  final kinds = <EntityKind>{};
  var query = '';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        bool shown(int i) =>
            (kinds.isEmpty || kinds.contains(m.cast[i].kind)) &&
            (query.isEmpty || m.cast[i].name.toLowerCase().contains(query));
        final here = [for (var i = 0; i < m.cast.length; i++) if (m.cast[i].perUnit[unit] > 0 && shown(i)) i];
        final away = [for (var i = 0; i < m.cast.length; i++) if (m.cast[i].perUnit[unit] == 0 && shown(i)) i];
        final present = [for (var i = 0; i < m.cast.length; i++) if (m.cast[i].perUnit[unit] > 0) i];
        final ties = [for (final t in m.ties) if (present.contains(t.a) && present.contains(t.b) && (t.label.isNotEmpty || t.weight > 0)) t]
          ..sort((x, y) => y.weight - x.weight);
        void toggle(int i) {
          m.togglePresence(i, unit);
          changed();
          set(() {});
        }

        Widget label(String text) => Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(text, style: const TextStyle(fontSize: 11, letterSpacing: 1)));

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${unit + 1}. ${m.unitTitles[unit]}', style: Theme.of(ctx).textTheme.titleLarge),
                  Text('${m.acts[m.unitAct[unit]].label} · ${present.length} ${tr(s, 'in this section', 'в разделе')}',
                      style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 12)),
                ]),
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final k in EntityKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                    child: FilterChip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(kindIcon(k), size: 16, color: kindColor(k)),
                      label: Text('${kindLabel(s, k, plural: true)} ${m.cast.where((c) => c.kind == k).length}'),
                      selected: kinds.contains(k),
                      onSelected: (on) => set(() => on ? kinds.add(k) : kinds.remove(k)),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: SizedBox(
                height: 38,
                child: TextField(
                  onChanged: (v) => set(() => query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: tr(s, 'Find…', 'Найти…'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  label(tr(s, 'IN THIS SECTION', 'В ЭТОМ РАЗДЕЛЕ')),
                  if (here.isEmpty)
                    Text(kinds.isEmpty && query.isEmpty ? tr(s, 'Nobody and nothing marked yet.', 'Пока ничего не отмечено.') : tr(s, 'No match.', 'Нет совпадений.'),
                        style: TextStyle(color: Theme.of(ctx).hintColor)),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final i in here)
                      InputChip(
                          visualDensity: VisualDensity.compact,
                          avatar: StoryMark(m.cast[i]),
                          label: Text(m.cast[i].name),
                          onPressed: () => showEntitySheet(ctx, s, m, i, changed: changed),
                          onDeleted: () => toggle(i),
                          deleteButtonTooltipMessage: tr(s, 'Not in this section', 'Нет в этом разделе')),
                  ]),
                  for (final i in here)
                    if (m.cast[i].kind != EntityKind.person && m.cast[i].note.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 6), child: Text('${m.cast[i].name}: ${m.cast[i].note}', style: const TextStyle(fontSize: 13))),
                  if (ties.isNotEmpty) ...[
                    label(tr(s, 'CONNECTIONS HERE', 'СВЯЗИ ЗДЕСЬ')),
                    for (final t in ties.take(8))
                      Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('${m.cast[t.a].name} ↔ ${m.cast[t.b].name}${t.label.isEmpty ? '' : ' · ${t.label}'}', style: const TextStyle(fontSize: 13))),
                  ],
                  Row(children: [
                    Expanded(child: label(tr(s, 'ADD TO THIS SECTION', 'ДОБАВИТЬ В РАЗДЕЛ'))),
                    TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(tr(s, 'New', 'Новое')),
                        onPressed: () async {
                          await showEntityEditor(ctx, s, m, changed: changed);
                          // a new entity starts absent; mark it here right away
                          if (m.cast.isNotEmpty && m.cast.last.total == 0) m.togglePresence(m.cast.length - 1, unit);
                          changed();
                          if (ctx.mounted) set(() {});
                        }),
                  ]),
                  if (away.isEmpty) Text(tr(s, 'No match.', 'Нет совпадений.'), style: TextStyle(color: Theme.of(ctx).hintColor)),
                  for (final i in away)
                    InkWell(
                      onTap: () => toggle(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          StoryMark(m.cast[i]),
                          const SizedBox(width: 12),
                          Expanded(child: Text(m.cast[i].name, overflow: TextOverflow.ellipsis)),
                          Text(kindLabel(s, m.cast[i].kind), style: TextStyle(fontSize: 11, color: Theme.of(ctx).hintColor)),
                          const SizedBox(width: 8),
                          const Icon(Icons.add_circle_outline, size: 20),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        );
      },
    ),
  );
}

