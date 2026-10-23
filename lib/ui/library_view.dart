import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/utils/color.utils.dart';
import 'package:quill_fb2/utils/consts.dart';

class HomeActions {
  final Future<void> Function() openFile;
  final Future<void> Function(Map) openBook;
  final Future<void> Function(Map) removeBook;
  final VoidCallback openSettings;
  final VoidCallback? openHelp;
  /// Creates an empty book; the tile is hidden when null.
  final Future<void> Function()? newBook;
  HomeActions(this.openFile, this.openBook, this.removeBook, this.openSettings,
      {this.openHelp, this.newBook});
}

String _date(Map b) {
  final d = DateTime.tryParse('${b['updated']}') ?? DateTime.now();
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}


/// Real cover when present, else a generated tile (colour from the title).
class BookCover extends StatelessWidget {
  final Map book;
  final AppService service;
  final double w, h;
  const BookCover(this.book, this.service,
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

class LibraryView extends StatefulWidget {
  final AppService service;
  final HomeActions actions;
  const LibraryView(this.service, this.actions, {super.key});
  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final books = List<Map>.from((widget.service.workspace['history'] as List).reversed)
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
                    child: Text(tr(widget.service, 'Your library', 'Ваша библиотека'),
                        style: t.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                if (widget.actions.openHelp != null)
                  IconButton(
                      tooltip: tr(widget.service, 'Help', 'Справка'),
                      icon: const Icon(Icons.help_outline),
                      onPressed: widget.actions.openHelp),
                IconButton(
                    tooltip: tr(widget.service, 'Settings', 'Настройки'),
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
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr(widget.service, 'Search title or author',
                        'Поиск по названию или автору'),
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
                if (widget.actions.newBook != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.actions.newBook,
                    child: Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.colorScheme.outlineVariant)),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.note_add_outlined,
                                size: 36, color: t.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(tr(widget.service, 'New book', 'Новая книга'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: t.colorScheme.onSurfaceVariant,
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
                                      builder: (_, c) => BookCover(
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
                                  onSelected: (_) => widget.actions.removeBook(b),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'rm',
                                        child: Text(tr(widget.service,
                                            'Remove from list', 'Убрать из списка')))
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
          const SliverToBoxAdapter(child: SizedBox(height: 72)),
        ]),
      ),
    );
  }
}

