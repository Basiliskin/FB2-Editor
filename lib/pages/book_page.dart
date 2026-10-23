import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prompt_dialog/prompt_dialog.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/color.utils.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/forms/book_form.dart';
import 'package:quill_fb2/widgets/leave_dialog.dart';
import 'package:quill_fb2/widgets/find_replace_dialog.dart';
import 'package:quill_fb2/widgets/section/list.dart';
import 'package:quill_fb2/ui/widgets.dart';

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

  /// Lets the forms put their values into the book before it is saved or exported.
  Future<void> _flushForms() async {
    changeController!.add({});
    await Future.delayed(Duration.zero);
  }

  Future<void> _export() async {
    final s = widget.service;
    await _flushForms();
    final filePath = await s.exportProject(widget.book);
    final message = exportedMessage(s, widget.book, filePath);
    if (message != null && mounted) {
      // drop the "saved" notice the flush raised so the export result shows now
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _findReplace() async {
    await _flushForms();
    if (!mounted) return;
    final changed = await showFindReplace(context, widget.service, widget.book);
    if (changed && mounted) setChangedString('{}');
  }

  Future<void> _leave() async {
    await _flushForms();
    if (await confirmLeave(context, widget.service, widget.book) && mounted) {
      Navigator.of(context).pop();
    }
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

  Future<void> _onFab() async {
    if (_toDelete.keys.length > 0) {
      return _removeSelectedSections();
    }
    String? title = await prompt(
      context,
      title: Text(widget.service.translate(LangTranslateItems.bookPagePromptEnterName)),
      textOK: Text(widget.service.translate(LangTranslateItems.buttonSave)),
      textCancel: Text(widget.service.translate(LangTranslateItems.buttonCancel)),
      autoFocus: true,
      obscureText: false,
      obscuringCharacter: '•',
      textCapitalization: TextCapitalization.words,
    );
    if (title != null) {
      setState(() {
        widget.book.addSection(title);
      });
      setChangedString('{}');
      final snackBar = SnackBar(
          content: Text(
              '$title ${widget.service.translate(LangTranslateItems.messageCreated)}'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = widget.service;
    final book = widget.book;
    final autoSave = stringToBool(s.getSettings()["auto-save"]) ?? false;
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
      key: _scaffoldKey,
      appBar: appBarFor(
        context,
        title: Row(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image(
                  image: s.base64Image(book.getImageBySectionId('cover'), true),
                  width: 28,
                  height: 40,
                  fit: BoxFit.cover)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trimSpecialChar(book.bookTitle, ' '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
              Text(book.getAuthor(), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
            ]),
          ),
        ]),
        actions: [
          IconButton(
              tooltip: tr(s, 'Find and replace', 'Поиск и замена'),
              icon: const Icon(Icons.find_replace),
              onPressed: _findReplace),
          IconButton(
              tooltip: tr(s, 'Help', 'Справка'),
              icon: const Icon(Icons.help_outline),
              onPressed: () => openHelp(context, s)),
          IconButton(
              tooltip: tr(s, autoSave ? 'Auto-save: on' : 'Auto-save: off',
                  autoSave ? 'Автосохранение: вкл' : 'Автосохранение: выкл'),
              icon: Icon(Icons.auto_awesome, color: autoSave ? Colors.green : null),
              onPressed: () async {
                await s.setSettings({"auto-save": !autoSave});
                setChangedString('{}');
              }),
          IconButton(
              tooltip: s.translate(LangTranslateItems.buttonSave),
              icon: const Icon(Icons.save_outlined),
              onPressed: () => setChangedString('{}')),
          IconButton(
              tooltip: tr(s, 'Export .fb2', 'Экспорт .fb2'),
              icon: const Icon(Icons.storage_outlined),
              onPressed: _export),
        ],
        bottom: TabBar(
          onTap: (_) => setChangedString('{}'),
          controller: controller,
          tabs: [
            Tab(text: s.translate(LangTranslateItems.bookPageInfo)),
            Tab(text: s.translate(LangTranslateItems.bookPageSection)),
          ],
        ),
      ),
      body: TabBarView(controller: controller, children: [
        BookComponent(s, book, changeController!.stream.asBroadcastStream()),
        SectionList(s, book, changeController!.stream.asBroadcastStream(), _markToDelete),
      ]),
      floatingActionButton: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          if (controller.index != 1) return const SizedBox.shrink();
          final deleting = _toDelete.isNotEmpty;
          return FloatingActionButton.extended(
            heroTag: 'bookPage',
            backgroundColor: deleting ? t.colorScheme.error : null,
            foregroundColor: deleting ? t.colorScheme.onError : null,
            icon: Icon(deleting ? Icons.delete_outline : Icons.add),
            label: Text(deleting
                ? tr(s, 'Delete ${_toDelete.length}', 'Удалить ${_toDelete.length}')
                : tr(s, 'New section', 'Новый раздел')),
            onPressed: _onFab,
          );
        },
      ),
    ));
  }
}
