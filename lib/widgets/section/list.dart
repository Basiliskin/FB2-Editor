import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quill_fb2/widgets/story_map/section_sheet.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/section_editor/editor.dart';
import 'package:quill_fb2/ui/widgets.dart';

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
  StreamSubscription<void>? _triggerSub;
  late List<Section> items;
  Map<String, bool> _isDeleted = {};
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    items = widget.book.section;
    _triggerSub = widget.triggerSave!.listen((event) {
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
    _triggerSub?.cancel();
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

  _changeTitle(item, text) {
    item.title = text;
    // widget.service.saveProject(widget.book);
  }

  // a swipe while scrolling must not silently remove a whole chapter
  Future<bool> _confirmDelete(Section item) async {
    final name = trimSpecialChar(item.title, ' ').trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(widget.service, 'Delete section?', 'Удалить раздел?')),
        content: name.isEmpty ? null : Text(name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('${widget.service.translate(LangTranslateItems.buttonCancel)}')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(widget.service, 'Delete', 'Удалить'))),
        ],
      ),
    );
    return ok ?? false;
  }

  Widget _tile(Section item, int index) {
    final t = Theme.of(context);
    final marked = _isDeleted.containsKey(item.sectionId);
    void toggle() {
      final isDeleted = widget.onMarkToDelete(item);
      setState(() {
        if (isDeleted) {
          _isDeleted[item.sectionId] = isDeleted;
        } else {
          _isDeleted.remove(item.sectionId);
        }
      });
    }

    void edit() => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  SectionEditor(widget.service, widget.book, item)),
        ).then((value) => setState(() {}));

    return Dismissible(
      key: Key(item.sectionId),
      confirmDismiss: (_) => _confirmDelete(item),
      onDismissed: (direction) => setState(() => items.removeAt(index)),
      background: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              color: t.colorScheme.error, borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          child: Icon(Icons.delete_outline, color: t.colorScheme.onError)),
      child: Card(
        key: ValueKey(item.sectionId),
        margin: const EdgeInsets.only(bottom: 8),
        color: marked ? t.colorScheme.errorContainer.withValues(alpha: .5) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            // tap the number to select for bulk delete (replaces the blue trash circle)
            Tooltip(
              message: tr(widget.service, 'Select', 'Выбрать'),
              child: InkResponse(
                onTap: toggle,
                child: CircleAvatar(
                    radius: 18,
                    backgroundColor: marked
                        ? t.colorScheme.error
                        : t.colorScheme.primaryContainer,
                    child: marked
                        ? Icon(Icons.check, size: 18, color: t.colorScheme.onError)
                        : Text('${index + 1}',
                            style: TextStyle(color: t.colorScheme.onPrimaryContainer))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextFormField(
                    initialValue: trimSpecialChar(item.title, ' '),
                    onFieldSubmitted: (text) => setState(() => _changeTitle(item, text)),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                        border: InputBorder.none, isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4))),
                Text('${item.p.length} ${tr(widget.service, 'paragraphs', 'абзацев')}',
                    style: t.textTheme.bodySmall),
                SectionCastLine(widget.book, item),
              ]),
            ),
            IconButton(
                tooltip: tr(widget.service, 'Edit text', 'Редактировать'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: edit),
            ReorderableDragStartListener(
                index: index,
                child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    items = widget.book.section;
    {
      return PageBody(
          child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        buildDefaultDragHandles: false,
        itemCount: items.length,
        onReorder: onReorder,
        itemBuilder: (c, i) => _tile(items[i], i),
      ));
    }
  }
}
