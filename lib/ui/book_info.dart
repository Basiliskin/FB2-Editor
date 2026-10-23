// Layout of the book Info tab: cover banner on top, flat form sections below.
import 'package:flutter/material.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// Real form fields, handed to the layout so it only decides placement.
class InfoKit {
  final AppService s;
  final ProjectModel book;
  final Widget Function(LangTranslateItems, String,
      {TextStyle? style, int maxLines, bool flat}) text;
  final Widget Function(double width) cover;
  final Widget Function(String name, String hint, List<String> items) labels;
  final Widget Function() annotation;
  final VoidCallback? onStoryMap;
  InfoKit(this.s, this.book,
      {required this.text,
      required this.cover,
      required this.labels,
      required this.annotation,
      this.onStoryMap});

  String get title => trimSpecialChar(book.bookTitle, ' ');
  Widget caption(BuildContext c, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t.toUpperCase(),
          style: Theme.of(c).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Theme.of(c).colorScheme.primary)));
}

class BookInfoLayout extends StatelessWidget {
  final InfoKit k;
  const BookInfoLayout(this.k, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final img = k.book.getImageBySectionId('cover');
    final has = img is String && img.isNotEmpty;
    Widget sec(String title, List<Widget> kids) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          k.caption(context, title),
          ...kids,
        ]));
    Widget two(Widget a, Widget b) => Row(children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ]);
    return PageBody(
        child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
      Stack(alignment: Alignment.center, children: [
        Positioned.fill(
            child: Container(
                decoration: BoxDecoration(
                    color: t.colorScheme.primaryContainer,
                    image: has
                        ? DecorationImage(
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                                Colors.black.withValues(alpha: .45),
                                BlendMode.darken),
                            image: MemoryImage(decode64Image(img)))
                        : null))),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: t.colorScheme.surface.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(blurRadius: 14, color: Colors.black38)
                    ]),
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      k.cover(132),
                      if (k.onStoryMap != null)
                        TextButton.icon(
                            onPressed: k.onStoryMap,
                            icon: const Icon(Icons.timeline, size: 16),
                            label: Text(tr(k.s, 'Story map', 'Карта сюжета'))),
                    ])))),
      ]),
      sec(tr(k.s, 'Title', 'Название'), [
        k.text(LangTranslateItems.bookTitle, k.title,
            style:
                t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 3,
            flat: true),
      ]),
      const Divider(height: 28),
      sec(tr(k.s, 'Author', 'Автор'), [
        two(
            k.text(LangTranslateItems.authorFirst, k.book.author.firstName,
                flat: true),
            k.text(LangTranslateItems.authorLast, k.book.author.lastName,
                flat: true)),
        two(
            k.text(LangTranslateItems.authorMid, k.book.author.middleName,
                flat: true),
            k.text(LangTranslateItems.authorHomePage, k.book.author.homePage,
                flat: true)),
        k.text(LangTranslateItems.authorEmail, k.book.author.email, flat: true),
      ]),
      const Divider(height: 28),
      sec(tr(k.s, 'Genre', 'Жанр'), [
        k.labels(
            'genre', k.s.translate(LangTranslateItems.bookGenre), k.book.genre),
      ]),
      sec(tr(k.s, 'Series', 'Серия'), [
        k.labels('sequence', k.s.translate(LangTranslateItems.bookSequence),
            k.book.sequence),
      ]),
      const Divider(height: 28),
      sec(tr(k.s, 'Annotation', 'Аннотация'), [k.annotation()]),
      const Divider(height: 28),
      sec(tr(k.s, 'Book details', 'О книге'), [
        two(k.text(LangTranslateItems.bookLang, k.book.lang, flat: true),
            k.text(LangTranslateItems.bookDate, k.book.date, flat: true)),
        k.text(LangTranslateItems.bookKeywords, k.book.keywords,
            maxLines: 2, flat: true),
      ]),
      const Divider(height: 28),
      sec(tr(k.s, 'File info', 'О файле'), [
        two(k.text(LangTranslateItems.bookVersion, k.book.version, flat: true),
            k.text(LangTranslateItems.bookId, k.book.id, flat: true)),
      ]),
    ]));
  }
}
