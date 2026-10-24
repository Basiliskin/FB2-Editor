import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/name_check.dart';
import 'package:quill_fb2/services/name_check_ai.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';
import 'package:quill_fb2/ui/widgets.dart';

typedef NameChecker = Future<List<NameFinding>> Function(List<StorySection> sections);

Future<List<NameFinding>> _inIsolate(List<StorySection> sections) => compute(checkNamesIn, sections);

/// Lists names the book writes in more than one way. Nothing here changes the book: the
/// local check is free and offline, and the AI step only judges the unclear pairs.
class NamesCheckPage extends StatefulWidget {
  final AppService service;
  final ProjectModel book;
  final NameChecker checker;
  final http.Client Function() httpFactory;
  NamesCheckPage(this.service, this.book, {super.key, NameChecker? checker, http.Client Function()? httpFactory})
      : checker = checker ?? _inIsolate,
        httpFactory = httpFactory ?? http.Client.new;
  @override
  State<NamesCheckPage> createState() => _NamesCheckPageState();
}

class _NamesCheckPageState extends State<NamesCheckPage> {
  AppService get _s => widget.service;
  List<NameFinding>? _findings;
  bool _busy = false;
  int _done = 0, _of = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sections = [for (final x in widget.book.section) StorySection(x.sectionId, x.title, List.of(x.p))];
    final found = await widget.checker(sections);
    final gone = _s.nameCheckStore.dismissed(widget.book.projectId).toSet();
    final shown = [for (final f in found) if (!gone.contains(f.key)) f];
    NameVerifier.plan(shown, _s.nameCheckStore, 1 << 30); // answers from an earlier run cost nothing
    if (mounted) setState(() => _findings = shown);
  }

  List<NameFinding> get _visible =>
      [for (final f in _findings ?? const <NameFinding>[]) if (f.verdict != NameVerdict.different) f];

  int get _hidden => (_findings?.length ?? 0) - _visible.length;

  String _failure(LlmException e) => switch (e.failure) {
        LlmFailure.invalidKey => tr(_s, 'The provider rejected the API key', 'Провайдер отклонил API-ключ'),
        LlmFailure.rateLimited => tr(_s, 'Rate limit reached, try again later', 'Лимит запросов исчерпан, попробуйте позже'),
        LlmFailure.network => tr(_s, 'No connection to the provider', 'Нет связи с провайдером'),
        LlmFailure.badResponse => tr(_s, 'The provider sent an unusable answer', 'Провайдер прислал непригодный ответ'),
      };

  Future<void> _verify() async {
    final provider = await _s.providerStore.defaultProvider();
    if (!mounted) return;
    if (provider == null) {
      setState(() => _error = tr(_s, 'Connect an AI provider in Settings first', 'Сначала подключите ИИ-провайдера в настройках'));
      return;
    }
    final store = _s.nameCheckStore;
    final plan = NameVerifier.plan(_findings!, store, provider.chunkChars);
    setState(() => _error = null);
    if (plan.pairs == 0) return setState(() {});
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(tr(_s, 'Ask the AI about ${plan.pairs} pair(s)?', 'Спросить ИИ про ${plan.pairs} пар(ы)?')),
              content: Text(tr(
                  _s,
                  'Short quotes around ${plan.pairs} pair(s) of names, about ${plan.characters} characters in '
                      '${plan.requests} request(s), will be sent to ${provider.name} (${provider.model}) using your API key. '
                      'The rest of the book stays on the device.',
                  'Короткие цитаты вокруг ${plan.pairs} пар имён, около ${plan.characters} символов в '
                      '${plan.requests} запрос(ах), будут отправлены в ${provider.name} (${provider.model}) с вашим API-ключом. '
                      'Остальной текст остаётся на устройстве.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(_s, 'Cancel', 'Отмена'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(_s, 'Send', 'Отправить'))),
              ],
            ));
    if (ok != true || !mounted) return;
    await _s.providerStore.consent(provider.id);
    setState(() {
      _busy = true;
      _done = 0;
      _of = plan.requests;
    });
    final client = widget.httpFactory();
    try {
      await NameVerifier(createLlmClient(provider, client), store)
          .run(plan, onBatch: (n) => mounted ? setState(() => _done = n) : null);
    } on LlmException catch (e) {
      _error = _failure(e);
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss(NameFinding f) async {
    await _s.nameCheckStore.dismiss(widget.book.projectId, f);
    if (mounted) setState(() => _findings!.remove(f));
  }

  int get _unverified => [for (final f in _visible) if (!f.certain && f.verdict == null) f].length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _visible;
    return Scaffold(
      appBar: AppBar(title: Text(tr(_s, 'Check names', 'Проверка имён'))),
      body: _findings == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          list.isEmpty
                              ? tr(_s, 'No names written in more than one way were found.', 'Имён, написанных по-разному, не найдено.')
                              : tr(_s, '${list.length} name(s) written in more than one way',
                                  'Имён, написанных по-разному: ${list.length}'),
                          style: Theme.of(context).textTheme.titleSmall)),
                  if (_unverified > 0 && !_busy)
                    FilledButton.tonalIcon(
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(tr(_s, 'Ask AI ($_unverified)', 'Спросить ИИ ($_unverified)')),
                        onPressed: _verify),
                ]),
              ),
              if (_busy)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_of > 1) Text(tr(_s, 'Request $_done of $_of', 'Запрос $_done из $_of')),
                      const LinearProgressIndicator(),
                    ])),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: cs.error, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_error!, style: TextStyle(color: cs.error))),
                    ])),
              if (_hidden > 0)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                        tr(_s, '$_hidden pair(s) hidden: the AI says they are different names.',
                            'Скрыто пар: $_hidden, ИИ считает их разными именами.'),
                        style: Theme.of(context).textTheme.bodySmall)),
              Expanded(
                  child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _FindingCard(_s, widget.book, list[i], () => _dismiss(list[i])))),
            ]),
    );
  }
}

class _FindingCard extends StatelessWidget {
  final AppService s;
  final ProjectModel book;
  final NameFinding f;
  final VoidCallback onDismiss;
  const _FindingCard(this.s, this.book, this.f, this.onDismiss);

  String get _label {
    switch (f.verdict) {
      case NameVerdict.same:
        return tr(s, 'AI: same name', 'ИИ: одно имя');
      case NameVerdict.unsure:
        return tr(s, 'AI: not sure', 'ИИ: не уверен');
      default:
    }
    switch (f.kind) {
      case NameFindingKind.script:
        return tr(s, 'Same name, two scripts', 'Одно имя, два алфавита');
      case NameFindingKind.spelling:
        return tr(s, 'Same name, two spellings', 'Одно имя, два написания');
      case NameFindingKind.similar:
        return tr(s, 'Possibly the same name', 'Возможно, одно имя');
    }
  }

  String _where(NameLocation w) {
    final title = w.unit < book.section.length ? book.section[w.unit].title.trim() : '';
    return '${title.isEmpty ? tr(s, 'Section ${w.unit + 1}', 'Раздел ${w.unit + 1}') : title} · ¶${w.paragraph + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text([for (final v in f.variants) v.surface].join('  ·  '), style: t.titleMedium)),
            TextButton(onPressed: onDismiss, child: Text(tr(s, 'Dismiss', 'Скрыть'))),
          ]),
          Text(_label, style: t.labelMedium),
          if (f.reason.isNotEmpty) Text(f.reason, style: t.bodySmall),
          if (f.canonical.isNotEmpty) Text(tr(s, 'Suggested spelling: ${f.canonical}', 'Предлагаемое написание: ${f.canonical}'), style: t.bodySmall),
          const SizedBox(height: 6),
          for (final v in f.variants) ...[
            Text('${v.surface} · ${tr(s, '${v.count} time(s)', 'раз: ${v.count}')}', style: t.labelLarge),
            for (final w in v.where.take(3))
              Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text('${_where(w)}\n${w.quote}', style: t.bodySmall)),
            const SizedBox(height: 4),
          ],
        ]),
      ),
    );
  }
}

Future<void> openNamesCheck(BuildContext context, AppService s, ProjectModel book) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NamesCheckPage(s, book)));
