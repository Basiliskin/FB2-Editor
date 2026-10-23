import 'package:flutter/material.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'dart:math';
import 'package:quill_fb2/widgets/story_map/entity_editor.dart';
import 'package:quill_fb2/widgets/story_map/entity_sheet.dart';
import 'package:quill_fb2/widgets/story_map/section_sheet.dart';
import 'package:quill_fb2/widgets/story_map/story_ui.dart';

class _Dim {
  final double cw, rowH, nameW, headH, font;
  const _Dim(this.cw, this.rowH, this.nameW, this.headH, this.font);
}

const _comfortable = _Dim(64, 44, 150, 60, 12);
const _compact = _Dim(36, 32, 124, 52, 11);
const _bandH = 24.0; // group band over the column titles

/// Sections down the side (the story's order), entities across the top. The section column
/// and the entity titles stay in view while the grid scrolls; acts collapse to one heat row.
/// Zoom levels: 0 comfortable, 1 compact, 2 fit (every column squeezed into the screen width).
class TimelineGrid extends StatefulWidget {
  final AppService s;
  final StoryMap m;
  final List<int> vis;
  final bool editing;
  final VoidCallback changed;
  final Set<StoryEntity> picked; // toggled columns
  final void Function(int) onToggle;
  const TimelineGrid(this.s, this.m, this.vis, this.editing, this.changed, {required this.picked, required this.onToggle, super.key});
  @override
  State<TimelineGrid> createState() => _TimelineGridState();
}

class _TimelineGridState extends State<TimelineGrid> {
  final _hc = ScrollController();
  final _vc = ScrollController();
  int? _zoom;
  bool _showMap = false;
  final _wide = <EntityKind>{}; // groups the user expanded: their columns show names at full width
  final _collapsed = <int>{};
  late _Dim d;
  AppService get s => widget.s;
  StoryMap get m => widget.m;
  List<int> get vis => widget.vis;

  @override
  void dispose() {
    _hc.dispose();
    _vc.dispose();
    super.dispose();
  }

  void _open(int i, {int? act}) => widget.editing
      ? showEntityEditor(context, s, m, index: i, changed: widget.changed)
      : showEntitySheet(context, s, m, i, act: act, changed: widget.changed);

  /// Keeps [child] at the left edge while the table scrolls sideways.
  Widget _sticky(Widget child) => AnimatedBuilder(
        animation: _hc,
        builder: (_, c) => Transform.translate(offset: Offset(_hc.hasClients ? _hc.offset : 0, 0), child: c),
        child: child,
      );

  Widget _row(double width, double h, Widget label, Widget cells, Color bg, {Color? tint}) => SizedBox(
        height: h,
        width: width,
        child: Stack(children: [
          if (tint != null) Positioned.fill(child: ColoredBox(color: tint)),
          Positioned(left: d.nameW, top: 0, bottom: 0, child: cells),
          Positioned(left: 0, top: 0, bottom: 0, child: _sticky(Container(width: d.nameW, color: tint ?? bg, alignment: Alignment.centerLeft, child: label))),
        ]),
      );

  static String _initials(String short, bool two) {
    final c = short.characters;
    if (c.isEmpty) return '';
    return two && c.length > 1 ? '${c.first.toUpperCase()}${c.elementAt(1).toLowerCase()}' : c.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = t.colorScheme.surface;
    final screenW = MediaQuery.sizeOf(context).width;
    // first look: the roomiest level whose columns fit the screen without sideways scrolling
    _zoom ??= vis.length * _comfortable.cw + _comfortable.nameW <= screenW
        ? 0
        : (vis.length * _compact.cw + _compact.nameW <= screenW ? 1 : 2);
    final zoom = _zoom!;
    // columns are grouped by kind; the sort inside a group is the page's
    final cols = [for (final k in EntityKind.values) for (final i in vis) if (m.cast[i].kind == k) i];
    bool wide(int i) => _wide.contains(m.cast[i].kind);
    final wideCount = cols.where(wide).length;
    const fitName = 104.0;
    d = switch (zoom) {
      0 => _comfortable,
      1 => _compact,
      // squeeze the rest into what the expanded groups leave over
      _ => _Dim(cols.length == wideCount ? 34 : ((screenW - fitName - wideCount * _comfortable.cw) / (cols.length - wideCount)).clamp(9.0, 34.0), 26, fitName, 44, 10),
    };
    final tiny = zoom == 2;
    double w(int i) => wide(i) ? max(d.cw, _comfortable.cw) : d.cw;
    double inner(int i) => w(i) - (tiny && !wide(i) ? 2 : 6);
    final width = max(d.nameW + cols.fold<double>(0, (a, i) => a + w(i)), screenW);
    final maxOf = {for (final i in vis) i: m.cast[i].perUnit.fold<int>(1, max)};
    final maxAct = {for (final i in vis) i: m.cast[i].perAct.fold<int>(1, max)};

    // rows: act header, then its sections unless collapsed
    final items = <(bool, int)>[];
    for (var u = 0; u < m.unitCount; u++) {
      final a = m.unitAct[u];
      if (u == 0 || a != m.unitAct[u - 1]) items.add((true, a));
      if (!_collapsed.contains(a)) items.add((false, u));
    }
    final focusTint = t.colorScheme.primary.withValues(alpha: .10);

    Widget actRow(int a) {
      final closed = _collapsed.contains(a);
      return _row(
        width,
        28,
        InkWell(
          onTap: () => setState(() => closed ? _collapsed.remove(a) : _collapsed.add(a)),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(children: [
              Icon(closed ? Icons.chevron_right : Icons.expand_more, size: 16),
              Expanded(
                  child: Text('${m.acts[a].label.replaceFirst('Act ', tr(s, 'Act ', 'Акт '))} · ${m.acts[a].sections}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
        Row(children: [
          for (final i in cols)
            SizedBox(
              width: w(i),
              height: 28,
              child: Center(
                child: Container(
                  width: max(4.0, w(i) - (tiny && !wide(i) ? 2 : 8)),
                  height: closed ? 18 : 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: m.cast[i].perAct[a] == 0 ? null : entityColor(m.cast[i]).withValues(alpha: .2 + .7 * m.cast[i].perAct[a] / maxAct[i]!),
                  ),
                ),
              ),
            ),
        ]),
        bg,
        tint: t.colorScheme.surfaceContainerHigh,
      );
    }

    Widget unitRow(int u) => _row(
          width,
          d.rowH,
          InkWell(
            onTap: () => showSectionSheet(context, s, m, u, widget.changed).then((_) => setState(() {})),
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Row(children: [
                SizedBox(width: 26, child: Text('${u + 1}', style: TextStyle(fontSize: d.font - 1, color: t.hintColor))),
                Expanded(child: Text(m.unitTitles[u], maxLines: zoom == 0 ? 2 : 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: d.font))),
              ]),
            ),
          ),
          Row(children: [
            for (final i in cols)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (widget.editing) {
                    m.togglePresence(i, u);
                    widget.changed();
                  } else {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text('${m.cast[i].name} · ${m.unitTitles[u]}: ${m.cast[i].perUnit[u]}')));
                  }
                },
                child: Container(
                  width: w(i),
                  height: d.rowH,
                  color: widget.picked.contains(m.cast[i]) ? focusTint : null,
                  child: Center(
                    child: Container(
                      width: inner(i),
                      height: d.rowH - (tiny ? 3 : 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(tiny ? 2 : 5),
                        color: m.cast[i].perUnit[u] == 0 ? null : entityColor(m.cast[i]).withValues(alpha: .25 + .7 * m.cast[i].perUnit[u] / maxOf[i]!),
                        border: m.cast[i].perUnit[u] == 0 && !tiny ? Border.all(color: t.dividerColor.withValues(alpha: .4)) : null,
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          bg,
        );

    // column titles are horizontal: the short name when there is room, initials otherwise
    Widget title(int i) {
      final c = m.cast[i];
      final Widget text = zoom == 0 || wide(i)
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Text(c.short, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))
          : Text(_initials(c.short, w(i) >= 15), maxLines: 1, style: TextStyle(fontSize: w(i) >= 15 ? 11 : 9, fontWeight: FontWeight.w600));
      return InkWell(
        onTap: () => widget.editing ? _open(i) : widget.onToggle(i),
        child: Container(
          width: w(i),
          height: d.headH,
          color: widget.picked.contains(c) ? focusTint : null,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            text,
            SizedBox(height: zoom == 0 || wide(i) ? 4 : 2),
            widget.picked.contains(c) ? Icon(Icons.check_circle, size: tiny && w(i) < 15 ? 10 : 13, color: t.colorScheme.primary) : StoryMark(c, tiny && w(i) < 15 ? 6 : 8),
          ]),
        ),
      );
    }

    // one band per kind over its columns; tap to expand that group (names, full width) or fold it back
    Widget band(EntityKind k) {
      final ids = [for (final i in cols) if (m.cast[i].kind == k) i];
      if (ids.isEmpty) return const SizedBox.shrink();
      final bw = ids.fold<double>(0, (a, i) => a + w(i));
      final open = _wide.contains(k);
      return InkWell(
        onTap: () => setState(() => open ? _wide.remove(k) : _wide.add(k)),
        child: Container(
          width: bw,
          height: _bandH,
          decoration: BoxDecoration(
            color: kindColor(k).withValues(alpha: .16),
            border: Border(left: BorderSide(color: t.colorScheme.surface, width: 2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          // never overflows: what does not fit is clipped, and the fold icon only shows when there is room
          child: ClipRect(
            child: Stack(children: [
              OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: 200,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(kindIcon(k), size: 13, color: kindColor(k)),
                  if (bw >= 36) ...[
                    const SizedBox(width: 3),
                    Text(bw >= 92 ? '${kindLabel(s, k, plural: true)} ${ids.length}' : '${ids.length}',
                        maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ]),
              ),
              if (bw >= 64) Positioned(right: 0, top: 0, bottom: 0, child: Icon(open ? Icons.unfold_less : Icons.unfold_more, size: 13)),
            ]),
          ),
        ),
      );
    }

    final header = _row(
      width,
      d.headH + _bandH,
      Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text('${m.unitCount} ${tr(s, 'sections', 'разделов')}\n${vis.length} ${tr(s, 'items', 'объектов')}',
              style: TextStyle(fontSize: 11, color: t.hintColor))),
      Column(children: [
        Row(children: [for (final k in EntityKind.values) band(k)]),
        Row(children: [for (final i in cols) title(i)]),
      ]),
      bg,
    );

    final grid = SingleChildScrollView(
      controller: _hc,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(children: [
          header,
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _vc,
              itemCount: items.length,
              itemExtentBuilder: (i, _) => items[i].$1 ? 28 : d.rowH,
              itemBuilder: (_, i) => items[i].$1 ? actRow(items[i].$2) : unitRow(items[i].$2),
            ),
          ),
        ]),
      ),
    );

    String zoomName() => switch (zoom) {
          0 => tr(s, 'Comfortable', 'Крупно'),
          1 => tr(s, 'Compact', 'Компактно'),
          _ => tr(s, 'Fit to width', 'По ширине'),
        };

    return Column(children: [
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: _showMap ? _Minimap(m: m, vis: cols, hc: _hc, vc: _vc, dim: d, rows: items.length, items: items) : const SizedBox(width: double.infinity),
      ),
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: grid),
          Positioned(
            right: 8,
            bottom: 8,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(20),
              color: t.colorScheme.surfaceContainerHigh,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: tr(s, 'Overview map', 'Обзорная карта'),
                    isSelected: _showMap,
                    icon: const Icon(Icons.map_outlined),
                    selectedIcon: const Icon(Icons.map),
                    onPressed: () => setState(() => _showMap = !_showMap)),
                IconButton(
                    tooltip: '${tr(s, 'Zoom out', 'Мельче')} · ${zoom < 2 ? (zoom == 0 ? tr(s, 'Compact', 'Компактно') : tr(s, 'Fit to width', 'По ширине')) : ''}',
                    icon: const Icon(Icons.zoom_out),
                    onPressed: zoom < 2 ? () => setState(() => _zoom = zoom + 1) : null),
                IconButton(
                    tooltip: tr(s, 'Zoom in', 'Крупнее'),
                    icon: const Icon(Icons.zoom_in),
                    onPressed: zoom > 0 ? () => setState(() => _zoom = zoom - 1) : null),
              ]),
            ),
          ),
          Positioned(
              left: 10,
              bottom: 8,
              child: IgnorePointer(
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHigh.withValues(alpha: .9), borderRadius: BorderRadius.circular(10)),
                      child: Text(zoomName(), style: const TextStyle(fontSize: 11))))),
        ]),
      ),
      if (widget.editing)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 80, 0), // clear of the + button
          child: Text(
              tr(s, 'Editing: tap a cell to mark where something appears, a column title to edit it, a section to open its map.',
                  'Правка: ячейка — где что появляется, заголовок колонки — править, раздел — его карта.'),
              style: const TextStyle(fontSize: 12, color: storyWarn)),
        ),
      Padding(padding: EdgeInsets.fromLTRB(16, 4, widget.editing ? 80 : 16, 6), child: storyLegend(s)),
    ]);
  }
}

/// The whole book as a tiny picture: x = items, y = sections. The frame shows what the grid
/// shows now; tap or drag to move there.
class _Minimap extends StatelessWidget {
  final StoryMap m;
  final List<int> vis;
  final ScrollController hc, vc;
  final _Dim dim;
  final int rows;
  final List<(bool, int)> items;
  const _Minimap({required this.m, required this.vis, required this.hc, required this.vc, required this.dim, required this.rows, required this.items});

  void _jump(Offset p, Size size) {
    if (hc.hasClients) {
      final content = hc.position.maxScrollExtent + hc.position.viewportDimension;
      hc.jumpTo((p.dx / size.width * content - hc.position.viewportDimension / 2).clamp(0, hc.position.maxScrollExtent));
    }
    if (vc.hasClients) {
      final content = vc.position.maxScrollExtent + vc.position.viewportDimension;
      vc.jumpTo((p.dy / size.height * content - vc.position.viewportDimension / 2).clamp(0, vc.position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: LayoutBuilder(builder: (ctx, box) {
        final size = Size(box.maxWidth, 84);
        return GestureDetector(
          onTapDown: (e) => _jump(e.localPosition, size),
          onPanUpdate: (e) => _jump(e.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              size: size,
              painter: _MinimapPainter(m, vis, hc, vc, t, dim),
            ),
          ),
        );
      }),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final StoryMap m;
  final List<int> vis;
  final ScrollController hc, vc;
  final ThemeData theme;
  final _Dim dim;
  _MinimapPainter(this.m, this.vis, this.hc, this.vc, this.theme, this.dim) : super(repaint: Listenable.merge([hc, vc]));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.colorScheme.surfaceContainerHigh);
    if (vis.isEmpty || m.unitCount == 0) return;
    final cw = size.width / vis.length, ch = size.height / m.unitCount;
    final paint = Paint();
    for (var u = 0; u < m.unitCount; u++) {
      for (var k = 0; k < vis.length; k++) {
        final c = m.cast[vis[k]];
        if (c.perUnit[u] == 0) continue;
        canvas.drawRect(Rect.fromLTWH(k * cw, u * ch, max(1, cw), max(1, ch)), paint..color = entityColor(c).withValues(alpha: .85));
      }
    }
    if (hc.hasClients && vc.hasClients) {
      final cx = hc.position.maxScrollExtent + hc.position.viewportDimension;
      final cy = vc.position.maxScrollExtent + vc.position.viewportDimension;
      final r = Rect.fromLTWH(hc.offset / cx * size.width, vc.offset / cy * size.height,
          hc.position.viewportDimension / cx * size.width, vc.position.viewportDimension / cy * size.height);
      canvas.drawRect(r, Paint()..color = theme.colorScheme.primary.withValues(alpha: .15));
      canvas.drawRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = theme.colorScheme.primary);
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter o) => true;
}


