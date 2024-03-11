import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quill_fb2/utils/color.utils.dart';
import 'package:tuple/tuple.dart';
import 'package:flutter/src/widgets/text.dart' as BaseText;

import 'package:flutter_quill/flutter_quill.dart';

// import 'package:flutter_quill/models/documents/attribute.dart';
// import 'package:flutter_quill/models/documents/document.dart';
// import 'package:flutter_quill/widgets/controller.dart';
// import 'package:flutter_quill/widgets/editor.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';
import 'package:quill_fb2/widgets/section_editor/toolbar.dart';
import 'package:prompt_dialog/prompt_dialog.dart';
import 'package:image_picker/image_picker.dart';

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
  late QuillController _controller;
  late int currentIndex;
  int startBookmark = -1;
  // bool _selected = false;
  String clipboardText = '';
  Map state = {};
  final picker = ImagePicker();

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
    final quillDelta = widget.service.sectionToDeltaJson(widget.section);

    // const delta =
    //     r'[{"insert":"\n","attributes":{"blockquote":true}},{"insert":"Hello "},{"insert":"Markdown","attributes":{"bold":true}},{"insert":"\n"}]';
    // final myJSON = jsonDecode(delta);
    try {
      final document = Document.fromJson(quillDelta);
      _controller = QuillController(
        document: document,
        selection: TextSelection.collapsed(offset: 0),
        // onSelectionChanged: (TextSelection textSelection) =>
        //     _selectionChanged(textSelection),
      );
    } catch (e) {
      print(e);
    }
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
    final docText = _controller.document.toPlainText();
    widget.section.load(docText);
    await widget.service.saveProject(widget.book);
    final snackBar =
        SnackBar(content: BaseText.Text('${widget.book.bookTitle} Saved'));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
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
    Map settings = widget.service.getSettings();
    bool showImageBtn = settings["show-image"] ?? false;

    final imageButton = defaultToggleStyleButtonBuilderHandler(
        context, Attribute.unchecked, Icons.image, showImageBtn, () async {
      await widget.service.setSettings({"show-image": !showImageBtn});
      setState(() {
        isLoading = false;
      });
    });
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
      // addBookmark,
      // pasteSection,
      addSection,
      addAnnotation,
      // saveSection,
    ];
  }

  _change() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      print(pickedFile.path);
      Map settings = widget.service.getSettings();
      int _imageWidth = stringToInt(settings["image-width"]) ?? 1024;
      int _imageQuality = stringToInt(settings["image-quality"]) ?? 100;

      List<int> imageBytes = await readFileByte(pickedFile.path);
      String value =
          await resizeImageBytes(imageBytes, _imageWidth, _imageQuality);
      widget.book.addSecionImage(widget.section, value);
    } else {
      print('No image selected.');
      widget.book.addSecionImage(widget.section, '');
    }
    await widget.service.saveProject(widget.book);
    setState(() {});
  }

  _image() {
    Map settings = widget.service.getSettings();
    bool showImageBtn = stringToBool(settings["show-image"]) ?? false;
    if (!showImageBtn) return null;
    // final currentImage =
    //     widget.section.images.length > 0 ? widget.section.images[0] : "";
    final img = widget.book.getImageBySectionId(widget.section.sectionId);

    return GestureDetector(
        onTap: _change,
        child: Container(
          width: 100.0,
          height: 160.0,
          decoration: new BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.all(Radius.circular(10)),
              border: Border.all(
                  color: Colors.teal, width: 2.0, style: BorderStyle.solid),
              image: new DecorationImage(
                  fit: BoxFit.cover,
                  image: widget.service.base64Image(img, true))),
        ));
  }

  _navigateBack(BuildContext context) async {
    Map settings = widget.service.getSettings();
    bool autoSave = stringToBool(settings["auto-save"]) ?? false;
    print(autoSave);
    if (autoSave) {
      await _save();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Map settings = widget.service.getSettings();
    double fontSize = (stringToInt(settings["font-size"]) ?? 12).toDouble();
    final ModalRoundedProgressBar progressBar =
        ModalRoundedProgressBar(0.95, "Loading");
    List<Widget> stackItems = [];
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () => _navigateBack(context),
            child: Icon(Icons.arrow_back),
          ),
        ),
        title: BaseText.Text(trimSpecialChar(widget.section.title)),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: GestureDetector(
                onTap: () async {
                  _save();
                },
                child: Icon(Icons.save)),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: GestureDetector(
                onTap: () async {
                  final filePath =
                      await widget.service.exportProject(widget.book);
                  final snackBar = SnackBar(
                      content: BaseText.Text(
                          '${widget.book.bookTitle} Saved\n$filePath'));
                  ScaffoldMessenger.of(context).showSnackBar(snackBar);
                },
                child: Icon(Icons.fact_check)),
          )
        ],
      ),
      body: Stack(children: [
        Column(
          children: [
            CustomQuillToolbar.basic(
              controller: _controller,
              extensions: _toolbarButtons(),
            ),
            Expanded(
              child: Container(
                  child: QuillEditor(
                      controller: _controller,
                      scrollController: ScrollController(),
                      scrollable: true,
                      focusNode: FocusNode(),
                      autoFocus: true,
                      readOnly: false,
                      expands: false,
                      padding: EdgeInsets.zero,
                      keyboardAppearance: Brightness.light,
                      customStyles: DefaultStyles(
                        bold: TextStyle(
                            fontSize: fontSize, fontWeight: FontWeight.bold),
                        italic: TextStyle(
                            fontSize: fontSize, fontStyle: FontStyle.italic),
                        paragraph: DefaultTextBlockStyle(
                          TextStyle(
                              fontSize: fontSize,
                              color: ColorUtils.stringToColor("0")),
                          const Tuple2(0, 0),
                          const Tuple2(0, 0),
                          null,
                        ),
                      ))),
            )
          ],
        ),
        Align(
          alignment: Alignment(0.9, 0.9),
          child: _image(),
        )
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
    );
    stackItems.add(scaffold);
    if (isLoading) stackItems.add(progressBar);

    return Stack(
      children: stackItems,
    );
  }
}
