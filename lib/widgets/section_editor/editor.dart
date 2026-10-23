import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quill_fb2/utils/color.utils.dart';
import 'package:flutter/src/widgets/text.dart' as BaseText;

import 'package:flutter_quill/flutter_quill.dart';

// import 'package:flutter_quill/models/documents/attribute.dart';
// import 'package:flutter_quill/models/documents/document.dart';
// import 'package:flutter_quill/widgets/controller.dart';
// import 'package:flutter_quill/widgets/editor.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/leave_dialog.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';
import 'package:quill_fb2/widgets/section_editor/toolbar.dart';
import 'package:prompt_dialog/prompt_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quill_fb2/ui/widgets.dart';

class SectionEditor extends StatefulWidget {
  final ProjectModel book;
  final AppService service;
  final Section section;
  SectionEditor(this.service, this.book, this.section);
  @override
  _SectionEditorState createState() => _SectionEditorState();
}

class _SectionEditorState extends State<SectionEditor>
    with WidgetsBindingObserver {
  bool isLoading = false;
  // Quill lays out its whole document eagerly, so a large section would jank on
  // scroll. The section is shown as a lazy list of plain paragraphs and only the
  // paragraph being edited (_active) gets a real Quill editor.
  QuillController _controller = QuillController.basic();
  int _active = -1;
  String _activeText = '';
  final _activeKey = GlobalKey();
  final Map<String, String> _textCache = {};
  late int currentIndex;
  int startBookmark = -1;
  // bool _selected = false;
  String clipboardText = '';
  Map state = {};
  final picker = ImagePicker();
  final _scrollController = ScrollController();
  final _innerScroll = ScrollController();
  final _focusNode = FocusNode();

  void changePage(int? index) {
    setState(() {
      currentIndex = index!;
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    currentIndex = 0;
  }

  /// Editable text of one stored paragraph (inline markup shows as its own lines).
  String _paragraphText(String xml) {
    if (_textCache.length > 800) _textCache.clear();
    return _textCache.putIfAbsent(xml, () {
      return widget.section.editableText(xml);
    });
  }

  /// Writes the active paragraph back. Returns the number of paragraphs it now
  /// occupies (1 when its structure is unchanged).
  int _commitActive() {
    if (_active < 0) return 1;
    final text = _controller.document.toPlainText().replaceFirst(RegExp(r'\n$'), '');
    if (text == _activeText && text.isNotEmpty) return 1;
    final count = widget.section.replaceParagraph(_active, text);
    _activeText = text;
    return count;
  }

  /// Starts a new paragraph at the end of the section and opens it for typing.
  void _addParagraph() {
    if (_active >= 0) {
      _commitActive();
      _controller.dispose();
      _active = -1;
    }
    widget.section.p.add('<p></p>');
    _activate(widget.section.p.length - 1);
  }

  void _activate(int index) {
    var target = index;
    if (_active >= 0) {
      if (index == _active) return;
      final count = _commitActive();
      if (index > _active) target += count - 1;
      _controller.dispose();
    }
    final text = _paragraphText(widget.section.p[target]);
    setState(() {
      _active = target;
      _activeText = text;
      _controller = QuillController(
          document: Document.fromJson([
            {"insert": "$text\n"}
          ]),
          selection: TextSelection.collapsed(offset: text.length));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 150));
      }
    });
  }

  // _selectionChanged(TextSelection textSelection) async {
  //   await Future.delayed(Duration(seconds: 1));
  //   // todo: selection
  //   print(textSelection);
  //   if (textSelection.start != textSelection.end) {
  //     setState(() {
  //       _selected = true;
  //       startBookmark = textSelection.baseOffset;
  //     });
  //   } else if (_selected) {
  //     setState(() {
  //       _selected = false;
  //       startBookmark = -1;
  //     });
  //   }
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _innerScroll.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    Map settings = widget.service.getSettings();
    bool autoSave = stringToBool(settings["auto-save"]) ?? false;
    print('editor.state = ${state.name}');
    print(autoSave);
    if (autoSave && state == AppLifecycleState.paused) {
      await _save();
    }
  }

  _save() async {
    print('save');
    if (_commitActive() != 1) {
      // the paragraph split or vanished; drop the stale editor
      setState(() => _active = -1);
    }
    await widget.service.saveProject(widget.book);
    if (!mounted) return;
    final snackBar = SnackBar(
        content: BaseText.Text(
            '${widget.book.bookTitle}: ${widget.service.translate(LangTranslateItems.messageSavedInApp)}'));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Puts the paragraph being edited into the book, so saving and exporting see it.
  _flushActive() {
    if (_commitActive() != 1) setState(() => _active = -1);
  }

  _editContent(int previousBookmark, [String tag = '', cb]) async {
    // int _start = startBookmark;
    setState(() {
      startBookmark = _controller.selection.baseOffset;
      isLoading = true;
    });

    final docText = _controller.document.toPlainText();
    final baseOffset = _controller.selection.baseOffset;
    final extentOffset = _controller.selection.baseOffset +
        (_controller.selection.end - _controller.selection.start);

    final selection = _controller.selection
        .copyWith(baseOffset: baseOffset, extentOffset: extentOffset);
    // _controller.updateSelection(selection, ChangeSource.LOCAL);
    final previousText = docText.substring(baseOffset, extentOffset);
    _controller.replaceText(
        baseOffset,
        (extentOffset - baseOffset),
        tag.isEmpty
            ? ""
            : cb != null
                ? await cb(previousText)
                : "<$tag>$previousText</$tag>",
        selection);
    // print({extentOffset, baseOffset, previousText});
    // Clipboard.setData(new ClipboardData(text: previousText));
    // final snackBar = SnackBar(
    //   content: BaseText.Text('Copied to Clipboard'),
    //   // action: SnackBarAction(
    //   //   label: 'Undo',
    //   //   onPressed: () {},
    //   // ),
    // );
    // ScaffoldMessenger.of(context).showSnackBar(snackBar);
    // await Future.delayed(Duration(seconds: 1));
    // final updatedText = _controller.document.toPlainText();
    // widget.section.load(updatedText);
    // final resetSelection = _controller.selection
    //     .copyWith(baseOffset: _start); //copyWith(baseOffset: _start);
    // _controller.updateSelection(
    //     TextSelection.collapsed(offset: _start), ChangeSource.LOCAL);
    // await Future.delayed(Duration(seconds: 1));
    setState(() {
      // _selected = false;
      // state = {
      //   "end": startBookmark,
      //   "start": previousBookmark,
      //   "text": tag.isEmpty ? clipboardText : ""
      // };
      clipboardText = tag.isEmpty ? previousText : "";
      isLoading = false;
      startBookmark = -1;
    });
  }

  _hasContentToEdit() {
    return (_controller.selection.end - _controller.selection.start) > 0;
  }

  _toolbarButtons() {
    final strongButton = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.format_bold, startBookmark != -1,
        () async {
      if (_hasContentToEdit()) await _editContent(startBookmark, 'strong');
    });
    final emphasisSection = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.format_italic, startBookmark != -1,
        () async {
      if (_hasContentToEdit()) await _editContent(startBookmark, 'emphasis');
    });
    final citySection = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.format_quote, startBookmark != -1,
        () async {
      if (_hasContentToEdit())
        await _editContent(startBookmark, 'cite', (value) async {
          String? author = await prompt(
            context,
            title: BaseText.Text('Enter Author Name:'),
            textOK: BaseText.Text('Save'),
            textCancel: BaseText.Text('Cancel'),
            autoFocus: true,
            obscureText: false,
            obscuringCharacter: '•',
            textCapitalization: TextCapitalization.words,
          );
          return author!.isEmpty
              ? "<cite><p>$value</p></cite>"
              : "<cite><p>$value</p><text-author>$author</text-author></cite>";
        });
    });
    final addSection = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.book, false, () async {
      ClipboardData? data = await Clipboard.getData('text/plain');
      if (data == null) return;
      String cdata = data.text ?? '';
      if (cdata.isEmpty) return;
      // final newSectionName = await Clipboard.getData(Clipboard.kTextPlain);
      String? title = await prompt(
        context,
        // initialValue: newSectionName!.text,
        title: BaseText.Text('Enter Section Name:'),
        textOK: BaseText.Text('Save'),
        textCancel: BaseText.Text('Cancel'),
        autoFocus: true,
        obscureText: false,
        obscuringCharacter: '•',
        textCapitalization: TextCapitalization.words,
      );
      if (title != null) {
        setState(() {
          isLoading = true;
        });
        Section section = widget.book.addSection(title);
        section.load(cdata);
        _save();
        setState(() {
          isLoading = false;
          clipboardText = '';
        });
        final snackBar = SnackBar(content: BaseText.Text('$title Created'));
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    });
    final addAnnotation = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.contact_page, false, () async {
      ClipboardData? data = await Clipboard.getData('text/plain');
      if (data == null) return;
      String cdata = data.text ?? '';
      if (cdata.isEmpty) return;
      setState(() {
        isLoading = true;
      });
      widget.book.annotation.addAll(splitStringByEof(cdata));
      _save();
      setState(() {
        isLoading = false;
        clipboardText = '';
      });
      final snackBar = SnackBar(content: BaseText.Text('Annotation Added'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    });
    final poemButton = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.lyrics_outlined, false, _insertPoem);
    final imageButton = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.image, false, _insertPicture);
    // final addBookmark = defaultToggleStyleButtonBuilderHandler(
    //     context,
    //     Attribute.unchecked,
    //     startBookmark == -1 ? Icons.anchor : Icons.cut,
    //     startBookmark != -1, () async {
    //   final previousBookmark = startBookmark;
    //   if (previousBookmark != -1) {
    //     await _editContent(previousBookmark);
    //   } else {
    //     setState(() {
    //       startBookmark = _controller.selection.baseOffset;
    //     });
    //   }
    // });
    // final saveSection = defaultToggleStyleButtonBuilder(
    //     context, Attribute.unchecked, Icons.save, false, () {
    //   _save();
    // });

    // final pasteSection = defaultToggleStyleButtonBuilderHandler(
    //     context, Attribute.unchecked, Icons.paste, false, () async {
    //   final data = await Clipboard.getData('text/plain');
    //   if (data!.text!.isNotEmpty) {
    //     try {
    //       final selection = _controller.selection
    //           .copyWith(baseOffset: _controller.selection.baseOffset);
    //       // _controller.updateSelection(selection, ChangeSource.LOCAL);
    //       _controller.replaceText(
    //           _controller.selection.baseOffset, 0, data.text, selection);
    //     } catch (e) {
    //       print(e);
    //     }
    //   }
    // });
    return [
      strongButton,
      emphasisSection,
      citySection,
      imageButton,
      poemButton,
      // addBookmark,
      // pasteSection,
      addSection,
      addAnnotation,
      // saveSection,
    ];
  }

  /// Picks a picture and puts it after the paragraph being edited (or at the end).
  Future<void> _insertPicture() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null || !mounted) return;
    Map settings = widget.service.getSettings();
    int width = stringToInt(settings["image-width"]) ?? 1024;
    int quality = stringToInt(settings["image-quality"]) ?? 100;
    List<int> imageBytes = await readFileByte(pickedFile.path);
    final resized = await resizeImageBytes(imageBytes, width, quality);
    final data = resized is String ? resized : base64Encode(resized as List<int>);
    if (!mounted) return;
    var after = widget.section.p.length - 1;
    if (_active >= 0) {
      after = _active + _commitActive() - 1;
    }
    setState(() {
      _active = -1;
      widget.book.addInlineImage(widget.section, data, after);
    });
    await widget.service.saveProject(widget.book);
  }

  /// Turns the copied text into a poem (blank line = new stanza) after the
  /// paragraph being edited, or at the end.
  Future<void> _insertPoem() async {
    final data = await Clipboard.getData('text/plain');
    final poem = Section.poemBlock(data?.text ?? '');
    if (!mounted) return;
    if (poem == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: BaseText.Text(tr(widget.service,
              'Copy the verses first: a blank line starts a new stanza.',
              'Сначала скопируйте стихи: пустая строка начинает новую строфу.'))));
      return;
    }
    var after = widget.section.p.length - 1;
    if (_active >= 0) after = _active + _commitActive() - 1;
    setState(() {
      _active = -1;
      widget.section.insertBlock(after, poem);
    });
    await widget.service.saveProject(widget.book);
  }

  void _removePicture(int index) {
    setState(() {
      if (_active >= 0) {
        final count = _commitActive();
        if (index > _active) index += count - 1;
        _active = -1;
      }
      widget.book.removeInlineImage(widget.section, index);
    });
  }

  final Map<String, Uint8List?> _pictureBytes = {};

  Widget _pictureTile(int i, String href) {
    final bytes = _pictureBytes.putIfAbsent(href, () {
      final data = widget.book.binaryResource.find(href).data;
      if (data.isEmpty) return null;
      final b = decode64Image(data);
      return b is Uint8List ? b : null;
    });
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Stack(children: [
          // tall enough for the delete button even before the picture has loaded
          ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: double.infinity),
              child: Center(
              child: bytes == null
                  ? const Icon(Icons.broken_image_outlined, size: 48)
                  : Image.memory(bytes,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined, size: 48)))),
          Positioned(
              right: 4,
              top: 4,
              child: IconButton.filledTonal(
                  tooltip: tr(widget.service, 'Remove picture', 'Удалить картинку'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removePicture(i))),
        ]));
  }

  Widget _paragraphList(double fontSize) {
    final style = TextStyle(
        fontSize: fontSize, color: ColorUtils.stringToColor("0"), height: 1.3);
    final paragraphs = widget.section.p;
    return ListView.builder(
      controller: _scrollController,
      itemCount: paragraphs.length + 1,
      itemBuilder: (context, i) {
        if (i == paragraphs.length) {
          return Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _addParagraph,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr(widget.service, 'Add paragraph', 'Добавить абзац'))));
        }
        final href = imageHref(paragraphs[i]);
        if (href != null) return _pictureTile(i, href);
        if (i == _active) {
          return QuillEditor(
              key: _activeKey,
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _innerScroll,
              config: QuillEditorConfig(
                autoFocus: true,
                scrollable: false,
                padding: const EdgeInsets.symmetric(vertical: 4),
                customStyles: DefaultStyles(
                  bold: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
                  italic: TextStyle(fontSize: fontSize, fontStyle: FontStyle.italic),
                  paragraph: DefaultTextBlockStyle(
                    style,
                    HorizontalSpacing.zero,
                    VerticalSpacing.zero,
                    VerticalSpacing.zero,
                    null,
                  ),
                ),
              ));
        }
        return InkWell(
          onTap: () => _activate(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
                width: double.infinity,
                child: BaseText.Text(
                    paragraphs[i].startsWith('<poem')
                        ? widget.section.displayText(paragraphs[i])
                        : _paragraphText(paragraphs[i]),
                    style: paragraphs[i].startsWith('<poem')
                        ? style.copyWith(fontStyle: FontStyle.italic)
                        : style)),
          ),
        );
      },
    );
  }

  _navigateBack(BuildContext context) async {
    _flushActive();
    if (await confirmLeave(context, widget.service, widget.book) && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    Map settings = widget.service.getSettings();
    double fontSize = (stringToInt(settings["font-size"]) ?? 12).toDouble();
    final ModalRoundedProgressBar progressBar =
        ModalRoundedProgressBar(0.95, "Loading");
    List<Widget> stackItems = [];
    final scaffold = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _navigateBack(context);
        },
        child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      appBar: appBarFor(
              context,
              leading: IconButton(
                  tooltip: tr(widget.service, 'Back', 'Назад'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _navigateBack(context)),
              title: BaseText.Text(trimSpecialChar(widget.section.title)),
              actions: [
                IconButton(
                    tooltip: tr(widget.service, 'Help', 'Справка'),
                    icon: const Icon(Icons.help_outline),
                    onPressed: () => openHelp(context, widget.service)),
                IconButton(
                    tooltip: widget.service.translate(LangTranslateItems.buttonSave),
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () async {
                      _save();
                    }),
                IconButton(
                    tooltip: tr(widget.service, 'Export .fb2', 'Экспорт .fb2'),
                    icon: const Icon(Icons.fact_check_outlined),
                    onPressed: () async {
                      _flushActive();
                      final filePath = await widget.service.exportProject(widget.book);
                      final message =
                          exportedMessage(widget.service, widget.book, filePath);
                      if (message != null && mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: BaseText.Text(message)));
                      }
                    }),
              ],
            ),
      body: Stack(children: [
        Column(
          children: [
            Material(
                color: Theme.of(context).colorScheme.surface,
                child: CustomQuillToolbar.basic(
              controller: _controller,
              extensions: _toolbarButtons(),
            )),
            const Divider(height: 1),
            Expanded(
              child: EditorPage(
                  margin: (stringToInt(settings["editor-margin"]) ?? 24).toDouble(),
                  child: _paragraphList(fontSize)),
            )
          ],
        ),
      ]),
      // floatingActionButton: FloatingActionButton(
      //   backgroundColor: Colors.lightBlue,
      //   onPressed: () {
      //     print('Save');
      //   },
      //   child: Icon(Icons.save),
      //   shape: BeveledRectangleBorder(
      //     borderRadius: BorderRadius.circular(2),
      //   ),
      // )
    ));
    stackItems.add(scaffold);
    if (isLoading) stackItems.add(progressBar);

    return Stack(
      children: stackItems,
    );
  }
}

/// Wraps the editor in a centred "page" card.
class EditorPage extends StatelessWidget {
  final Widget child;
  /// Space between the page edge and the text.
  final double margin;
  const EditorPage({super.key, required this.child, this.margin = 24});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return PageBody(
        max: 760,
        child: Container(
          // fill the space above the keyboard so the card tracks the resize
          height: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          padding: EdgeInsets.symmetric(horizontal: margin, vertical: 16),
          decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.outlineVariant)),
          child: child,
        ));
  }
}
