import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/pages/ask_page.dart'
    show askSectionsOf, bookLanguageOf;
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/story_map_ai.dart';
import 'package:quill_fb2/services/book_ask.dart' show AskSection;
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/widgets/stop_run_dialog.dart';

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
  StoryMapAiPage(this.service, this.book, this.map, this.changed,
      {super.key, http.Client Function()? httpFactory})
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

  String get _language => bookLanguageOf(_s, widget.book);

  late final List<AskSection> _all = [
    for (final x in askSectionsOf(widget.book))
      if (x.paragraphs.isNotEmpty) x
  ];

  /// Sections the user ticked; none by default, since every one sent costs time and money.
  final Set<int> _picked = {};

  /// False once a run has started (or finished): the picker is only for choosing what to send.
  bool _picking = true;
  Provider? _provider;
  bool _loaded = false;

  List<AskSection> get _chosen => [
        for (final x in _all)
          if (_picked.contains(x.number)) x
      ];

  StoryMapAiPlan? get _plan {
    final p = _provider;
    if (p == null || _picked.isEmpty) return null;
    return StoryMapAi.plan(_m, _chosen, p.chunkChars);
  }

  @override
  void initState() {
    super.initState();
    _s.providerStore.defaultProvider().then((p) {
      if (!mounted) return;
      setState(() {
        _provider = p;
        _loaded = true;
        if (p == null) {
          _error = tr(_s, 'Connect an AI provider in Settings first',
              'Сначала подключите ИИ-провайдера в настройках');
        } else if (_all.isEmpty) {
          _error =
              tr(_s, 'The book has no text yet', 'В книге пока нет текста');
        }
      });
    });
  }

  @override
  void dispose() {
    _run++;
    _client?.close();
    super.dispose();
  }

  String _failure(LlmException e) => switch (e.failure) {
        LlmFailure.invalidKey => tr(_s, 'The provider rejected the API key',
            'Провайдер отклонил API-ключ'),
        LlmFailure.rateLimited => tr(_s, 'Rate limit reached, try again later',
            'Лимит запросов исчерпан, попробуйте позже'),
        LlmFailure.network =>
          tr(_s, 'No connection to the provider', 'Нет связи с провайдером'),
        LlmFailure.badResponse => tr(_s, 'The provider sent an unusable answer',
            'Провайдер прислал непригодный ответ'),
      };

  Future<void> _start() async {
    final provider = _provider, plan = _plan;
    if (provider == null || plan == null) return;
    final sections = _chosen;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(tr(_s, 'Send the book to a provider?',
                  'Отправить книгу провайдеру?')),
              content: Text(tr(
                  _s,
                  'The text of ${sections.length} section(s), about ${plan.characters} characters in '
                      '${plan.requests} request(s), with the names on your map, will be sent to ${provider.name} (${provider.model}) '
                      'using your API key. You review every proposal before it reaches the map.',
                  'Текст ${sections.length} раздел(ов), около ${plan.characters} символов в '
                      '${plan.requests} запрос(ах), вместе с именами с вашей карты, будет отправлен в ${provider.name} (${provider.model}) '
                      'с вашим API-ключом. Каждое предложение вы проверяете до попадания на карту.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(tr(_s, 'Cancel', 'Отмена'))),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(tr(_s, 'Send', 'Отправить'))),
              ],
            ));
    if (ok != true || !mounted) return;
    await _s.providerStore.consent(provider.id);
    final mine = ++_run;
    setState(() {
      _picking = false;
      _busy = true;
      _done = 0;
      _of = plan.requests;
      _error = null;
    });
    final client = _client = widget.httpFactory();
    try {
      final got = await StoryMapAiRunner(
              createLlmClient(provider, client), _language)
          .run(plan, _m, sections,
              onRequest: (n) =>
                  mine == _run && mounted ? setState(() => _done = n) : null);
      if (mine != _run) return;
      setState(() {
        _entities = [...got.entities];
        _ties = [...got.ties];
      });
    } on LlmException catch (e) {
      if (mine == _run) {
        setState(() {
          _error = _failure(e);
          _picking = true;
        });
      }
    } finally {
      client.close();
      if (mine == _run && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (!await confirmStopRun(context, _s) || !mounted) return;
    _run++;
    _client?.close();
    setState(() {
      _busy = false;
      _picking = true;
    });
  }

  /// Kinds switched off by the filter chips; 'ties' hides every tie.
  final Set<String> _hidden = {};

  void _acceptEntity(EntityProposal p) {
    StoryMapAi.accept(_m, p);
    widget.changed();
    setState(() => _entities!.remove(p));
  }

  /// Accepts a tie, adding the places it names that are still proposals first.
  void _acceptTie(TieProposal t) {
    for (final n in [t.a, t.b]) {
      final p = _entities!
          .where((e) => e.name.toLowerCase() == n.toLowerCase())
          .firstOrNull;
      if (p != null) StoryMapAi.accept(_m, p);
      _entities!.remove(p);
    }
    if (!StoryMapAi.acceptTie(_m, t)) return;
    widget.changed();
    setState(() => _ties!.remove(t));
  }

  /// A rejected place takes the ties that name it along.
  void _rejectEntity(EntityProposal p) => setState(() {
        _entities!.remove(p);
        final n = p.name.toLowerCase();
        _ties!.removeWhere(
            (t) => t.a.toLowerCase() == n || t.b.toLowerCase() == n);
      });

  bool _named(TieProposal t, EntityProposal e) =>
      t.a.toLowerCase() == e.name.toLowerCase() ||
      t.b.toLowerCase() == e.name.toLowerCase();

  /// The first proposed place a tie names; the tie is shown under it.
  EntityProposal? _anchor(TieProposal t) =>
      _entities!.where((e) => _named(t, e)).firstOrNull;

  bool _entityShown(EntityProposal e) => !_hidden.contains(e.kind.name);

  List<TieProposal> _nested(EntityProposal e) => _hidden.contains('ties')
      ? const []
      : [
          for (final t in _ties!)
            if (_anchor(t) == e) t
        ];

  /// Ties shown in the trailing card: those with no place to hang under, or whose place is filtered out.
  List<TieProposal> get _loose =>
      _hidden.contains('ties') || _ties == null || _entities == null
          ? const []
          : [
              for (final t in _ties!)
                if (_anchor(t) == null || !_entityShown(_anchor(t)!)) t
            ];

  int get _shown =>
      [
        for (final e in _entities ?? const <EntityProposal>[])
          if (_entityShown(e)) e
      ].length +
      [
        for (final e in _entities ?? const <EntityProposal>[])
          if (_entityShown(e)) ..._nested(e)
      ].length +
      _loose.length;

  /// Accepts what the filters leave on screen.
  void _acceptAll() {
    final es = [
      for (final e in _entities!)
        if (_entityShown(e)) e
    ];
    final ties = [for (final e in es) ..._nested(e), ..._loose];
    for (final e in es) {
      if (_entities!.contains(e)) _acceptEntity(e);
    }
    for (final t in ties) {
      if (_ties!.contains(t)) _acceptTie(t);
    }
  }

  String _kind(EntityKind k) => switch (k) {
        EntityKind.place => tr(_s, 'Place', 'Место'),
        EntityKind.event => tr(_s, 'Event', 'Событие'),
        EntityKind.lore => tr(_s, 'Lore', 'Мир'),
        EntityKind.person => tr(_s, 'Person', 'Герой'),
      };

  Widget _actions(VoidCallback accept, VoidCallback reject, VoidCallback edit) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: tr(_s, 'Edit', 'Изменить'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: edit),
        IconButton(
            tooltip: tr(_s, 'Accept', 'Принять'),
            icon: const Icon(Icons.check, color: Colors.green),
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
    final shown = entities == null ? 0 : _shown;
    return PopScope(
        canPop: !_busy,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await confirmStopRun(context, _s) && mounted) {
            _run++;
            _client?.close();
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(tr(_s, 'Improve map with AI', 'Улучшить карту с ИИ')),
              actions: [
                if (shown > 1)
                  TextButton(
                      onPressed: _acceptAll,
                      child: Text(tr(
                          _s, 'Accept all ($shown)', 'Принять все ($shown)'))),
              ]),
          body: Column(children: [
            if (_busy)
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_of > 1
                            ? tr(_s, 'Request $_done of $_of',
                                'Запрос $_done из $_of')
                            : tr(_s, 'Reading the book…', 'Читаю книгу…')),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                                onPressed: _cancel,
                                child: Text(tr(_s, 'Cancel', 'Отмена')))),
                      ])),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: cs.error, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                        child:
                            Text(_error!, style: TextStyle(color: cs.error))),
                  ])),
            if (entities != null && ties != null && left == 0 && !_busy)
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      tr(_s, 'Nothing more to propose.',
                          'Больше предложений нет.'),
                      style: t.titleSmall)),
            if (entities != null && ties != null && left > 0)
              _filters(entities, ties),
            if (!_loaded)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_picking && _provider != null && _all.isNotEmpty)
              Expanded(child: _picker(t))
            else
              Expanded(
                  child: ListView(children: [
                for (final p in entities ?? const <EntityProposal>[])
                  if (_entityShown(p))
                    Card(
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Column(children: [
                          ListTile(
                            title: Text(p.name),
                            subtitle: Text([
                              _kind(p.kind),
                              tr(_s, '${p.mentions} mention(s)',
                                  'упоминаний: ${p.mentions}'),
                              if (p.note.isNotEmpty) p.note,
                            ].join(' · ')),
                            onTap: () => _editEntity(p),
                            trailing: _actions(() => _acceptEntity(p),
                                () => _rejectEntity(p), () => _editEntity(p)),
                          ),
                          for (final x in _nested(p))
                            Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: _tieTile(x)),
                        ])),
                if (_loose.isNotEmpty)
                  Card(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Column(children: [
                        _header(tr(_s, 'Ties', 'Связи')),
                        for (final x in _loose) _tieTile(x),
                      ])),
              ])),
          ]),
        ));
  }

  /// Which Sections go to the provider. Nothing is ticked at first.
  Widget _picker(TextTheme t) {
    final plan = _plan;
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
              tr(
                  _s,
                  'Choose the sections the AI should read. Fewer sections means a faster, cheaper run.',
                  'Выберите разделы, которые должен прочитать ИИ. Чем меньше разделов, тем быстрее и дешевле.'),
              style: t.bodyMedium)),
      Row(children: [
        const SizedBox(width: 8),
        TextButton(
            onPressed: () =>
                setState(() => _picked.addAll(_all.map((x) => x.number))),
            child: Text(tr(_s, 'Select all', 'Выбрать все'))),
        TextButton(
            onPressed: _picked.isEmpty ? null : () => setState(_picked.clear),
            child: Text(tr(_s, 'Clear', 'Снять выбор'))),
      ]),
      Expanded(
          child: ListView(children: [
        for (final x in _all)
          CheckboxListTile(
              key: ValueKey('pick${x.number}'),
              value: _picked.contains(x.number),
              onChanged: (on) => setState(() => on == true
                  ? _picked.add(x.number)
                  : _picked.remove(x.number)),
              title: Text(
                  x.title.isEmpty
                      ? tr(_s, 'Section ${x.number}', 'Раздел ${x.number}')
                      : x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(tr(_s, '${x.text.length} characters',
                  'символов: ${x.text.length}'))),
      ])),
      SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: Text(
                        plan == null
                            ? tr(_s, 'Nothing selected', 'Ничего не выбрано')
                            : tr(
                                _s,
                                '${_picked.length} section(s), about ${plan.characters} characters, ${plan.requests} request(s)',
                                'Разделов: ${_picked.length}, около ${plan.characters} символов, запросов: ${plan.requests}'),
                        style: t.bodySmall)),
                FilledButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(tr(_s, 'Continue', 'Далее')),
                    onPressed: plan == null ? null : _start),
              ]))),
    ]);
  }

  Widget _tieTile(TieProposal x) => ListTile(
      title: Text('${x.a} — ${x.b}'),
      subtitle: Text([x.label, if (!x.exists) tr(_s, 'new tie', 'новая связь')]
          .join(' · ')),
      onTap: () => _editTie(x),
      trailing: _actions(() => _acceptTie(x),
          () => setState(() => _ties!.remove(x)), () => _editTie(x)));

  Future<List<String>?> _ask(String title, List<(String, String)> fields) {
    final ctrls = [for (final f in fields) TextEditingController(text: f.$2)];
    return showDialog<List<String>>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < fields.length; i++)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                          controller: ctrls[i],
                          minLines: 1,
                          maxLines: 4,
                          decoration:
                              InputDecoration(labelText: fields[i].$1))),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(tr(_s, 'Cancel', 'Отмена'))),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, [for (final c in ctrls) c.text.trim()]),
                    child: Text(tr(_s, 'Save', 'Сохранить'))),
              ],
            ));
  }

  /// Changes a proposal before it is accepted; a new name is carried into the ties that name it.
  Future<void> _editEntity(EntityProposal p) async {
    final got = await _ask(tr(_s, 'Edit proposal', 'Изменить предложение'), [
      (tr(_s, 'Name', 'Название'), p.name),
      (tr(_s, 'Note', 'Заметка'), p.note),
    ]);
    if (got == null || got[0].isEmpty || !mounted) return;
    setState(() {
      final i = _entities!.indexOf(p);
      if (i < 0) return;
      _entities![i] = p.edited(name: got[0], note: got[1]);
      final old = p.name.toLowerCase();
      for (var k = 0; k < _ties!.length; k++) {
        final t = _ties![k];
        if (t.a.toLowerCase() == old || t.b.toLowerCase() == old) {
          _ties![k] = t.edited(
              a: t.a.toLowerCase() == old ? got[0] : null,
              b: t.b.toLowerCase() == old ? got[0] : null);
        }
      }
    });
  }

  Future<void> _editTie(TieProposal t) async {
    final got = await _ask(tr(_s, 'Edit tie', 'Изменить связь'),
        [(tr(_s, 'Label', 'Подпись'), t.label)]);
    if (got == null || !mounted) return;
    setState(() {
      final i = _ties!.indexOf(t);
      if (i >= 0) _ties![i] = t.edited(label: got[0]);
    });
  }

  /// Switches that narrow the list; "Accept all" then applies only to what is left showing.
  Widget _filters(List<EntityProposal> entities, List<TieProposal> ties) {
    int count(EntityKind k) => entities.where((e) => e.kind == k).length;
    final chips = <(String, String, int)>[
      ('place', tr(_s, 'Places', 'Места'), count(EntityKind.place)),
      ('event', tr(_s, 'Events', 'События'), count(EntityKind.event)),
      ('lore', tr(_s, 'Lore', 'Мир'), count(EntityKind.lore)),
      ('ties', tr(_s, 'Ties', 'Связи'), ties.length),
    ];
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, children: [
              for (final (key, label, n) in chips)
                if (n > 0)
                  FilterChip(
                      label: Text('$label $n'),
                      selected: !_hidden.contains(key),
                      onSelected: (on) => setState(
                          () => on ? _hidden.remove(key) : _hidden.add(key))),
            ])));
  }

  Widget _header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall));
}

Future<void> openStoryMapAi(BuildContext context, AppService s,
        ProjectModel book, StoryMap map, VoidCallback changed) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StoryMapAiPage(s, book, map, changed)));
