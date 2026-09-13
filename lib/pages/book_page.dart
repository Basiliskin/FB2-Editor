import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prompt_dialog/prompt_dialog.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/color.utils.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/forms/book_form.dart';
import 'package:quill_fb2/widgets/section/list.dart';

class BookPage extends StatefulWidget {
  final ProjectModel book;
  final AppService service;
  final StreamController<void>? triggerChange;
  BookPage(this.service, this.book, this.triggerChange);
  @override
  _BookPageState createState() => _BookPageState();
}

class _BookPageState extends State<BookPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey _scaffoldKey = GlobalKey();
  late TabController controller;
  late String onChangedString = '{}';
  StreamController<void>? changeController;
  Map<String, Section> _toDelete = {};

  _markToDelete(Section section) {
    setState(() {
      if (_toDelete.containsKey(section.sectionId))
        _toDelete.remove(section.sectionId);
      else
        _toDelete[section.sectionId] = section;
    });
    return _toDelete.containsKey(section.sectionId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    changeController!.close();
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    Map settings = widget.service.getSettings();
    bool autoSave = stringToBool(settings["auto-save"]) ?? false;
    print('page.state = ${state.name} - autoSave=$autoSave');
    print(autoSave);
  }

  void setChangedString(String changedString) {
    print('setChangedString');
    setState(() {
      onChangedString = changedString;
    });
    changeController!.add({});
    // Future.delayed(Duration(seconds: 3), () => {widget.triggerChange!.add({})});
    /*
      final filePath =
          await widget.service.saveProject(widget.book);
      final snackBar = SnackBar(
          content:
              Text('${widget.book.bookTitle} Saved\n$filePath'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      changeController!.add({});
    */
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _toDelete = {};
    changeController = StreamController<void>.broadcast();
    controller = TabController(length: 2, vsync: this);
    super.initState();
  }

  void resultsCallback(Map<String, String> results) {
    print(results);
  }

  _removeSelectedSections() {
    setState(() {
      widget.book.removeSelected(_toDelete);
      _toDelete = {};
    });
  }

  _build() {
    try {
      return SafeArea(
          child: Column(
        children: <Widget>[
          TabBar(
            onTap: (_) => setChangedString('{}'),
            labelColor: Theme.of(context).colorScheme.primary,
            controller: controller,
            tabs: <Widget>[
              Tab(
                  text: widget.service
                      .translate(LangTranslateItems.bookPageInfo)),
              Tab(
                  text: widget.service
                      .translate(LangTranslateItems.bookPageSection))
            ],
          ),
          Expanded(
              child: TabBarView(controller: controller, children: <Widget>[
            /// Simple Form Builder with custom form UI, Extension Syntax
            BookComponent(widget.service, widget.book,
                changeController!.stream.asBroadcastStream()),
            Stack(
              children: [
                SectionList(
                    widget.service,
                    widget.book,
                    changeController!.stream.asBroadcastStream(),
                    _markToDelete),
                Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                        width: 40.0,
                        height: 40.0,
                        child: FloatingActionButton(
                          heroTag: 'bookPage',
                          backgroundColor: _toDelete.keys.length > 0
                              ? Colors.red
                              : Colors.blue,
                          onPressed: () async {
                            if (_toDelete.keys.length > 0) {
                              return _removeSelectedSections();
                            }
                            String? title = await prompt(
                              context,
                              title: Text(widget.service.translate(
                                  LangTranslateItems.bookPagePromptEnterName)),
                              textOK: Text(widget.service
                                  .translate(LangTranslateItems.buttonSave)),
                              textCancel: Text(widget.service
                                  .translate(LangTranslateItems.buttonCancel)),
                              autoFocus: true,
                              obscureText: false,
                              obscuringCharacter: '•',
                              textCapitalization: TextCapitalization.words,
                            );
                            if (title != null) {
                              print('Add Section');
                              setState(() {
                                widget.book.addSection(title);
                              });
                              setChangedString('{}');
                              final snackBar = SnackBar(
                                  content: Text(
                                      '$title ${widget.service.translate(LangTranslateItems.messageCreated)}'));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(snackBar);
                            }
                          },
                          child: Icon(_toDelete.keys.length > 0
                              ? Icons.delete_forever
                              : Icons.add),
                          shape: BeveledRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        )))
              ],
            ),
          ]))
        ],
      ));
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    Map settings = widget.service.getSettings();
    bool autoSave = stringToBool(settings["auto-save"]) ?? false;
    Color? autoSaveIconColor = autoSave
        ? ColorUtils.stringToColor('#00FF0000')
        : ColorUtils.stringToColor('#000000');

    return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(trimSpecialChar(widget.book.bookTitle, ' ')),
          centerTitle: true,
          actions: [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: GestureDetector(
                  onTap: () async {
                    await widget.service.setSettings({"auto-save": !autoSave});
                    setChangedString('{}');
                  },
                  child: Icon(Icons.auto_awesome, color: autoSaveIconColor)),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: GestureDetector(
                  onTap: () async {
                    setChangedString('{}');
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
                        content: Text(
                            '${widget.book.bookTitle} ${widget.service.translate(LangTranslateItems.messageSaved)}\n$filePath'));
                    ScaffoldMessenger.of(context).showSnackBar(snackBar);
                  },
                  child: Icon(Icons.storage)),
            )
          ],
        ),
        body: Padding(
          padding: EdgeInsets.all(16.0),
          child: _build(),
        ));
  }
}
