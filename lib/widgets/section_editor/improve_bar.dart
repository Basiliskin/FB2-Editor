import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/improvement.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/network_message.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/widgets/section_editor/diff_text.dart';
import 'package:quill_fb2/widgets/section_editor/improve_controller.dart';

String _errorText(AppService s, ImproveController c) {
  final detail = c.errorDetail.isEmpty ? '' : ' (${c.errorDetail})';
  switch (c.error!) {
    case ImproveError.invalidKey:
      return tr(s, 'The provider rejected the API key', 'Провайдер отклонил API-ключ');
    case ImproveError.rateLimited:
      return tr(s, 'Rate limit reached, try again later',
          'Лимит запросов исчерпан, попробуйте позже');
    case ImproveError.network:
      return networkMessage(s, web: kIsWeb, baseUrl: c.current?.baseUrl ?? '');
    case ImproveError.badResponse:
      return tr(s, 'The provider sent an unusable answer$detail',
          'Провайдер прислал непригодный ответ$detail');
    case ImproveError.rejected:
      return tr(s, 'The suggestion was discarded: $detail',
          'Предложение отброшено: $detail');
    case ImproveError.truncated:
      return tr(
          s,
          'The answer was cut off. Lower the chunk limit in the provider settings',
          'Ответ оборвался. Уменьшите лимит фрагмента в настройках провайдера');
    case ImproveError.nothing:
      return tr(s, 'Nothing to change in the chosen paragraphs',
          'В выбранных абзацах нечего менять');
    case ImproveError.tooLarge:
      return tr(s, 'A single paragraph is too long to send',
          'Один из абзацев слишком длинный для отправки');
  }
}

Future<bool> confirmSend(BuildContext context, AppService s, Provider p,
    int paragraphs, int tokens, int requests) async {
  final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
            title: Text(tr(s, 'Send text to a provider?', 'Отправить текст провайдеру?')),
            content: Text(tr(
                s,
                '$paragraphs paragraph(s), about $tokens tokens, will be sent to '
                    '${p.name} (${p.model}) using your API key'
                    '${requests > 1 ? ', in $requests requests' : ''}. Text is only sent when you ask.',
                '$paragraphs абз., около $tokens токенов, будут отправлены в '
                    '${p.name} (${p.model}) с вашим API-ключом'
                    '${requests > 1 ? ', $requests запросами' : ''}. Текст уходит только по вашему запросу.')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr(s, 'Cancel', 'Отмена'))),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr(s, 'Send', 'Отправить'))),
            ],
          ));
  return ok == true;
}

/// Bottom command bar: provider, chosen paragraphs, presets and a free instruction.
class ImproveBar extends StatefulWidget {
  final AppService service;
  final ImproveController controller;
  final VoidCallback onManageProviders;
  const ImproveBar(
      {super.key,
      required this.service,
      required this.controller,
      required this.onManageProviders});
  @override
  State<ImproveBar> createState() => _ImproveBarState();
}

class _ImproveBarState extends State<ImproveBar> {
  final _text = TextEditingController();
  AppService get _s => widget.service;
  ImproveController get _c => widget.controller;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _ask(String instruction) => _c.ask(
      instruction, (p, n, t, r) => confirmSend(context, _s, p, n, t, r));

  Future<void> _editStyleNote() async {
    final saved = await showDialog<String>(
        context: context, builder: (_) => _StyleNoteDialog(_s, _c.styleNote));
    if (saved != null) await _c.setStyleNote(saved);
  }

  /// Creates a preset (or edits [existing]); [prefill] seeds the instruction.
  Future<void> _editPreset([Preset? existing, String prefill = '']) async {
    final result = await showDialog<(String, Preset?)>(
        context: context,
        builder: (_) => _PresetDialog(_s, existing, prefill));
    if (result == null) return;
    if (result.$1 == 'save') {
      await _c.savePreset(result.$2!);
    } else {
      await _c.deletePreset(existing!.id);
    }
  }

  Future<void> _translate() async {
    final r = await showDialog<({String name, String code, bool whole})>(
        context: context,
        builder: (_) => _TranslateDialog(_s, !_c.allSelected));
    if (r == null) return;
    if (r.whole) _c.selectAll();
    await _c.translate(r.name, r.code,
        (p, n, t, q) => confirmSend(context, _s, p, n, t, q));
  }

  void _pickProvider() {
    showModalBottomSheet(
        context: context,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final p in _c.providers)
                ListTile(
                  leading: Icon(p.id == _c.current?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  title: Text(p.name),
                  subtitle: Text('${p.vendor.name} · ${p.model}'),
                  onTap: () {
                    _c.selectProvider(p);
                    Navigator.pop(sheet);
                  },
                ),
              const Divider(),
              ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(tr(_s, 'Manage providers...', 'Управление провайдерами...')),
                  onTap: () {
                    Navigator.pop(sheet);
                    widget.onManageProviders();
                  }),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final p = _c.current;
          final n = _c.eligible.length;
          return Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_c.busy)
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            if (_c.chunks > 1 && !_c.translating)
                              Text(tr(_s, 'Part ${_c.chunk} of ${_c.chunks}',
                                  'Часть ${_c.chunk} из ${_c.chunks}')),
                            const LinearProgressIndicator(),
                          ])),
                      TextButton(
                          onPressed: _c.cancel,
                          child: Text(tr(_s, 'Cancel', 'Отмена'))),
                    ]),
                  if (_c.error != null)
                    Row(children: [
                      Icon(Icons.error_outline, color: cs.error, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(_errorText(_s, _c),
                              style: TextStyle(color: cs.error))),
                      if (_c.canResume)
                        TextButton(
                            onPressed: () => _c.resume(),
                            child: Text(tr(_s, 'Retry', 'Повторить'))),
                      if (_c.error == ImproveError.invalidKey)
                        TextButton(
                            onPressed: widget.onManageProviders,
                            child: Text(tr(_s, 'Edit provider', 'Провайдер'))),
                    ]),
                  if (_c.translating)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              for (final part in _c.parts)
                                Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Chip(
                                        avatar: _partIcon(part.status, cs),
                                        label: Text('${part.number}'))),
                            ]))),
                  if (_c.titleSuggestion != null)
                    Row(children: [
                      Expanded(
                          child: Text(
                              tr(_s, 'Title: ${_c.titleSuggestion}',
                                  'Заголовок: ${_c.titleSuggestion}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)),
                      IconButton(
                          tooltip: tr(_s, 'Accept title', 'Принять заголовок'),
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: _c.acceptTitle),
                      IconButton(
                          tooltip: tr(_s, 'Reject title', 'Отклонить заголовок'),
                          icon: Icon(Icons.close, color: cs.error),
                          onPressed: _c.rejectTitle),
                    ]),
                  if (p == null)
                    Row(children: [
                      Expanded(
                          child: Text(tr(
                              _s,
                              'Connect an AI provider to improve your text.',
                              'Подключите ИИ-провайдера, чтобы улучшать текст.'))),
                      FilledButton(
                          onPressed: widget.onManageProviders,
                          child: Text(tr(_s, 'Add provider', 'Добавить'))),
                      IconButton(
                          tooltip: tr(_s, 'Close', 'Закрыть'),
                          icon: const Icon(Icons.close),
                          onPressed: _c.close),
                    ])
                  else ...[
                    Wrap(spacing: 8, children: [
                      ActionChip(
                          avatar: const Icon(Icons.vpn_key_outlined, size: 16),
                          label: Text(p.name),
                          onPressed: _pickProvider),
                      ActionChip(
                          avatar: const Icon(Icons.format_list_numbered, size: 16),
                          label: Text(tr(
                              _s,
                              _c.noneSelected
                                  ? 'No paragraphs (select all)'
                                  : _c.start == _c.end
                                      ? 'Paragraph ${_c.start + 1}'
                                      : 'Paragraphs ${_c.start + 1}-${_c.end + 1}',
                              _c.noneSelected
                                  ? 'Ничего не выбрано (выбрать все)'
                                  : _c.start == _c.end
                                      ? 'Абзац ${_c.start + 1}'
                                      : 'Абзацы ${_c.start + 1}-${_c.end + 1}')),
                          // one tap selects everything, the next clears it
                          onPressed: _c.allSelected ? _c.clearSelection : _c.selectAll),
                      if (n > 0) Chip(label: Text('~${_c.tokenEstimate} tokens')),
                    ]),
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final pr in _c.presets)
                            Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onLongPress: pr.custom ? () => _editPreset(pr) : null,
                                  child: ActionChip(
                                      label: Text(pr.name),
                                      onPressed: _c.busy
                                          ? null
                                          : () => _ask(pr.instruction)),
                                )),
                          Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                  avatar: const Icon(Icons.translate, size: 16),
                                  label: Text(tr(_s, 'Translate...', 'Перевести...')),
                                  onPressed: _c.busy ? null : _translate)),
                          Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                  avatar: const Icon(Icons.add, size: 16),
                                  label: Text(tr(_s, 'New preset', 'Новый шаблон')),
                                  onPressed: () => _editPreset(null, _text.text.trim()))),
                          if (_c.suggestions.length > 1)
                            FilledButton(
                                onPressed: () => _c.accept(_c.suggestions.keys.toList()),
                                child: Text(_c.translating
                                    ? tr(_s, 'Accept ready', 'Принять готовое')
                                    : tr(_s, 'Accept all', 'Принять все'))),
                        ])),
                    Row(children: [
                      const Icon(Icons.auto_awesome, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _text,
                              decoration: InputDecoration(
                                  hintText: tr(
                                      _s,
                                      'Tap paragraphs to choose, then ask...',
                                      'Выберите абзацы и задайте задачу...'),
                                  border: InputBorder.none),
                              onSubmitted: (v) {
                                if (v.trim().isNotEmpty) _ask(v.trim());
                              })),
                      IconButton(
                          tooltip: tr(_s, 'Style note', 'Стиль книги'),
                          icon: Icon(_c.styleNote.isEmpty
                              ? Icons.brush_outlined
                              : Icons.brush),
                          onPressed: _editStyleNote),
                      IconButton(
                          tooltip: tr(_s, 'Close', 'Закрыть'),
                          icon: const Icon(Icons.close),
                          onPressed: _c.close),
                    ]),
                  ],
                ]),
              ),
            ),
          );
        });
  }
}

/// A pending Suggestion shown under its paragraph.
class SuggestionCard extends StatelessWidget {
  final AppService service;
  final ImproveController controller;
  final int index;
  final String before;
  const SuggestionCard(
      {super.key,
      required this.service,
      required this.controller,
      required this.index,
      required this.before});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 8),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.primary, width: 3)),
          color: cs.surfaceContainerHighest),
      child: Row(children: [
        Expanded(child: DiffText(before, controller.suggestions[index] ?? '')),
        IconButton(
            tooltip: tr(service, 'Accept', 'Принять'),
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () => controller.accept([index])),
        IconButton(
            tooltip: tr(service, 'Reject', 'Отклонить'),
            icon: Icon(Icons.close, color: cs.error),
            onPressed: () => controller.reject(index)),
      ]),
    );
  }
}

class _StyleNoteDialog extends StatefulWidget {
  final AppService service;
  final String note;
  const _StyleNoteDialog(this.service, this.note);
  @override
  State<_StyleNoteDialog> createState() => _StyleNoteDialogState();
}

class _StyleNoteDialogState extends State<_StyleNoteDialog> {
  late final _ctl = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return AlertDialog(
      title: Text(tr(s, 'Style note for this book', 'Стиль этой книги')),
      content: TextField(
          controller: _ctl,
          maxLines: 4,
          decoration: InputDecoration(
              hintText: tr(s, 'e.g. keep the 19th-century tone',
                  'например: сохранять тон XIX века'))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(s, 'Cancel', 'Отмена'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctl.text),
            child: Text(tr(s, 'Save', 'Сохранить'))),
      ],
    );
  }
}

/// Pops ('save', preset) or ('delete', null); null when cancelled.
class _PresetDialog extends StatefulWidget {
  final AppService service;
  final Preset? existing;
  final String prefill;
  const _PresetDialog(this.service, this.existing, this.prefill);
  @override
  State<_PresetDialog> createState() => _PresetDialogState();
}

class _PresetDialogState extends State<_PresetDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _text = TextEditingController(
      text: widget.existing?.instruction ?? widget.prefill);

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return AlertDialog(
      title: Text(tr(s, 'Preset', 'Шаблон')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr(s, 'Name', 'Название'))),
        TextField(
            controller: _text,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration:
                InputDecoration(labelText: tr(s, 'Instruction', 'Инструкция'))),
      ]),
      actions: [
        if (widget.existing != null)
          TextButton(
              onPressed: () => Navigator.pop(context, ('delete', null)),
              child: Text(tr(s, 'Delete', 'Удалить'))),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(s, 'Cancel', 'Отмена'))),
        FilledButton(
            onPressed: _name.text.trim().isEmpty || _text.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    (
                      'save',
                      Preset(_name.text.trim(), _text.text.trim(),
                          id: widget.existing?.id ?? getRandomString(8))
                    )),
            child: Text(tr(s, 'Save', 'Сохранить'))),
      ],
    );
  }
}

/// Asks for the target language and whether to take the whole Section.
class _TranslateDialog extends StatefulWidget {
  final AppService service;
  final bool offerWhole;
  const _TranslateDialog(this.service, this.offerWhole);
  @override
  State<_TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<_TranslateDialog> {
  static const _other = '';
  String _code = translationLanguages.first.code;
  // off unless asked for: translating only what was selected is the default
  bool _whole = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _language => _code == _other
      ? _name.text.trim()
      : translationLanguages.firstWhere((l) => l.code == _code).name;

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return AlertDialog(
      title: Text(tr(s, 'Translate into', 'Перевести на')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(
            value: _code,
            isExpanded: true,
            items: [
              for (final l in translationLanguages)
                DropdownMenuItem(value: l.code, child: Text('${l.name} (${l.code})')),
              DropdownMenuItem(
                  value: _other, child: Text(tr(s, 'Other...', 'Другой...'))),
            ],
            onChanged: (v) => setState(() => _code = v!)),
        if (_code == _other)
          TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: tr(s, 'Language (in English)', 'Язык (по-английски)'))),
        if (widget.offerWhole)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(s, 'Whole Section', 'Весь раздел')),
              value: _whole,
              onChanged: (v) => setState(() => _whole = v)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(s, 'Cancel', 'Отмена'))),
        FilledButton(
            onPressed: _language.isEmpty
                ? null
                : () => Navigator.pop(
                    context, (name: _language, code: _code, whole: _whole)),
            child: Text(tr(s, 'Translate', 'Перевести'))),
      ],
    );
  }
}

Widget _partIcon(PartStatus status, ColorScheme cs) => switch (status) {
      PartStatus.ready => const Icon(Icons.check_circle, size: 16, color: Colors.green),
      PartStatus.handled => Icon(Icons.done_all, size: 16, color: cs.outline),
      PartStatus.failed => Icon(Icons.refresh, size: 16, color: cs.error),
      PartStatus.running => const SizedBox(
          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      PartStatus.waiting => Icon(Icons.hourglass_empty, size: 16, color: cs.outline),
    };

/// Header above the first paragraph of a translated part, with its own actions.
class PartHeader extends StatelessWidget {
  final AppService service;
  final ImproveController controller;
  final TranslationPart part;
  const PartHeader(
      {super.key,
      required this.service,
      required this.controller,
      required this.part});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final failed = part.status == PartStatus.failed;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(left: 8),
      color: failed ? cs.errorContainer : cs.surfaceContainerHighest,
      child: Row(children: [
        Text(tr(service, 'Part ${part.number}', 'Часть ${part.number}'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (failed)
          Expanded(
              child: Text('  ·  ${_errorText(service, controller)}'.split('\n').first,
                  maxLines: 1, overflow: TextOverflow.ellipsis))
        else
          const Spacer(),
        if (failed && controller.canResume)
          TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: () => controller.resume(),
              label: Text(tr(service, 'Retry', 'Повторить'))),
        if (part.status == PartStatus.ready) ...[
          TextButton(
              onPressed: () => controller.rejectPart(part.number),
              child: Text(tr(service, 'Reject', 'Отклонить'))),
          FilledButton(
              onPressed: () => controller.acceptPart(part.number),
              child: Text(tr(service, 'Accept', 'Принять'))),
        ],
      ]),
    );
  }
}

/// A translated paragraph beside its original (two columns).
class TranslationPair extends StatelessWidget {
  final String before;
  final String after;
  final TextStyle style;
  const TranslationPair(
      {super.key, required this.before, required this.after, required this.style});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(before, style: style.copyWith(color: cs.outline))),
          const SizedBox(width: 12),
          Expanded(child: Text(after, style: style)),
        ]));
  }
}
