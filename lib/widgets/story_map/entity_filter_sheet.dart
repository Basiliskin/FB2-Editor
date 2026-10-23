import 'package:flutter/material.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/story_map/story_ui.dart';

/// Checkbox list of every item: toggle any, Apply keeps only those as columns, Reset shows all
/// again. Null when dismissed.
Future<({bool reset, Set<StoryEntity> picked})?> showEntityFilterSheet(
  BuildContext context, AppService s, StoryMap m, Set<StoryEntity> initial) {
  final draft = <StoryEntity>{...initial};
  var query = '';
  return showModalBottomSheet<({bool reset, Set<StoryEntity> picked})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final groups = [
          for (final k in EntityKind.values)
            (k, [for (final c in m.cast) if (c.kind == k && (query.isEmpty || c.name.toLowerCase().contains(query))) c]..sort((a, b) => b.total - a.total))
        ].where((g) => g.$2.isNotEmpty).toList();
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Expanded(child: Text(tr(s, 'Filter items', 'Фильтр объектов'), style: Theme.of(ctx).textTheme.titleLarge)),
                Text(tr(s, '${draft.length} selected', 'выбрано: ${draft.length}')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
              child: ListView(shrinkWrap: true, children: [
                for (final (k, list) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(children: [
                      Icon(kindIcon(k), size: 16, color: kindColor(k)),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${kindLabel(s, k, plural: true)} ${list.length}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      TextButton(
                        onPressed: () => set(() => list.every(draft.contains) ? draft.removeAll(list) : draft.addAll(list)),
                        child: Text(list.every(draft.contains) ? tr(s, 'None', 'Снять') : tr(s, 'All', 'Все')),
                      ),
                    ]),
                  ),
                  for (final c in list)
                    CheckboxListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: StoryMark(c),
                      title: Text(c.name, overflow: TextOverflow.ellipsis),
                      value: draft.contains(c),
                      onChanged: (on) => set(() => on == true ? draft.add(c) : draft.remove(c)),
                    ),
                ],
                if (groups.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr(s, 'No match.', 'Нет совпадений.')))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, (reset: true, picked: <StoryEntity>{})),
                    child: Text(tr(s, 'Reset', 'Сбросить'))),
                const Spacer(),
                FilledButton(
                    onPressed: draft.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, (reset: false, picked: {...draft})),
                    child: Text(tr(s, 'Apply (${draft.length})', 'Применить (${draft.length})'))),
              ]),
            ),
          ]),
        );
      },
    ),
  );
}
