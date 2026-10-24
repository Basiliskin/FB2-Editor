import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/pages/ask_page.dart' show askSectionsOf;
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/story_map_ai.dart';
import 'package:quill_fb2/ui/widgets.dart';

/// "Improve with AI" for the story map: the Provider proposes places, events and lore and
/// labels for Ties; each proposal is accepted or rejected here, one by one. The book text is
/// only sent after the user confirms the size shown, and nothing reaches the map unreviewed.
class StoryMapAiPage extends StatefulWidget {
  final AppService service;
  final ProjectModel book;
  final StoryMap map;

  /// Called after the map was edited, so the caller can save it.
  final VoidCallback changed;
  final http.Client Function() httpFactory;
  StoryMapAiPage(this.service, this.book, this.map, this.changed, {super.key, http.Client Function()? httpFactory})
      : httpFactory = httpFactory ?? http.Client.new;
  @override
  State<StoryMapAiPage> createState() => _StoryMapAiPageState();
}

class _StoryMapAiPageState extends State<StoryMapAiPage> {
  AppService get _s => widget.service;
  StoryMap get _m => widget.map;
  bool _busy = false;
  int _done = 0, _of = 0;
  String? _error;
  List<EntityProposal>? _entities;
  List<TieProposal>? _ties;
  http.Client? _client;
  int _run = 0;

  String get _language => _s.getSettings()['language'] == 'ru' ? 'ru' : 'en';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _run++;
    _client?.close();
    super.dispose();
  }

  String _failure(LlmException e) => switch (e.failure) {
        LlmFailure.invalidKey => tr(_s, 'The provider rejected the API key', 'Провайдер отклонил API-ключ'),
        LlmFailure.rateLimited => tr(_s, 'Rate limit reached, try again later', 'Лимит запросов исчерпан, попробуйте позже'),
        LlmFailure.network => tr(_s, 'No connection to the provider', 'Нет связи с провайдером'),
        LlmFailure.badResponse => tr(_s, 'The provider sent an unusable answer', 'Провайдер прислал непригодный ответ'),
      };

  Future<void> _start() async {
    final provider = await _s.providerStore.defaultProvider();
    if (!mounted) return;
    if (provider == null) {
      setState(() => _error = tr(_s, 'Connect an AI provider in Settings first', 'Сначала подключите ИИ-провайдера в настройках'));
      return;
    }
    final sections = askSectionsOf(widget.book);
    final plan = StoryMapAi.plan(_m, sections, provider.chunkChars);
    if (plan.requests == 0) {
      setState(() => _error = tr(_s, 'The book has no text yet', 'В книге пока нет текста'));
      return;
    }
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(tr(_s, 'Send the book to a provider?', 'Отправить книгу провайдеру?')),
              content: Text(tr(
                  _s,
                  'The text of ${sections.where((x) => x.paragraphs.isNotEmpty).length} section(s), about ${plan.characters} characters in '
                      '${plan.requests} request(s), with the names on your map, will be sent to ${provider.name} (${provider.model}) '
                      'using your API key. You review every proposal before it reaches the map.',
                  'Текст ${sections.where((x) => x.paragraphs.isNotEmpty).length} раздел(ов), около ${plan.characters} символов в '
                      '${plan.requests} запрос(ах), вместе с именами с вашей карты, будет отправлен в ${provider.name} (${provider.model}) '
                      'с вашим API-ключом. Каждое предложение вы проверяете до попадания на карту.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(_s, 'Cancel', 'Отмена'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(_s, 'Send', 'Отправить'))),
              ],
            ));
    if (ok != true || !mounted) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await _s.providerStore.consent(provider.id);
    final mine = ++_run;
    setState(() {
      _busy = true;
      _done = 0;
      _of = plan.requests;
      _error = null;
    });
    final client = _client = widget.httpFactory();
    try {
      final got = await StoryMapAiRunner(createLlmClient(provider, client), _language)
          .run(plan, _m, sections, onRequest: (n) => mine == _run && mounted ? setState(() => _done = n) : null);
      if (mine != _run) return;
      setState(() {
        _entities = [...got.entities];
        _ties = [...got.ties];
      });
    } on LlmException catch (e) {
      if (mine == _run) setState(() => _error = _failure(e));
    } finally {
      client.close();
      if (mine == _run && mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    _run++;
    _client?.close();
    Navigator.of(context).maybePop();
  }

  void _acceptEntity(EntityProposal p) {
    StoryMapAi.accept(_m, p);
    widget.changed();
    setState(() => _entities!.remove(p));
  }

  void _acceptTie(TieProposal t) {
    if (!StoryMapAi.acceptTie(_m, t)) return;
    widget.changed();
    setState(() => _ties!.remove(t));
  }

  bool _resolved(TieProposal t) {
    bool on(String n) => _m.cast.any((e) => e.name.toLowerCase() == n.toLowerCase());
    return on(t.a) && on(t.b);
  }

  void _acceptAll() {
    for (final p in [..._entities!]) {
      _acceptEntity(p);
    }
    for (final t in [..._ties!]) {
      _acceptTie(t);
    }
  }

  String _kind(EntityKind k) => switch (k) {
        EntityKind.place => tr(_s, 'Place', 'Место'),
        EntityKind.event => tr(_s, 'Event', 'Событие'),
        EntityKind.lore => tr(_s, 'Lore', 'Мир'),
        EntityKind.person => tr(_s, 'Person', 'Герой'),
      };

  Widget _actions(VoidCallback? accept, VoidCallback reject) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: tr(_s, 'Accept', 'Принять'),
            icon: Icon(Icons.check, color: accept == null ? null : Colors.green),
            onPressed: accept),
        IconButton(
            tooltip: tr(_s, 'Reject', 'Отклонить'),
            icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
            onPressed: reject),
      ]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final entities = _entities, ties = _ties;
    final left = (entities?.length ?? 0) + (ties?.length ?? 0);
    return Scaffold(
      appBar: AppBar(title: Text(tr(_s, 'Improve map with AI', 'Улучшить карту с ИИ')), actions: [
        if (left > 1) TextButton(onPressed: _acceptAll, child: Text(tr(_s, 'Accept all ($left)', 'Принять все ($left)'))),
      ]),
      body: Column(children: [
        if (_busy)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_of > 1 ? tr(_s, 'Request $_done of $_of', 'Запрос $_done из $_of') : tr(_s, 'Reading the book…', 'Читаю книгу…')),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _cancel, child: Text(tr(_s, 'Cancel', 'Отмена')))),
              ])),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.error_outline, color: cs.error, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: TextStyle(color: cs.error))),
                TextButton(onPressed: _start, child: Text(tr(_s, 'Retry', 'Повторить'))),
              ])),
        if (entities != null && ties != null && left == 0 && !_busy)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr(_s, 'Nothing more to propose.', 'Больше предложений нет.'), style: t.titleSmall)),
        Expanded(
            child: ListView(children: [
          if (entities != null && entities.isNotEmpty) ...[
            _header(tr(_s, 'To add to the map (${entities.length})', 'Добавить на карту (${entities.length})')),
            for (final p in entities)
              ListTile(
                title: Text(p.name),
                subtitle: Text([
                  _kind(p.kind),
                  tr(_s, '${p.mentions} mention(s)', 'упоминаний: ${p.mentions}'),
                  if (p.note.isNotEmpty) p.note,
                ].join(' · ')),
                trailing: _actions(() => _acceptEntity(p), () => setState(() => entities.remove(p))),
              ),
          ],
          if (ties != null && ties.isNotEmpty) ...[
            _header(tr(_s, 'Ties (${ties.length})', 'Связи (${ties.length})')),
            for (final x in ties)
              ListTile(
                title: Text('${x.a} — ${x.b}'),
                subtitle: Text([
                  x.label,
                  if (!x.exists) tr(_s, 'new tie', 'новая связь'),
                  if (!_resolved(x)) tr(_s, 'add both names first', 'сначала добавьте оба имени'),
                ].join(' · ')),
                trailing: _actions(_resolved(x) ? () => _acceptTie(x) : null, () => setState(() => ties.remove(x))),
              ),
          ],
        ])),
      ]),
    );
  }

  Widget _header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall));
}

Future<void> openStoryMapAi(BuildContext context, AppService s, ProjectModel book, StoryMap map, VoidCallback changed) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryMapAiPage(s, book, map, changed)));
