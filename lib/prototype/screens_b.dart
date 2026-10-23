// PROTOTYPE - THROWAWAY. Variant-B design language applied to the other
// screens: Book (Info | Book tabs), Section editor, Settings. In-memory only.
// The editor body is a plain TextField: flutter_quill can't compile here.
import 'package:flutter/material.dart';

import 'home_variants.dart';
import 'package:quill_fb2/services/app.service.dart';

// ── shared bits ──────────────────────────────────────────────────────────────
Widget _group(BuildContext c, String title, List<Widget> children,
    {IconData? icon}) {
  final t = Theme.of(c);
  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: t.colorScheme.primary),
            const SizedBox(width: 8)
          ],
          Text(title,
              style: t.textTheme.titleSmall?.copyWith(
                  color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
        ]),
      ),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: children))),
    ]),
  );
}

Widget _field(String label, String value, {int lines = 1}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
          initialValue: value,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, isDense: true)),
    );

class _Page extends StatelessWidget {
  final Widget child;
  final double max;
  const _Page(this.child, {this.max = 760});
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max), child: child));
}

// ── Book screen ──────────────────────────────────────────────────────────────
class _Chapter {
  String title;
  int paras;
  _Chapter(this.title, this.paras);
}

class BookScreenB extends StatefulWidget {
  final Map book;
  final AppService service;
  const BookScreenB(this.book, this.service, {super.key});
  @override
  State<BookScreenB> createState() => _BookScreenBState();
}

class _BookScreenBState extends State<BookScreenB> {
  bool autoSave = true;
  final Set<int> selected = {};
  late final List<_Chapter> chapters = [
    _Chapter('Part One', 42),
    _Chapter('Chapter 1', 118),
    _Chapter('Chapter 2', 96),
    _Chapter('Chapter 3', 131),
    _Chapter('Epilogue', 24),
  ];

  void _toast(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = widget.book;
    final selecting = selected.isNotEmpty;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: t.colorScheme.surface,
          foregroundColor: t.colorScheme.onSurface,
          centerTitle: false,
          title: Row(children: [
            ProtoCover(b, widget.service, w: 28, h: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${b['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleMedium),
                    Text('${b['author']}', style: t.textTheme.bodySmall),
                  ]),
            ),
          ]),
          actions: [
            // same three actions & icons as today, now labelled
            IconButton(
                tooltip: autoSave ? 'Auto-save: on' : 'Auto-save: off',
                icon: Icon(Icons.auto_awesome,
                    color: autoSave ? Colors.green : null),
                onPressed: () => setState(() => autoSave = !autoSave)),
            IconButton(
                tooltip: 'Save',
                icon: const Icon(Icons.save_outlined),
                onPressed: () => _toast('Saved')),
            IconButton(
                tooltip: 'Export .fb2',
                icon: const Icon(Icons.storage_outlined),
                onPressed: () => _toast('Exported')),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Info'), Tab(text: 'Book')]),
        ),
        body: TabBarView(children: [_info(context), _book(context, selecting)]),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 56),
          child: Builder(
            builder: (c) => AnimatedBuilder(
              animation: DefaultTabController.of(c),
              builder: (_, __) => DefaultTabController.of(c).index != 1
                  ? const SizedBox.shrink()
                  : selecting
                      ? FloatingActionButton.extended(
                          backgroundColor: t.colorScheme.error,
                          foregroundColor: t.colorScheme.onError,
                          icon: const Icon(Icons.delete_outline),
                          label: Text('Delete ${selected.length}'),
                          onPressed: () => setState(() {
                                final idx = selected.toList()
                                  ..sort((a, b) => b.compareTo(a));
                                for (final i in idx) {
                                  chapters.removeAt(i);
                                }
                                selected.clear();
                              }))
                      : FloatingActionButton.extended(
                          icon: const Icon(Icons.add),
                          label: const Text('New section'),
                          onPressed: () => setState(
                              () => chapters.add(_Chapter('New Section', 0)))),
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(BuildContext context) {
    final b = widget.book;
    final t = Theme.of(context);
    return _Page(ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          _group(context, 'Cover & title', icon: Icons.menu_book_outlined, [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                ProtoCover(b, widget.service, w: 110, h: 160),
                TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('Change')),
              ]),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(children: [
                _field('Book Title', '${b['title']}'),
                _field('Version', '${b['version']}'),
                _field('Book ID', 'a1b2c3d4'),
              ])),
            ]),
          ]),
          _group(context, 'Author', icon: Icons.person_outline, [
            Row(children: [
              Expanded(
                  child: _field('First', '${b['author']}'.split(' ').first)),
              const SizedBox(width: 12),
              Expanded(child: _field('Middle', '')),
              const SizedBox(width: 12),
              Expanded(child: _field('Last', '${b['author']}'.split(' ').last)),
            ]),
            _field('Home Page', ''),
          ]),
          _group(context, 'Genre & series', icon: Icons.sell_outlined, [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, children: [
                InputChip(label: const Text('prose'), onDeleted: () {}),
                InputChip(label: const Text('sf'), onDeleted: () {}),
                ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Genre'),
                    onPressed: () {}),
              ]),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, children: [
                if ('${b['sequence']}'.isNotEmpty)
                  InputChip(label: Text('${b['sequence']}'), onDeleted: () {}),
                ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Series'),
                    onPressed: () {}),
              ]),
            ),
          ]),
          _group(context, 'Annotation', icon: Icons.notes, [
            _field('Annotation', 'A short description of the book…', lines: 5),
          ]),
          Center(
              child: Text(
                  autoSave
                      ? 'Changes are saved automatically'
                      : 'Auto-save is off – press Save',
                  style: t.textTheme.bodySmall)),
        ]));
  }

  Widget _book(BuildContext context, bool selecting) {
    final t = Theme.of(context);
    return _Page(ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      buildDefaultDragHandles: false,
      itemCount: chapters.length,
      onReorder: (o, n) => setState(() {
        if (n > o) n--;
        chapters.insert(n, chapters.removeAt(o));
        selected.clear();
      }),
      itemBuilder: (c, i) {
        final ch = chapters[i];
        final sel = selected.contains(i);
        return Card(
          key: ValueKey('${ch.title}$i'),
          margin: const EdgeInsets.only(bottom: 8),
          color:
              sel ? t.colorScheme.errorContainer.withValues(alpha: .4) : null,
          child: ListTile(
            leading: selecting
                ? Checkbox(
                    value: sel,
                    onChanged: (_) => setState(
                        () => sel ? selected.remove(i) : selected.add(i)))
                : CircleAvatar(
                    backgroundColor: t.colorScheme.primaryContainer,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: t.colorScheme.onPrimaryContainer))),
            title: Text(ch.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${ch.paras} paragraphs'),
            onLongPress: () => setState(() => selected.add(i)),
            onTap: selecting
                ? () =>
                    setState(() => sel ? selected.remove(i) : selected.add(i))
                : () => Navigator.push(c,
                    MaterialPageRoute(builder: (_) => EditorScreenB(ch.title))),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: 'Edit text',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                          builder: (_) => EditorScreenB(ch.title)))),
              ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_indicator))),
            ]),
          ),
        );
      },
    ));
  }
}

// ── Section editor ───────────────────────────────────────────────────────────
class EditorScreenB extends StatelessWidget {
  final String title;
  const EditorScreenB(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget tb(IconData i, String tip) => IconButton(
        tooltip: tip,
        icon: Icon(i),
        onPressed: () {},
        visualDensity: VisualDensity.compact);
    return Scaffold(
      backgroundColor: t.colorScheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: t.colorScheme.surface,
        foregroundColor: t.colorScheme.onSurface,
        title: Text(title),
        actions: [
          IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.save_outlined),
              onPressed: () {}),
          IconButton(
              tooltip: 'Check',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () {}),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        // same tools as the current toolbar, one tidy row; scrolls on narrow screens
        Material(
          color: t.colorScheme.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              tb(Icons.undo_outlined, 'Undo'),
              tb(Icons.redo_outlined, 'Redo'),
              const SizedBox(height: 24, child: VerticalDivider()),
              tb(Icons.format_bold, 'Bold'),
              tb(Icons.format_italic, 'Italic'),
              tb(Icons.format_quote, 'Quote'),
              const SizedBox(height: 24, child: VerticalDivider()),
              tb(Icons.image_outlined, 'Section image'),
              tb(Icons.book_outlined, 'New section'),
              tb(Icons.contact_page_outlined, 'Author name'),
            ]),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _Page(
            max: 720,
            Container(
              margin: const EdgeInsets.fromLTRB(12, 16, 12, 72),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              decoration: BoxDecoration(
                  color: t.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.colorScheme.outlineVariant)),
              child: TextFormField(
                maxLines: null,
                expands: true,
                style: const TextStyle(fontSize: 16, height: 1.6),
                initialValue:
                    'It was a bright cold day in April, and the clocks were striking thirteen.\n\n'
                    'Winston Smith, his chin nuzzled into his breast in an effort to escape the vile wind, '
                    'slipped quickly through the glass doors of Victory Mansions…',
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Settings ─────────────────────────────────────────────────────────────────
class SettingsScreenB extends StatefulWidget {
  const SettingsScreenB({super.key});
  @override
  State<SettingsScreenB> createState() => _SettingsScreenBState();
}

class _SettingsScreenBState extends State<SettingsScreenB> {
  bool autoSave = false, showImage = false;
  String width = '600', quality = 'best', font = '12', lang = 'eng';

  Widget _dd(String label, String value, List<String> opts,
          void Function(String) on,
          {IconData? icon}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: icon == null ? null : Icon(icon),
        title: Text(label),
        trailing: DropdownButton<String>(
          value: value,
          underline: const SizedBox.shrink(),
          items: [
            for (final o in opts) DropdownMenuItem(value: o, child: Text(o))
          ],
          onChanged: (v) => setState(() => on(v!)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          backgroundColor: t.colorScheme.surface,
          foregroundColor: t.colorScheme.onSurface,
          title: const Text('Settings')),
      body: _Page(
          max: 600,
          ListView(padding: const EdgeInsets.all(16), children: [
            _group(context, 'Editing', icon: Icons.edit_outlined, [
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autosave book'),
                  subtitle: const Text('Save changes as you type'),
                  value: autoSave,
                  onChanged: (v) => setState(() => autoSave = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show page image'),
                  value: showImage,
                  onChanged: (v) => setState(() => showImage = v)),
              _dd('Font size', font, ['10', '12', '14', '16', '18'],
                  (v) => font = v,
                  icon: Icons.format_size),
            ]),
            _group(context, 'Images', icon: Icons.image_outlined, [
              _dd('Image width', width, ['300', '600', '900', '1200'],
                  (v) => width = v),
              _dd('Image quality', quality, ['best', '90', '75', '50'],
                  (v) => quality = v),
            ]),
            _group(context, 'Language', icon: Icons.language, [
              _dd('Language', lang, ['eng', 'ru'], (v) => lang = v),
            ]),
            Center(
                child:
                    Text('Saved automatically', style: t.textTheme.bodySmall)),
          ])),
    );
  }
}
