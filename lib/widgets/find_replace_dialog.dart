import 'package:flutter/material.dart';
import 'package:quill_fb2/models/find_replace.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/voice/dictation_target.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/voice/dictation_button.dart';

/// Book-wide find and replace. Returns true when the book was changed.
Future<bool> showFindReplace(
    BuildContext context, AppService service, ProjectModel book) async {
  final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FindReplaceSheet(service, book));
  return changed ?? false;
}

class FindReplaceSheet extends StatefulWidget {
  final AppService service;
  final ProjectModel book;
  const FindReplaceSheet(this.service, this.book, {super.key});
  @override
  State<FindReplaceSheet> createState() => _FindReplaceSheetState();
}

class _FindReplaceSheetState extends State<FindReplaceSheet> {
  final _find = TextEditingController();
  final _replace = TextEditingController();
  bool _matchCase = false;
  bool _changed = false;
  String? _done;
  List<FindHit> _hits = [];

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  void _search() => setState(() {
        _done = null;
        _hits = findText(widget.book.section, _find.text, matchCase: _matchCase);
      });

  void _apply(List<FindHit>? only) {
    final n = replaceText(widget.book.section, _find.text, _replace.text,
        matchCase: _matchCase, hits: only);
    _changed = _changed || n > 0;
    setState(() {
      _hits = findText(widget.book.section, _find.text, matchCase: _matchCase);
      _done = tr(widget.service, 'Replaced: $n', 'Заменено: $n');
    });
  }

  String _where(FindHit h) {
    final s = widget.book.section[h.section];
    final name = s.title.isEmpty ? '#${h.section + 1}' : s.title;
    return h.paragraph == FindHit.titleIndex
        ? tr(widget.service, '$name (title)', '$name (заголовок)')
        : name;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final total = _hits.fold<int>(0, (a, h) => a + h.count);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(children: [
            TextField(
                controller: _find,
                autofocus: true,
                onChanged: (_) => _search(),
                decoration: InputDecoration(
                    labelText: tr(s, 'Find', 'Найти'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: DictationButton(
                        service: s,
                        target: TextFieldDictationTarget(_find),
                        onInserted: _search))),
            const SizedBox(height: 8),
            TextField(
                controller: _replace,
                decoration: InputDecoration(
                    labelText: tr(s, 'Replace with', 'Заменить на'),
                    prefixIcon: const Icon(Icons.find_replace),
                    suffixIcon: DictationButton(
                        service: s,
                        target: TextFieldDictationTarget(_replace)))),
            Row(children: [
              Expanded(
                  child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(tr(s, 'Match case', 'Учитывать регистр')),
                      value: _matchCase,
                      onChanged: (v) {
                        _matchCase = v ?? false;
                        _search();
                      })),
              FilledButton(
                  onPressed: _hits.isEmpty ? null : () => _apply(null),
                  child: Text(tr(s, 'Replace all', 'Заменить все'))),
            ]),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    _done ??
                        (_find.text.isEmpty
                            ? ''
                            : tr(s, 'Found: $total in ${_hits.length} places',
                                'Найдено: $total в ${_hits.length} местах')),
                    style: Theme.of(context).textTheme.bodySmall)),
          ]),
        ),
        Flexible(
          child: ListView.builder(
              shrinkWrap: true,
              itemCount: _hits.length,
              itemBuilder: (_, i) {
                final h = _hits[i];
                return ListTile(
                    dense: true,
                    title: Text(h.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_where(h)),
                    trailing: TextButton(
                        onPressed: () => _apply([h]),
                        child: Text(tr(s, 'Replace', 'Заменить'))));
              }),
        ),
        Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.of(context).pop(_changed),
                    child: Text(tr(s, 'Close', 'Закрыть'))))),
      ]),
    );
  }
}
