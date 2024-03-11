import 'package:flutter/material.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';

class SectionTitle extends StatefulWidget {
  final String title;
  final Function(String) onTextSubmitted;
  SectionTitle(this.title, this.onTextSubmitted);
  @override
  _SectionTitleState createState() => _SectionTitleState();
}

class _SectionTitleState extends State<SectionTitle> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
        initialValue: widget.title,
        onFieldSubmitted: (text) => setState(() {
              widget.onTextSubmitted(text);
            }),
        decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: widget.title,
            isDense: true, // Added this
            contentPadding: EdgeInsets.all(8)));
  }
}

class SectionList extends StatefulWidget {
  final ProjectModel book;
  final AppService service;
  final Stream<void>? triggerSave;
  final Function(Section) onMarkToDelete;
  SectionList(this.service, this.book, this.triggerSave, this.onMarkToDelete);
  @override
  _SectionListState createState() => _SectionListState();
}

class _SectionListState extends State<SectionList> with WidgetsBindingObserver {
  late List<Section> items;
  Map<String, bool> _isDeleted = {};
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    items = widget.book.section;
    widget.triggerSave!.listen((event) {
      try {
        print('SectionListState.triggerSave');
        widget.service.saveProject(widget.book);
      } catch (e) {
        print(e);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Map settings = widget.service.getSettings();
    bool autoSave = stringToBool(settings["auto-save"]) ?? false;
    print('section.state = ${state.name} - autoSave=$autoSave');
    print(autoSave);
  }

  void onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    setState(() {
      Section section = items[oldIndex];

      items.removeAt(oldIndex);
      items.insert(newIndex, section);
    });
    widget.service.saveProject(widget.book);
  }

  _getListItems() => items
      .asMap()
      .map((i, item) => MapEntry(i, _buildTenableListTile(item, i)))
      .values
      .toList();

  _changeTitle(item, text) {
    item.title = text;
    // widget.service.saveProject(widget.book);
  }

  Widget _buildTenableListTile(Section item, int index) {
    return Dismissible(
      key: Key(item.sectionId),
      onDismissed: (direction) {
        setState(() {
          items.removeAt(index);
        });
      },
      background: Container(color: Colors.red),
      child: ListTile(
        key: ValueKey(item.sectionId),
        title: Row(
          children: [
            Expanded(
                flex: 1,
                child: MaterialButton(
                  onPressed: () {
                    final isDeleted = widget.onMarkToDelete(item);
                    setState(() {
                      if (isDeleted)
                        _isDeleted[item.sectionId] = isDeleted;
                      else
                        _isDeleted.remove(item.sectionId);
                    });
                  },
                  color: _isDeleted.containsKey(item.sectionId)
                      ? Colors.red
                      : Colors.blue,
                  textColor: Colors.white,
                  child: Icon(
                    _isDeleted.containsKey(item.sectionId)
                        ? Icons.remove
                        : Icons.delete,
                    size: 32,
                  ),
                  padding: EdgeInsets.all(2),
                  shape: CircleBorder(),
                )),
            Expanded(
                flex: 6,
                child: SectionTitle(trimSpecialChar(item.title, ' '),
                    (text) => {_changeTitle(item, text)})),
            Expanded(
                flex: 1,
                child: MaterialButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SectionEditor(widget.service, widget.book, item),
                      ),
                    ).then((value) => setState(() {}));
                  },
                  color: Colors.blue,
                  textColor: Colors.white,
                  child: Icon(
                    Icons.edit,
                    size: 18,
                  ),
                  padding: EdgeInsets.all(2),
                  shape: CircleBorder(),
                ))
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    items = widget.book.section;
    return SingleChildScrollView(
        child: SafeArea(
            child: Container(
                child: Column(children: <Widget>[
      Container(
          height: 500,
          child: ReorderableListView(
            onReorder: onReorder,
            children: _getListItems(),
          )) //_content(context)
    ]))));
  }
}
