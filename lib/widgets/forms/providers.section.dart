import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/llm/adapters.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/ui/widgets.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/widgets/network_message.dart';

const _vendorNames = {
  LlmVendor.gemini: 'Gemini',
  LlmVendor.openai: 'OpenAI',
  LlmVendor.anthropic: 'Anthropic',
};

const _defaultModels = {
  LlmVendor.gemini: 'gemini-2.5-flash',
  LlmVendor.openai: 'gpt-4o-mini',
  LlmVendor.anthropic: 'claude-sonnet-5-5',
};

/// Settings group listing the saved AI Providers, with add, edit and delete.
class ProvidersSection extends StatefulWidget {
  final AppService service;

  /// Makes the HTTP client used by "Test connection" (replaced in tests).
  final http.Client Function() httpFactory;
  const ProvidersSection(this.service,
      {super.key, this.httpFactory = http.Client.new});
  @override
  State<ProvidersSection> createState() => _ProvidersSectionState();
}

class _ProvidersSectionState extends State<ProvidersSection> {
  List<Provider> _providers = [];

  AppService get _s => widget.service;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _s.providerStore.list();
    if (mounted) setState(() => _providers = list);
  }

  Future<void> _edit([Provider? existing]) async {
    final result = await showDialog<Provider>(
        context: context,
        builder: (_) => _ProviderDialog(_s, existing, widget.httpFactory));
    if (result == null) return;
    await _s.providerStore
        .save(result, makeDefault: existing == null && _providers.isEmpty);
    await _reload();
  }

  Future<void> _delete(Provider p) async {
    await _s.providerStore.delete(p.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final store = _s.providerStore;
    return SettingsGroup(
        tr(_s, 'AI providers', 'ИИ-провайдеры'),
        icon: Icons.auto_awesome_outlined,
        [
          for (final p in _providers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name),
              subtitle: Text('${_vendorNames[p.vendor]} · ${p.model}'),
              leading: Icon(
                  p.id == store.defaultId ? Icons.star : Icons.star_border),
              onTap: () => _edit(p),
              trailing: IconButton(
                  tooltip: tr(_s, 'Delete', 'Удалить'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(p)),
            ),
          if (kIsWeb)
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(_s, 'Remember keys in this browser',
                    'Запомнить ключи в этом браузере')),
                subtitle: Text(tr(_s, 'Otherwise keys are forgotten on reload',
                    'Иначе ключи забываются при перезагрузке')),
                value: store.rememberKey,
                onChanged: (v) async {
                  await store.setRememberKey(v);
                  await _reload();
                }),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add),
            title: Text(tr(_s, 'Add provider', 'Добавить провайдера')),
            onTap: () => _edit(),
          ),
        ]);
  }
}

class _ProviderDialog extends StatefulWidget {
  final AppService service;
  final Provider? existing;
  final http.Client Function() httpFactory;
  const _ProviderDialog(this.service, this.existing, this.httpFactory);
  @override
  State<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<_ProviderDialog> {
  late LlmVendor _vendor = widget.existing?.vendor ?? LlmVendor.openai;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _model = TextEditingController(
      text: widget.existing?.model ?? _defaultModels[_vendor]);
  late final _key = TextEditingController(text: widget.existing?.apiKey ?? '');
  late final _url = TextEditingController(text: widget.existing?.baseUrl ?? '');
  late final _chunk = TextEditingController(
      text: '${widget.existing?.chunkChars ?? defaultChunkChars}');

  @override
  void dispose() {
    for (final c in [_name, _model, _key, _url, _chunk]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _testing = false;
  String? _result; // null: not tested; '' : worked; else the problem
  bool get _worked => _result == '';

  Provider get _draft => Provider(
      id: widget.existing?.id ?? 'test',
      name: _name.text.trim(),
      vendor: _vendor,
      model: _model.text.trim(),
      apiKey: _key.text.trim(),
      baseUrl: _url.text.trim(),
      chunkChars: _chunkChars ?? defaultChunkChars);

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final failure = await testConnection(_draft, widget.httpFactory());
    if (!mounted) return;
    final s = widget.service;
    var text = '';
    if (failure != null) {
      switch (failure.failure) {
        case LlmFailure.invalidKey:
          text = tr(s, 'The API key was rejected', 'API-ключ отклонён');
        case LlmFailure.rateLimited:
          text = tr(s, 'Reachable, but the rate limit is reached',
              'Сервер доступен, но лимит запросов исчерпан');
        case LlmFailure.network:
          text = networkMessage(s, web: kIsWeb, baseUrl: _url.text);
        case LlmFailure.badResponse:
          text = tr(s, 'Unexpected answer (${failure.message}): check the model and base URL',
              'Неожиданный ответ (${failure.message}): проверьте модель и URL');
      }
    }
    setState(() {
      _testing = false;
      _result = text;
    });
  }

  int? get _chunkChars {
    final n = int.tryParse(_chunk.text.trim());
    return n != null && n >= minChunkChars && n <= maxChunkChars ? n : null;
  }

  bool get _valid =>
      _chunkChars != null &&
      _name.text.trim().isNotEmpty &&
      _model.text.trim().isNotEmpty &&
      _key.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return AlertDialog(
      title: Text(tr(s, 'AI provider', 'ИИ-провайдер')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButton<LlmVendor>(
            value: _vendor,
            isExpanded: true,
            items: [
              for (final v in LlmVendor.values)
                DropdownMenuItem(value: v, child: Text(_vendorNames[v]!))
            ],
            onChanged: (v) => setState(() {
              if (_model.text == _defaultModels[_vendor]) {
                _model.text = _defaultModels[v]!;
              }
              _vendor = v!;
            }),
          ),
          TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration:
                  InputDecoration(labelText: tr(s, 'Name', 'Название'))),
          TextField(
              controller: _model,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr(s, 'Model', 'Модель'))),
          TextField(
              controller: _key,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration:
                  InputDecoration(labelText: tr(s, 'API key', 'API-ключ'))),
          TextField(
              controller: _url,
              decoration: InputDecoration(
                  labelText: tr(s, 'Base URL (optional)',
                      'Базовый URL (необязательно)'))),
          TextField(
              controller: _chunk,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: tr(s, 'Chunk limit (characters)',
                      'Лимит фрагмента (символов)'),
                  helperText: tr(
                      s,
                      'Most text sent in one request, $minChunkChars–$maxChunkChars',
                      'Максимум текста в одном запросе, $minChunkChars–$maxChunkChars'),
                  errorText: _chunkChars == null
                      ? tr(s, 'Enter $minChunkChars–$maxChunkChars',
                          'Введите $minChunkChars–$maxChunkChars')
                      : null)),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: Text(tr(s, 'Test connection', 'Проверить связь')),
                onPressed: _valid && !_testing ? _test : null),
          ]),
          if (_result != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(_worked ? Icons.check_circle : Icons.error_outline,
                      size: 18,
                      color: _worked
                          ? Colors.green
                          : Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(_worked
                          ? tr(s, 'Connected', 'Связь есть')
                          : _result!)),
                ])),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(s, 'Cancel', 'Отмена'))),
        FilledButton(
            onPressed: !_valid
                ? null
                : () => Navigator.pop(
                    context,
                    Provider(
                        id: widget.existing?.id ?? getRandomString(8),
                        name: _name.text.trim(),
                        vendor: _vendor,
                        model: _model.text.trim(),
                        apiKey: _key.text.trim(),
                        baseUrl: _url.text.trim(),
                        chunkChars: _chunkChars!)),
            child: Text(tr(s, 'Save', 'Сохранить'))),
      ],
    );
  }
}
