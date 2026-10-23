// PROTOTYPE - THROWAWAY. Variants of the HomeScreen. Read-only: stub books
// are used when the workspace history is empty, actions on them are no-ops.
import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/color.utils.dart';
import 'package:quill_fb2/utils/consts.dart';

import 'prototype_switcher.dart';

class HomeActions {
  final Future<void> Function() openFile;
  final Future<void> Function(Map) openBook;
  final Future<void> Function(Map) removeBook;
  final VoidCallback openSettings;
  HomeActions(this.openFile, this.openBook, this.removeBook, this.openSettings);
}

/// Real history, or stub books so variants can be judged with data.
List<Map> protoBooks(AppService s) {
  final real = List<Map>.from((s.workspace['history'] as List).reversed);
  if (real.isNotEmpty) return real;
  final now = DateTime.now();
  Map b(String t, String a, String seq, int daysAgo) => {
        'title': t,
        'author': a,
        'sequence': seq,
        'version': '1.0',
        'cover': '',
        'stub': true,
        'updated': now.subtract(Duration(days: daysAgo)).toString(),
      };
  return [
    b('War and Peace', 'Leo Tolstoy', '', 0),
    b('The Hobbit', 'J. R. R. Tolkien', 'Middle-earth', 2),
    b('Solaris', 'Stanisław Lem', '', 9),
    b('Roadside Picnic', 'Arkady Strugatsky', 'Stalker', 21),
    b('Dune', 'Frank Herbert', 'Dune Chronicles', 40),
  ];
}

String _date(Map b) {
  final d = DateTime.tryParse('${b['updated']}') ?? DateTime.now();
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}

/// Real cover when present, else a generated tile (colour from the title).
class ProtoCover extends StatelessWidget {
  final Map book;
  final AppService service;
  final double w, h;
  const ProtoCover(this.book, this.service,
      {super.key, this.w = 80, this.h = 116});
  @override
  Widget build(BuildContext context) {
    final has = '${book['cover'] ?? ''}'.isNotEmpty;
    final title = '${book['title'] ?? '?'}';
    final c = ColorUtils.stringToColor(title);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: w,
        height: h,
        child: has
            ? Image(
                image: service.base64Image(book['cover'], true),
                fit: BoxFit.cover)
            : Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [c, Color.alphaBlend(Colors.black38, c)])),
                alignment: Alignment.bottomLeft,
                child: Text(title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: w / 7,
                        fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }
}

void _stubNote(BuildContext c) => ScaffoldMessenger.of(c).showSnackBar(
    const SnackBar(content: Text('Prototype sample book - action disabled')));

Widget _classicLink() => Builder(
    builder: (c) => TextButton.icon(
        onPressed: () => Proto.set('0'),
        icon: const Icon(Icons.history, size: 16),
        label: const Text('Use classic look')));

// ───────────────────────── Variant A: familiar, refreshed ──────────────────
// Same structure & positions as today: Load tile on top, list below, gear top
// right, delete top-right of each card, cover on the right.
class HomeVariantA extends StatelessWidget {
  final AppService service;
  final HomeActions actions;
  const HomeVariantA(this.service, this.actions, {super.key});
  @override
  Widget build(BuildContext context) {
    final books = protoBooks(service);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(service.translate(LangTranslateItems.appTitle)),
        actions: [
          IconButton(
              icon: const Icon(Icons.settings), onPressed: actions.openSettings)
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            color: t.colorScheme.primaryContainer,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: actions.openFile,
              child: SizedBox(
                height: 110,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add,
                          size: 32, color: t.colorScheme.onPrimaryContainer),
                      const SizedBox(height: 4),
                      Text(service.translate(LangTranslateItems.buttonLoadBook),
                          style: t.textTheme.titleMedium?.copyWith(
                              color: t.colorScheme.onPrimaryContainer)),
                    ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final b in books)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => actions.openBook(b),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${b['author'] ?? '-'}',
                                style: t.textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            Text(
                                '[ ${_date(b)} ] ${b['sequence'] ?? ''} ( ${b['version'] ?? ''} )',
                                style: t.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Text('${b['title'] ?? 'Unknown'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                          ]),
                    ),
                    ProtoCover(b, service),
                    Column(children: [
                      IconButton(
                          tooltip: 'Remove from list',
                          icon: Icon(Icons.delete_outline,
                              color: t.colorScheme.error),
                          onPressed: () => b['stub'] == true
                              ? _stubNote(context)
                              : actions.removeBook(b)),
                    ]),
                  ]),
                ),
              ),
            ),
          Center(child: _classicLink()),
        ],
      ),
    );
  }
}

// ───────────────────────── Variant B: library shelf ────────────────────────
class HomeVariantB extends StatefulWidget {
  final AppService service;
  final HomeActions actions;
  const HomeVariantB(this.service, this.actions, {super.key});
  @override
  State<HomeVariantB> createState() => _HomeVariantBState();
}

class _HomeVariantBState extends State<HomeVariantB> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final books = protoBooks(widget.service)
        .where((b) => '${b['title']} ${b['author']}'
            .toLowerCase()
            .contains(q.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
              child: Row(children: [
                Expanded(
                    child: Text('Your library',
                        style: t.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: widget.actions.openSettings),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TextField(
                onChanged: (v) => setState(() => q = v),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search title or author',
                    isDense: true),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 0.52),
              delegate: SliverChildListDelegate([
                // first tile = the old "Load book" button, same place in reading order
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.actions.openFile,
                  child: Container(
                    decoration: BoxDecoration(
                        color: t.colorScheme.primaryContainer
                            .withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: t.colorScheme.primary, width: 1.5)),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline,
                              size: 36, color: t.colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(
                              widget.service
                                  .translate(LangTranslateItems.buttonLoadBook),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: t.colorScheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                ),
                for (final b in books)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => widget.actions.openBook(b),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(children: [
                              Positioned.fill(
                                  child: LayoutBuilder(
                                      builder: (_, c) => ProtoCover(
                                          b, widget.service,
                                          w: c.maxWidth, h: c.maxHeight))),
                              Positioned(
                                right: 2,
                                top: 2,
                                child: PopupMenuButton<String>(
                                  icon: const CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.black54,
                                      child: Icon(Icons.more_vert,
                                          size: 16, color: Colors.white)),
                                  onSelected: (_) => b['stub'] == true
                                      ? _stubNote(context)
                                      : widget.actions.removeBook(b),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'rm',
                                        child: Text('Remove from list'))
                                  ],
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          Text('${b['title']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text('${b['author']} · ${_date(b)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodySmall),
                        ]),
                  ),
              ]),
            ),
          ),
          SliverToBoxAdapter(child: Center(child: _classicLink())),
          const SliverToBoxAdapter(child: SizedBox(height: 72)),
        ]),
      ),
    );
  }
}

// ───────────────────────── Variant C: workspace ────────────────────────────
class HomeVariantC extends StatefulWidget {
  final AppService service;
  final HomeActions actions;
  const HomeVariantC(this.service, this.actions, {super.key});
  @override
  State<HomeVariantC> createState() => _HomeVariantCState();
}

class _HomeVariantCState extends State<HomeVariantC> {
  int sel = 0;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final books = protoBooks(widget.service);
    final cur = books[sel.clamp(0, books.length - 1)];
    final wide = MediaQuery.sizeOf(context).width >= 760;

    final list =
        ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('Recent',
            style:
                t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ),
      for (var i = 0; i < books.length; i++)
        ListTile(
          selected: wide && i == sel,
          selectedTileColor:
              t.colorScheme.primaryContainer.withValues(alpha: .5),
          leading: ProtoCover(books[i], widget.service, w: 40, h: 56),
          title: Text('${books[i]['title']}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${books[i]['author']} · ${_date(books[i])}'),
          onTap: () {
            if (wide) {
              setState(() => sel = i);
            } else {
              widget.actions.openBook(books[i]);
            }
          },
        ),
    ]);

    final detail = Padding(
      padding: const EdgeInsets.all(32),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProtoCover(cur, widget.service, w: 180, h: 260),
        const SizedBox(width: 32),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${cur['title']}',
                style: t.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${cur['author']}', style: t.textTheme.titleMedium),
            if ('${cur['sequence'] ?? ''}'.isNotEmpty)
              Text('Series: ${cur['sequence']}'),
            Text('Last edited ${_date(cur)}  ·  v${cur['version']}',
                style: t.textTheme.bodySmall),
            const SizedBox(height: 24),
            Wrap(spacing: 12, children: [
              FilledButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Continue editing'),
                  onPressed: () => widget.actions.openBook(cur)),
              OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove from list'),
                  onPressed: () => cur['stub'] == true
                      ? _stubNote(context)
                      : widget.actions.removeBook(cur)),
            ]),
          ]),
        ),
      ]),
    );

    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              title:
                  Text(widget.service.translate(LangTranslateItems.appTitle)),
              actions: [
                  IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: widget.actions.openSettings)
                ]),
      floatingActionButton: wide
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: FloatingActionButton.extended(
                  onPressed: widget.actions.openFile,
                  icon: const Icon(Icons.add),
                  label: Text(widget.service
                      .translate(LangTranslateItems.buttonLoadBook))),
            ),
      body: wide
          ? Row(children: [
              Container(
                width: 220,
                color: t.colorScheme.surfaceContainer,
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          widget.service.translate(LangTranslateItems.appTitle),
                          style: t.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                          onPressed: widget.actions.openFile,
                          icon: const Icon(Icons.add),
                          label: Text(widget.service
                              .translate(LangTranslateItems.buttonLoadBook))),
                      const SizedBox(height: 12),
                      ListTile(
                          dense: true,
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('Settings'),
                          onTap: widget.actions.openSettings),
                      const Spacer(),
                      _classicLink(),
                      const SizedBox(height: 56),
                    ]),
              ),
              SizedBox(width: 320, child: list),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ])
          : list,
    );
  }
}

// ───────────────────────── Variant 0: original look (control) ──────────────
// Replica of the current HomeScreen so the standalone prototype has a control.
class HomeVariantOriginal extends StatelessWidget {
  final AppService service;
  final HomeActions actions;
  const HomeVariantOriginal(this.service, this.actions, {super.key});
  @override
  Widget build(BuildContext context) {
    BoxDecoration card() => BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 10)
            ]);
    return Scaffold(
      appBar: AppBar(
          title: Text(service.translate(LangTranslateItems.appTitle)),
          centerTitle: true,
          actions: [
            Padding(
                padding: const EdgeInsets.all(8),
                child: GestureDetector(
                    onTap: actions.openSettings,
                    child: const Icon(Icons.settings)))
          ]),
      body: ListView(children: [
        Card(
            child: Container(
          height: 150,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: card(),
          child: Center(
            child: SizedBox(
              width: 120,
              height: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Material(
                  color: Colors.lightBlue[100],
                  child: InkWell(
                    onTap: actions.openFile,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add, color: Colors.black),
                          Text(
                              service
                                  .translate(LangTranslateItems.buttonLoadBook),
                              style: const TextStyle(color: Colors.black)),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        )),
        for (final b in protoBooks(service))
          Container(
            height: 150,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: card(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Stack(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b['author']}',
                            style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                        Text(
                            '[ ${_date(b)} ] ${b['sequence']} ( ${b['version']} )',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black)),
                        const SizedBox(height: 12),
                        Text('${b['title']}',
                            style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                      ]),
                ),
                ProtoCover(b, service, w: 100, h: 130),
              ]),
              Positioned(
                right: 0,
                top: 0,
                child: SizedBox(
                    height: 32,
                    width: 32,
                    child: FittedBox(
                        child: FloatingActionButton(
                            heroTag: null,
                            backgroundColor: Colors.red,
                            mini: true,
                            shape: BeveledRectangleBorder(
                                borderRadius: BorderRadius.circular(5)),
                            onPressed: () => actions.removeBook(b),
                            child: const Icon(Icons.delete)))),
              ),
            ]),
          ),
      ]),
    );
  }
}
