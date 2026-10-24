import 'package:flutter/material.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/pages/names_check_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/story_map/entity_editor.dart';
import 'package:quill_fb2/widgets/story_map/entity_filter_sheet.dart';
import 'package:quill_fb2/widgets/story_map/entity_sheet.dart';
import 'package:quill_fb2/widgets/story_map/story_ui.dart';
import 'package:quill_fb2/widgets/story_map/timeline_grid.dart';

/// The story map of a book: sections down the side, people / places / events / lore across.
/// Built from the text, then managed by hand; every edit is written into the book.
class StoryMapPage extends StatefulWidget {
  final AppService service;
  final ProjectModel book;
  const StoryMapPage(this.service, this.book, {super.key});
  @override
  State<StoryMapPage> createState() => _StoryMapPageState();
}

enum ColumnSort { mentions, firstAppearance, name }

class _StoryMapPageState extends State<StoryMapPage> {
  late Future<StoryMap> _map = widget.book.loadStoryMap();
  StoryMap? _m;
  bool _editing = false;
  bool _dirty = false; // the map was edited: the book screen should treat the book as changed
  final Set<StoryEntity> _picked = {}; // toggled by tapping column titles or in the filter sheet
  Set<StoryEntity>? _only; // applied filter: only these entities are shown as columns
  String _query = '';
  ColumnSort _sort = ColumnSort.mentions;

  /// Entities to show as columns, after the kind filter, the search and the sort.
  List<int> _visible(StoryMap m) {
    final q = _query.trim().toLowerCase();
    final ids = [
      for (var i = 0; i < m.cast.length; i++)
        if ((_only == null || _only!.contains(m.cast[i])) && (q.isEmpty || m.cast[i].name.toLowerCase().contains(q))) i
    ];
    int first(int i) {
      final u = m.cast[i].perUnit.indexWhere((x) => x > 0);
      return u < 0 ? 1 << 30 : u;
    }

    switch (_sort) {
      case ColumnSort.mentions:
        ids.sort((a, b) => m.cast[b].total - m.cast[a].total);
      case ColumnSort.firstAppearance:
        ids.sort((a, b) => first(a) - first(b));
      case ColumnSort.name:
        ids.sort((a, b) => m.cast[a].name.compareTo(m.cast[b].name));
    }
    return ids;
  }

  /// Every edit: write it into the book and redraw.
  void _changed() {
    if (_m != null) widget.book.saveStoryMap(_m!);
    _dirty = true;
    setState(() {});
  }

  Future<void> _regenerate() async {
    final s = widget.service;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(s, 'Rebuild from the text?', 'Пересобрать по тексту?')),
        content: Text(tr(s, 'Your edits to the map are replaced by a fresh automatic map. The book text is not changed.',
            'Ваши правки карты заменятся новой автоматической картой. Текст книги не изменится.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(s, 'Cancel', 'Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(s, 'Rebuild', 'Пересобрать'))),
        ],
      ),
    );
    if (ok != true) return;
    widget.book.discardStoryMap();
    _dirty = true;
    setState(() {
      _m = null;
      _picked.clear();
      _only = null;
      _map = widget.book.loadStoryMap();
    });
  }

  void _showFlags(StoryMap m) {
    final s = widget.service;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr(s, 'Worth a look', 'Стоит проверить'), style: Theme.of(ctx).textTheme.titleMedium)),
          for (final f in m.flags)
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: storyWarn),
              title: Text(f.text),
              onTap: () {
                Navigator.pop(ctx);
                showEntitySheet(context, s, m, f.who, act: f.act, changed: _changed);
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _openFilter(StoryMap m) async {
    final r = await showEntityFilterSheet(context, widget.service, m, _picked.isNotEmpty ? _picked : (_only ?? <StoryEntity>{}));
    if (r == null || !mounted) return;
    setState(() {
      _only = r.reset ? null : {...r.picked};
      _picked.clear();
    });
  }

  /// Shown above the grid: what is toggled and not yet applied, or that a filter is on.
  Widget _selectionBar(StoryMap m, int shown) {
    final s = widget.service;
    final t = Theme.of(context);
    if (_picked.isEmpty && _only == null) return const SizedBox.shrink();
    final picking = _picked.isNotEmpty;
    return Container(
      color: t.colorScheme.primary.withValues(alpha: .10),
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(children: [
        Expanded(
            child: Text(
                picking
                    ? tr(s, '${_picked.length} toggled', 'отмечено: ${_picked.length}')
                    : tr(s, 'Showing $shown of ${m.cast.length}', 'Показано $shown из ${m.cast.length}'),
                style: const TextStyle(fontSize: 13))),
        if (picking && _picked.length == 1)
          TextButton(onPressed: () => showEntitySheet(context, s, m, m.cast.indexOf(_picked.first), changed: _changed), child: Text(tr(s, 'Details', 'Подробнее'))),
        TextButton(
            onPressed: () => setState(() {
                  _picked.clear();
                  if (!picking) _only = null;
                }),
            child: Text(picking ? tr(s, 'Clear', 'Очистить') : tr(s, 'Reset', 'Сбросить'))),
        if (picking)
          FilledButton(
              onPressed: () => setState(() {
                    _only = {..._picked};
                    _picked.clear();
                  }),
              child: Text(tr(s, 'Apply', 'Применить'))),
      ]),
    );
  }

  Widget _toolbar(StoryMap m) {
    final s = widget.service;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: tr(s, 'Find a person, place, event…', 'Найти героя, место, событие…'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          IconButton(
              tooltip: tr(s, 'Filter items', 'Фильтр объектов'),
              icon: Badge(isLabelVisible: _only != null, label: Text('${_only?.length ?? 0}'), child: const Icon(Icons.filter_list)),
              onPressed: () => _openFilter(m)),
          PopupMenuButton<ColumnSort>(
            tooltip: tr(s, 'Order columns', 'Порядок колонок'),
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              PopupMenuItem(value: ColumnSort.mentions, child: Text(tr(s, 'Most mentioned', 'Чаще упоминаются'))),
              PopupMenuItem(value: ColumnSort.firstAppearance, child: Text(tr(s, 'First appearance', 'Порядок появления'))),
              PopupMenuItem(value: ColumnSort.name, child: Text(tr(s, 'By name', 'По имени'))),
            ],
          ),
          if (m.flags.isNotEmpty)
            IconButton(
                tooltip: tr(s, 'Worth a look', 'Стоит проверить'),
                icon: Badge(label: Text('${m.flags.length}'), child: const Icon(Icons.flag_outlined)),
                onPressed: () => _showFlags(m)),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_dirty);
      },
      child: Scaffold(
        appBar: appBarFor(context, title: Text(tr(s, 'Story map', 'Карта истории')), actions: [
          IconButton(
              tooltip: tr(s, 'Help', 'Справка'),
              icon: const Icon(Icons.help_outline),
              onPressed: () => openHelp(context, s, topic: 'story-map')),
          IconButton(
              tooltip: _editing ? tr(s, 'Done', 'Готово') : tr(s, 'Edit', 'Править'),
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
              onPressed: () => setState(() => _editing = !_editing)),
          PopupMenuButton<String>(
              tooltip: tr(s, 'More', 'Ещё'),
              onSelected: (v) => v == 'names' ? openNamesCheck(context, s, widget.book) : _regenerate(),
              itemBuilder: (_) => [
                    PopupMenuItem(value: 'names', child: Text(tr(s, 'Check names', 'Проверить имена'))),
                    PopupMenuItem(value: 'rebuild', child: Text(tr(s, 'Rebuild from the text', 'Пересобрать по тексту'))),
                  ]),
        ]),
        floatingActionButton: _editing && _m != null
            ? FloatingActionButton(
                heroTag: 'storyMapAdd',
                tooltip: tr(s, 'Add person, place, event or lore', 'Добавить героя, место, событие или мир'),
                child: const Icon(Icons.add),
                onPressed: () => showEntityEditor(context, s, _m!, changed: _changed))
            : null,
        body: FutureBuilder<StoryMap>(
          future: _map,
          builder: (ctx, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final map = snap.data!;
            _m = map;
            _picked.removeWhere((c) => !map.cast.contains(c));
            _only?.removeWhere((c) => !map.cast.contains(c));
            if (_only != null && _only!.isEmpty) _only = null;
            final vis = _visible(map);
            return Column(children: [
              if (map.cast.isEmpty)
                Container(
                  width: double.infinity,
                  color: storyWarn.withValues(alpha: .18),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                      tr(s, 'No names found in the text yet. Tap the pencil, then + to add people, places, events or lore.',
                          'В тексте пока не найдено имён. Нажмите карандаш, затем +, чтобы добавить героев, места, события или мир.'),
                      style: const TextStyle(fontSize: 12)),
                ),
              _toolbar(map),
              _selectionBar(map, vis.length),
              Expanded(
                  child: TimelineGrid(s, map, vis, _editing, _changed,
                      picked: _picked,
                      onToggle: (i) => setState(() => _picked.contains(map.cast[i]) ? _picked.remove(map.cast[i]) : _picked.add(map.cast[i])))),
            ]);
          },
        ),
      ),
    );
  }
}

/// Opens the story map. Completes with true when the map was edited, so the caller can
/// treat the book as changed.
Future<bool> openStoryMap(BuildContext context, AppService s, ProjectModel book) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => StoryMapPage(s, book))) ?? false;
