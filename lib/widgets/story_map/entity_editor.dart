import 'package:flutter/material.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/story_map/story_ui.dart';

Future<String?> askTieLabel(BuildContext context, AppService s, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(s, 'How are they connected?', 'Как они связаны?')),
      content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: tr(s, 'brother of, lives in, caused by…', 'брат, живёт в, вызвано…'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(s, 'Cancel', 'Отмена'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr(s, 'Save', 'Сохранить'))),
      ],
    ),
  );
}

Future<int?> pickEntity(BuildContext context, AppService s, StoryMap m, Set<int> skip) => showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr(s, 'Connect to…', 'Связать с…')),
        children: [
          for (var i = 0; i < m.cast.length; i++)
            if (!skip.contains(i))
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, i),
                  child: Row(children: [StoryMark(m.cast[i]), const SizedBox(width: 10), Expanded(child: Text(m.cast[i].name))])),
        ],
      ),
    );

/// Create (index null) or edit one entity: name, kind, role, note, and its connections.
Future<void> showEntityEditor(BuildContext context, AppService s, StoryMap m,
    {int? index, required VoidCallback changed}) {
  final existing = index == null ? null : m.cast[index];
  final name = TextEditingController(text: existing?.name ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  var kind = existing?.kind ?? EntityKind.person;
  var role = existing?.role ?? Role.minor;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final ties = index == null ? <Tie>[] : m.tiesOf(index);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(existing == null ? tr(s, 'Add to the map', 'Добавить на карту') : tr(s, 'Edit', 'Править'),
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                TextField(
                    controller: name,
                    autofocus: existing == null,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: tr(s, 'Name', 'Название'))),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  for (final k in EntityKind.values)
                    ChoiceChip(
                        avatar: Icon(kindIcon(k), size: 16, color: kindColor(k)),
                        label: Text(kindLabel(s, k)),
                        selected: kind == k,
                        onSelected: (_) => set(() => kind = k)),
                ]),
                if (kind == EntityKind.person) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final r in Role.values)
                      ChoiceChip(
                          avatar: StoryDot(roleColor(r), 9),
                          label: Text(roleLabel(s, r)),
                          selected: role == r,
                          onSelected: (_) => set(() => role = r)),
                  ]),
                ],
                const SizedBox(height: 8),
                TextField(
                    controller: note,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: tr(s, 'Note', 'Заметка'))),
                if (index != null) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Text(tr(s, 'Connections', 'Связи'), style: const TextStyle(fontWeight: FontWeight.w600))),
                    TextButton.icon(
                        icon: const Icon(Icons.add_link, size: 18),
                        label: Text(tr(s, 'Add', 'Добавить')),
                        onPressed: () async {
                          final other = await pickEntity(ctx, s, m, {index, for (final t in ties) m.other(t, index)});
                          if (other == null || !ctx.mounted) return;
                          final label = await askTieLabel(ctx, s, '');
                          if (label == null) return;
                          m.setTie(index, other, label);
                          changed();
                          set(() {});
                        }),
                  ]),
                  for (final t in ties)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: StoryMark(m.cast[m.other(t, index)]),
                      title: Text(m.cast[m.other(t, index)].name),
                      subtitle: Text(t.label.isEmpty ? tr(s, 'no label — tap to add', 'без подписи — нажмите') : t.label),
                      onTap: () async {
                        final label = await askTieLabel(ctx, s, t.label);
                        if (label == null) return;
                        t.label = label;
                        changed();
                        set(() {});
                      },
                      trailing: IconButton(
                          icon: const Icon(Icons.link_off, size: 20),
                          tooltip: tr(s, 'Remove connection', 'Убрать связь'),
                          onPressed: () {
                            m.removeTie(t);
                            changed();
                            set(() {});
                          }),
                    ),
                  if (ties.isEmpty) Text(tr(s, 'None yet.', 'Пока нет.'), style: TextStyle(color: Theme.of(ctx).hintColor)),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  if (index != null)
                    TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(tr(s, 'Remove', 'Убрать')),
                        onPressed: () {
                          final removed = m.removeEntity(index);
                          changed();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(SnackBar(
                                content: Text(tr(s, 'Removed ${removed.entity.name}', 'Убрано: ${removed.entity.name}')),
                                action: SnackBarAction(
                                    label: tr(s, 'Undo', 'Отменить'),
                                    onPressed: () {
                                      m.restoreEntity(removed);
                                      changed();
                                    })));
                        }),
                  const Spacer(),
                  FilledButton(
                      onPressed: () {
                        final n = name.text.trim();
                        if (n.isEmpty) return;
                        if (existing == null) {
                          m.addEntity(n, kind, role, note.text.trim());
                        } else {
                          m.updateEntity(index!, name: n, kind: kind, role: role, note: note.text.trim());
                        }
                        changed();
                        Navigator.pop(ctx);
                      },
                      child: Text(tr(s, 'Save', 'Сохранить'))),
                ]),
              ]),
            ),
          ),
        );
      },
    ),
  );
}

/// Everything the map knows about one section; also where appearances are marked.
