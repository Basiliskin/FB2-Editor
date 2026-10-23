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
import 'package:quill_fb2/ui/book_info.dart';
import 'annotation.dart';
import 'label.dart';

const Map<String, dynamic> defaultMap = {};

class BookComponent extends StatefulWidget {
  final ProjectModel book;
  final AppService service;
  final Stream<void>? triggerSave;
  final VoidCallback? onStoryMap;
  BookComponent(this.service, this.book, this.triggerSave, {this.onStoryMap});
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
            '${widget.book.bookTitle}: ${widget.service.translate(LangTranslateItems.messageSavedInApp)}'));
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
      {TextStyle? style,
      int maxLines = 1,
      bool flat = false}) {
    final label = widget.service.translate(fieldName);
    final c = Theme.of(context).colorScheme;
    return EasyTextFormField(
      initialValue: value,
      name: fieldName.name,
      style: style,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: !flat,
        fillColor: c.surfaceContainerHighest.withValues(alpha: .5),
        border: flat
            ? const UnderlineInputBorder()
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
      ),
    );
  }

  _build() {
    try {
      Map setting = widget.service.getSettings();
      final book = widget.book;
      final kit = InfoKit(widget.service, book,
          onStoryMap: widget.onStoryMap,
          text: (n, val, {style, maxLines = 1, flat = false}) =>
              _createFormField(n, val,
                  style: style, maxLines: maxLines, flat: flat),
          cover: (w) => ImageFormField(
                name: 'bookCoverPage',
                initialValue: book.getImageBySectionId('cover'),
                width: stringToInt(setting["image-width"]),
                quality: stringToInt(setting["image-quality"]),
                coverWidth: w,
              ),
          labels: (name, hint, items) =>
              LabelFormField(name: name, initialValue: LabelData(hint, items)),
          annotation: () => AnnotationFormField(
              name: 'annotation',
              initialValue: AnnotationData(
                  widget.service.translate(LangTranslateItems.bookAnnotation),
                  book.annotation)));
      return BookInfoLayout(kit);
    } catch (e) {
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
