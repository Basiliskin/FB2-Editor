import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/book_ask.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart' show plain;
import 'package:quill_fb2/services/voice/dictation_target.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/markdown_lite.dart';
import 'package:quill_fb2/widgets/stop_run_dialog.dart';
import 'package:quill_fb2/widgets/voice/dictation_button.dart';

/// The text of every Section of [book] with text, numbered by its place in the book.
List<AskSection> askSectionsOf(ProjectModel book) => [
      for (var i = 0; i < book.section.length; i++)
        AskSection(i + 1, book.section[i].title.trim(), [
          for (final p in book.section[i].p)
            if (plain(book.section[i].editableText(p)).trim().isNotEmpty) plain(book.section[i].editableText(p)).trim()
        ])
    ];

/// The language the model writes in: the book's own, else the app's.
String bookLanguageOf(AppService s, ProjectModel book) {
  final code = book.lang.trim();
  if (code.isNotEmpty) return code;
  return s.getSettings()['language'] == 'ru' ? 'ru' : 'en';
}

/// Summarise a range of Sections or ask the book a question. Read-only: the answer is
/// shown, never applied.
class AskPage extends StatefulWidget {
  final AppService service;
  final ProjectModel book;
  final http.Client Function() httpFactory;
  AskPage(this.service, this.book, {super.key, http.Client Function()? httpFactory})
      : httpFactory = httpFactory ?? http.Client.new;
  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> {
  AppService get _s => widget.service;
  late final List<AskSection> _all = askSectionsOf(widget.book);
  final _question = TextEditingController();
  AskMode _mode = AskMode.summarise;
  int _from = 1, _to = 1;
  Provider? _provider;
  bool _loaded = false, _busy = false;
  int _done = 0;
  int _run = 0;
  http.Client? _client;
  AskAnswer? _answer;
  List<AskSection> _sentSections = const [];
  String? _error;

  String get _language => bookLanguageOf(_s, widget.book);

  @override
  void initState() {
    super.initState();
    _to = _all.isEmpty ? 1 : _all.length;
    _s.providerStore.defaultProvider().then((p) {
      if (mounted) {
        setState(() {
          _provider = p;
          _loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _run++;
    _client?.close();
    _question.dispose();
    super.dispose();
  }

  List<AskSection> get _range => [for (final x in _all) if (x.number >= _from && x.number <= _to && x.paragraphs.isNotEmpty) x];

  /// The plan the running request was started with; the live plan shrinks as Digests get cached.
  AskPlan? _runPlan;

  AskPlan? get _plan {
    final p = _provider;
    if (p == null || _range.isEmpty) return null;
    return BookAsk.plan(_range, _mode, _question.text.trim(), p.chunkChars, _s.digestStore, _language);
  }

  bool get _canRun => !_busy && _plan != null && (_mode == AskMode.summarise || _question.text.trim().isNotEmpty);

  String _failure(LlmException e) => switch (e.failure) {
        LlmFailure.invalidKey => tr(_s, 'The provider rejected the API key', 'Провайдер отклонил API-ключ'),
        LlmFailure.rateLimited => tr(_s, 'Rate limit reached, try again later', 'Лимит запросов исчерпан, попробуйте позже'),
        LlmFailure.network => tr(_s, 'No connection to the provider', 'Нет связи с провайдером'),
        LlmFailure.badResponse => tr(_s, 'The provider sent an unusable answer', 'Провайдер прислал непригодный ответ'),
      };

  Future<void> _go() async {
    final provider = _provider, plan = _plan;
    if (provider == null || plan == null) return;
    final sections = _range;
    if (plan.requests > 1 || sections.length > 1 || !_s.providerStore.isConsented(provider.id)) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text(tr(_s, 'Send text to a provider?', 'Отправить текст провайдеру?')),
                content: Text(tr(
                    _s,
                    '${sections.length} section(s), about ${plan.characters} characters in ${plan.requests} request(s), '
                        'will be sent to ${provider.name} (${provider.model}) using your API key. '
                        '${plan.direct ? '' : 'Sections are summarised first; summaries already made are reused. '}'
                        'Nothing in your book is changed.',
                    '${sections.length} раздел(ов), около ${plan.characters} символов в ${plan.requests} запрос(ах), '
                        'будут отправлены в ${provider.name} (${provider.model}) с вашим API-ключом. '
                        '${plan.direct ? '' : 'Сначала разделы сжимаются в краткие пересказы; готовые используются повторно. '}'
                        'Ваша книга не меняется.')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(_s, 'Cancel', 'Отмена'))),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(_s, 'Send', 'Отправить'))),
                ],
              ));
      if (ok != true || !mounted) return;
      await _s.providerStore.consent(provider.id);
    }
    final mine = ++_run;
    setState(() {
      _busy = true;
      _done = 0;
      _answer = null;
      _error = null;
      _sentSections = sections;
      _runPlan = plan;
    });
    final client = _client = widget.httpFactory();
    try {
      final answer = await BookAskRunner(createLlmClient(provider, client), _s.digestStore, _language)
          .run(plan, sections, onRequest: (n) => mine == _run && mounted ? setState(() => _done = n) : null);
      if (mine != _run) return;
      setState(() => _answer = answer);
    } on LlmException catch (e) {
      if (mine != _run) return;
      setState(() => _error = _failure(e));
    } finally {
      client.close();
      if (mine == _run && mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    _run++;
    _client?.close();
    setState(() => _busy = false);
  }

  String _label(AskSection x) {
    if (x.title.isEmpty) return '${x.number}. ${tr(_s, 'Section ${x.number}', 'Раздел ${x.number}')}';
    // many titles already carry their own number ("1. Начало"): do not number them twice
    return RegExp(r'^\d').hasMatch(x.title) ? x.title : '${x.number}. ${x.title}';
  }

  Widget _picker(String label, int value, ValueChanged<int> onChanged) => DropdownButtonFormField<int>(
      key: ValueKey('$label$value'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [for (final x in _all) DropdownMenuItem(value: x.number, child: Text(_label(x), overflow: TextOverflow.ellipsis))],
      onChanged: _busy ? null : (v) => onChanged(v!));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final plan = _busy ? _runPlan : _plan;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmStopRun(context, _s) && mounted) {
          _cancel();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(title: Text(tr(_s, 'Ask about the book', 'Вопрос о книге'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_provider == null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(tr(_s, 'Connect an AI provider in Settings to ask about your book.',
                              'Подключите ИИ-провайдера в настройках, чтобы задавать вопросы о книге.'))),
                    ])),
              SegmentedButton<AskMode>(
                  segments: [
                    ButtonSegment(value: AskMode.summarise, label: Text(tr(_s, 'Summarise', 'Пересказ'))),
                    ButtonSegment(value: AskMode.question, label: Text(tr(_s, 'Ask', 'Вопрос'))),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy ? null : (v) => setState(() => _mode = v.first)),
              const SizedBox(height: 12),
              _picker(tr(_s, 'From', 'С'), _from, (v) => setState(() {
                    _from = v;
                    if (_to < v) _to = v;
                  })),
              const SizedBox(height: 12),
              _picker(tr(_s, 'To', 'По'), _to, (v) => setState(() {
                    _to = v;
                    if (_from > v) _from = v;
                  })),
              const SizedBox(height: 12),
              if (_mode == AskMode.question)
                TextField(
                    controller: _question,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        suffixIcon: DictationButton(
                            service: _s,
                            target: TextFieldDictationTarget(_question),
                            onInserted: () => setState(() {})),
                        labelText: tr(_s, 'Your question', 'Ваш вопрос'),
                        hintText: tr(_s, 'e.g. Why does Артур leave the port?', 'например: почему Артур покидает порт?'))),
              const SizedBox(height: 12),
              if (plan != null)
                Text(
                    plan.direct
                        ? tr(_s, 'About ${plan.characters} characters, 1 request. The model reads the text itself.',
                            'Около ${plan.characters} символов, 1 запрос. Модель читает сам текст.')
                        : tr(
                            _s,
                            'About ${plan.characters} characters, ${plan.requests} request${plan.requests == 1 ? '' : 's'}. Too long for one request, '
                                'so it works from short summaries of each section'
                                '${_mode == AskMode.question ? '; narrow the range for an exact answer' : ''}.',
                            'Около ${plan.characters} символов, запросов: ${plan.requests}. Слишком длинно для одного запроса, '
                                'поэтому используются краткие пересказы разделов'
                                '${_mode == AskMode.question ? '; сузьте диапазон для точного ответа' : ''}.'),
                    style: t.bodySmall),
              const SizedBox(height: 12),
              if (_busy)
                Row(children: [
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(_s, 'Request ${_done + 1} of ${plan == null || _done + 1 > plan.requests ? _done + 1 : plan.requests}',
                        'Запрос ${_done + 1} из ${plan == null || _done + 1 > plan.requests ? _done + 1 : plan.requests}')),
                    const LinearProgressIndicator(),
                  ])),
                  TextButton(onPressed: _cancel, child: Text(tr(_s, 'Cancel', 'Отмена'))),
                ])
              else
                Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(_mode == AskMode.summarise ? tr(_s, 'Summarise', 'Пересказать') : tr(_s, 'Ask', 'Спросить')),
                        onPressed: _canRun ? _go : null)),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: cs.error, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_error!, style: TextStyle(color: cs.error))),
                    ])),
              if (_answer != null) _result(_answer!, t, cs),
            ]),
    ));
  }

  Widget _result(AskAnswer a, TextTheme t, ColorScheme cs) {
    final cited = {for (final m in RegExp(r'S(\d+)').allMatches(a.body)) int.parse(m.group(1)!)};
    final byNumber = {for (final x in _sentSections) x.number: x};
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (a.fromDigests)
              Text(tr(_s, 'From short summaries of the sections, less detailed than the text.',
                  'По кратким пересказам разделов, менее подробно, чем по тексту.'),
                  style: t.labelMedium),
            if (a.truncated)
              Text(tr(_s, 'The answer was cut off. Try a narrower range or a shorter question.',
                  'Ответ оборвался. Сузьте диапазон или сократите вопрос.'),
                  style: t.labelMedium?.copyWith(color: cs.error)),
            if (a.body.isEmpty)
              Text(tr(_s, 'The model gave no answer.', 'Модель не дала ответа.'))
            else
              MarkdownLite(a.body),
            if (cited.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                  [for (final n in cited.toList()..sort()) if (byNumber[n] != null) 'S$n = ${_label(byNumber[n]!)}'].join('\n'),
                  style: t.bodySmall),
            ],
            if (a.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(tr(_s, 'Evidence', 'Подтверждение'), style: t.titleSmall),
              for (final e in a.evidence)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(e.verified ? Icons.check_circle_outline : Icons.help_outline,
                          size: 16, color: e.verified ? Colors.green : cs.outline),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              '${e.verified ? '' : '${tr(_s, 'Not found in the text', 'Не найдено в тексте')}: '}'
                              'S${e.section}: «${e.quote}»',
                              style: t.bodySmall?.copyWith(color: e.verified ? null : cs.outline))),
                    ])),
            ],
          ]),
        ),
      ),
    );
  }
}

Future<void> openAsk(BuildContext context, AppService s, ProjectModel book) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AskPage(s, book)));
