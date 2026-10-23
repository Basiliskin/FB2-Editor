import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';
import 'package:quill_fb2/widgets/forms/image.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';

import 'package:quill_fb2/ui/widgets.dart';
import 'annotation.dart';
import 'label.dart';

const Map<String, dynamic> defaultMap = {};

class BookComponent extends StatefulWidget {
  final ProjectModel book;
  final AppService service;
  final Stream<void>? triggerSave;
  BookComponent(this.service, this.book, this.triggerSave);
  @override
  _BookComponentState createState() => _BookComponentState();
}

class _BookComponentState extends State<BookComponent> {
  bool isLoading = false;

  Future<dynamic> _save(Map<String, dynamic> values, EasyFormState form) async {
    setState(() {
      isLoading = true;
    });
    widget.book.updateInfo(values);
    await widget.service.saveProject(widget.book);
    if (!mounted) return;
    final snackBar = SnackBar(
        content: Text(
            '${widget.book.bookTitle} ${widget.service.translate(LangTranslateItems.messageSaved)}'));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    setState(() {
      isLoading = false;
    });
  }

  _saved(
      dynamic response, Map<String, dynamic> fieldValues, EasyFormState form) {
    // print(response);
  }

  _createFormField(LangTranslateItems fieldName, String value,
      [bool validate = false]) {
    final label = widget.service.translate(fieldName);
    return EasyTextFormField(
      initialValue: value,
      name: fieldName.name,
      decoration: InputDecoration(
        labelText: label,
        hintText:
            '${widget.service.translate(LangTranslateItems.hintMessage)} $label',
      ),
      validator: (value, [values = defaultMap]) {
        if (validate && value!.isEmpty) {
          return widget.service.translate(LangTranslateItems.messagePlease);
        }
        return null;
      },
    );
  }

  _log(message) {
    final snackBar = SnackBar(content: Text(message));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  _build() {
    try {
      Map setting = widget.service.getSettings();
      final book = widget.book;
      {
        final s = widget.service;
        final labelForm = (String name, String hint, List<String> items) =>
            LabelFormField(name: name, initialValue: LabelData(hint, items));
        return PageBody(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                children: [
              SettingsGroup(tr(s, 'Cover & title', 'Обложка и название'), icon: Icons.menu_book_outlined, [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ImageFormField(
                    name: 'bookCoverPage',
                    initialValue: book.getImageBySectionId('cover'),
                    width: stringToInt(setting["image-width"]),
                    quality: stringToInt(setting["image-quality"]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(children: [
                    _createFormField(LangTranslateItems.bookTitle,
                        trimSpecialChar(book.bookTitle, ' ')),
                    _createFormField(LangTranslateItems.bookVersion, book.version),
                    _createFormField(LangTranslateItems.bookId, book.id),
                  ])),
                ]),
              ]),
              SettingsGroup(tr(s, 'Author', 'Автор'), icon: Icons.person_outline, [
                Row(children: [
                  Expanded(child: _createFormField(LangTranslateItems.authorFirst, book.author.firstName)),
                  const SizedBox(width: 12),
                  Expanded(child: _createFormField(LangTranslateItems.authorMid, book.author.middleName)),
                  const SizedBox(width: 12),
                  Expanded(child: _createFormField(LangTranslateItems.authorLast, book.author.lastName)),
                ]),
                _createFormField(LangTranslateItems.authorHomePage, book.author.homePage),
              ]),
              SettingsGroup(tr(s, 'Genre', 'Жанр'), icon: Icons.sell_outlined, [
                labelForm('genre', s.translate(LangTranslateItems.bookGenre), book.genre),
              ]),
              SettingsGroup(tr(s, 'Series', 'Серия'), icon: Icons.collections_bookmark_outlined, [
                labelForm('sequence', s.translate(LangTranslateItems.bookSequence), book.sequence),
              ]),
              SettingsGroup(tr(s, 'Annotation', 'Аннотация'), icon: Icons.notes, [
                AnnotationFormField(
                    name: 'annotation',
                    initialValue: AnnotationData(
                        s.translate(LangTranslateItems.bookAnnotation), book.annotation)),
              ]),
            ]));
      }
    } catch (e) {
      _log(e.toString());
      return Text(widget.service.translate(LangTranslateItems.messageError));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ModalRoundedProgressBar progressBar = ModalRoundedProgressBar(
        0.95, widget.service.translate(LangTranslateItems.messageLoading));
    List<Widget> stackItems = [];

    stackItems.add(EasyForm(
        onSave: _save,
        onSaved: _saved,
        child: _build(),
        triggerSave: widget.triggerSave,
        rebuildOnChange: false));
    if (isLoading) stackItems.add(progressBar);

    return Stack(
      children: stackItems,
    );
  }
}
