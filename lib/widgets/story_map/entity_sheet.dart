import 'package:flutter/material.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/story_map/entity_editor.dart';
import 'package:quill_fb2/widgets/story_map/story_ui.dart';


/// Details of one entity: kind, note, mentions per act, sections, ties, a line from the text.
Future<void> showEntitySheet(BuildContext context, AppService s, StoryMap m, int c,
    {int? act, VoidCallback? changed}) {
  final ch = m.cast[c];
  final ties = m.tiesOf(c).take(8).toList();
  final where = [for (var u = 0; u < m.unitCount; u++) if (ch.perUnit[u] > 0) u];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StoryMark(ch, 14),
            const SizedBox(width: 8),
            Expanded(child: Text(ch.name, style: Theme.of(ctx).textTheme.titleLarge)),
            Text(ch.kind == EntityKind.person ? roleLabel(s, ch.role) : kindLabel(s, ch.kind), style: const TextStyle(fontSize: 12)),
          ]),
          if (ch.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ch.note)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (var a = 0; a < m.acts.length; a++)
              Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: a == act ? entityColor(ch).withValues(alpha: .25) : null,
                  side: ch.perAct[a] == 0 ? const BorderSide(color: storyWarn) : null,
                  label: Text('${m.acts[a].label} · ${ch.perAct[a] == 0 ? tr(s, 'none', 'нет') : ch.perAct[a]}')),
          ]),
          if (where.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr(s, 'Sections', 'Разделы'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(where.map((u) => '${u + 1}. ${m.unitTitles[u]}').join('  ·  '), style: const TextStyle(fontSize: 13)),
          ],
          if (ties.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr(s, 'Connected to', 'Связан с'), style: const TextStyle(fontSize: 12)),
            for (final t in ties)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: StoryMark(m.cast[m.other(t, c)]),
                title: Text(tieText(m, t, c)),
                trailing: Text(t.manual ? '' : '×${t.weight}'),
              ),
          ],
          for (var a = 0; a < m.acts.length; a++)
            if (ch.snippet[a] != null && (act == null || act == a)) ...[
              const SizedBox(height: 10),
              Text(m.acts[a].label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text('«${clipText(ch.snippet[a])}»', style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          if (changed != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(tr(s, 'Edit', 'Править')),
                onPressed: () {
                  Navigator.pop(ctx);
                  showEntityEditor(context, s, m, index: c, changed: changed);
                }),
          ],
        ]),
      ),
    ),
  );
}

