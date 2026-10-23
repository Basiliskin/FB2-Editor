/// Colors, icons, labels and small shared widgets for the story map screens.
import 'package:flutter/material.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';

Color roleColor(Role r) => switch (r) {
      Role.protagonist => const Color(0xFF5B8DEF),
      Role.major => const Color(0xFF3FB68B),
      Role.minor => const Color(0xFF9B7BE8),
    };
Color kindColor(EntityKind k) => switch (k) {
      EntityKind.person => const Color(0xFF9B7BE8),
      EntityKind.place => const Color(0xFF26A6C9),
      EntityKind.event => const Color(0xFFE8833A),
      EntityKind.lore => const Color(0xFFC2A13A),
    };
Color entityColor(StoryEntity c) => c.kind == EntityKind.person ? roleColor(c.role) : kindColor(c.kind);
IconData kindIcon(EntityKind k) => switch (k) {
      EntityKind.person => Icons.person_outline,
      EntityKind.place => Icons.place_outlined,
      EntityKind.event => Icons.bolt,
      EntityKind.lore => Icons.auto_stories_outlined,
    };
String kindLabel(AppService s, EntityKind k, {bool plural = false}) => switch (k) {
      EntityKind.person => plural ? tr(s, 'People', 'Герои') : tr(s, 'Person', 'Герой'),
      EntityKind.place => plural ? tr(s, 'Places', 'Места') : tr(s, 'Place', 'Место'),
      EntityKind.event => plural ? tr(s, 'Events', 'События') : tr(s, 'Event', 'Событие'),
      EntityKind.lore => plural ? tr(s, 'Lore', 'Мир') : tr(s, 'Lore', 'Мир'),
    };
String roleLabel(AppService s, Role r) => switch (r) {
      Role.protagonist => tr(s, 'protagonist', 'главный герой'),
      Role.major => tr(s, 'major', 'важный'),
      Role.minor => tr(s, 'minor', 'второстепенный'),
    };
const storyWarn = Color(0xFFF0B429);

String clipText(String? t, [int n = 170]) =>
    t == null ? '' : (t.length <= n ? t : '${t.substring(0, n).trimRight()}…');

class StoryDot extends StatelessWidget {
  final Color color;
  final double size;
  const StoryDot(this.color, [this.size = 10]);
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// A person is a colored dot (color = role); every other kind is its icon.
class StoryMark extends StatelessWidget {
  final StoryEntity c;
  final double size;
  const StoryMark(this.c, [this.size = 10]);
  @override
  Widget build(BuildContext context) => c.kind == EntityKind.person
      ? StoryDot(entityColor(c), size)
      : Icon(kindIcon(c.kind), size: size + 5, color: entityColor(c));
}

/// People (by role) and the other kinds, in two labelled groups that wrap instead of scrolling.
Widget storyLegend(AppService s) {
  Widget group(String title, List<Widget> items) => Wrap(spacing: 12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ...items,
      ]);
  Widget item(Widget mark, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        mark,
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    group(kindLabel(s, EntityKind.person, plural: true), [for (final r in Role.values) item(StoryDot(roleColor(r), 8), roleLabel(s, r))]),
    const SizedBox(height: 2),
    group(tr(s, 'Other', 'Прочее'), [for (final k in EntityKind.values.skip(1)) item(Icon(kindIcon(k), size: 14, color: kindColor(k)), kindLabel(s, k))]),
  ]);
}

String tieText(StoryMap m, Tie t, int from) =>
    '${m.cast[m.other(t, from)].name}${t.label.isEmpty ? '' : ' — ${t.label}'}';
