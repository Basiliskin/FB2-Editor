import 'package:quill_fb2/services/llm/improvement.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';

const _providersKey = 'llm-providers';
const _defaultKey = 'llm-default-provider';
const rememberKeyKey = 'llm-remember-key';
const _consentKey = 'llm-consented';
const _styleNotesKey = 'llm-style-notes';
const _presetsKey = 'llm-presets';

/// Saved Providers: descriptions in the workspace settings, keys in a [KeyVault].
class ProviderStore {
  final Map Function() _getSettings;
  final Future<void> Function(Map) _setSettings;
  final KeyVault _session;
  final KeyVault _persistent;
  final bool _isWeb;

  /// On web keys stay in [session] unless the user opted in to [persistent].
  ProviderStore(
      {required Map Function() getSettings,
      required Future<void> Function(Map) setSettings,
      required KeyVault session,
      required KeyVault persistent,
      required bool isWeb})
      : _getSettings = getSettings,
        _setSettings = setSettings,
        _session = session,
        _persistent = persistent,
        _isWeb = isWeb;

  bool get rememberKey => _getSettings()[rememberKeyKey] == true;
  KeyVault get _vault => (!_isWeb || rememberKey) ? _persistent : _session;

  List<Map> get _rows => [
        for (final r in (_getSettings()[_providersKey] as List? ?? []))
          Map.from(r as Map)
      ];

  String? get defaultId => _getSettings()[_defaultKey] as String?;

  Future<List<Provider>> list() async => [
        for (final r in _rows)
          Provider(
              id: r['id'],
              name: r['name'],
              vendor: LlmVendor.values.byName(r['vendor']),
              model: r['model'],
              apiKey: await _vault.read(r['id']) ?? '',
              baseUrl: r['baseUrl'])
      ];

  /// The Provider to use when the user does not pick one: the default, else the first.
  Future<Provider?> defaultProvider() async {
    final all = await list();
    if (all.isEmpty) return null;
    return all.firstWhere((p) => p.id == defaultId, orElse: () => all.first);
  }

  Future<void> save(Provider p, {bool makeDefault = false}) async {
    final rows = _rows.where((r) => r['id'] != p.id).toList();
    final row = {
      'id': p.id,
      'name': p.name,
      'vendor': p.vendor.name,
      'model': p.model,
      if ((p.baseUrl ?? '').trim().isNotEmpty) 'baseUrl': p.baseUrl!.trim(),
    };
    final old = _rows.indexWhere((r) => r['id'] == p.id);
    if (old >= 0) {
      rows.insert(old, row);
    } else {
      rows.add(row);
    }
    await _vault.write(p.id, p.apiKey);
    await _setSettings({
      _providersKey: rows,
      if (makeDefault || defaultId == null) _defaultKey: p.id,
    });
  }

  Future<void> delete(String id) async {
    await _vault.delete(id);
    final consented = ((_getSettings()[_consentKey] as List?) ?? const [])
        .where((c) => c != id)
        .toList();
    final rows = _rows.where((r) => r['id'] != id).toList();
    await _setSettings({
      _providersKey: rows,
      _consentKey: consented,
      if (defaultId == id) _defaultKey: rows.isEmpty ? null : rows.first['id'],
    });
  }

  /// Whether the user agreed to send text to this Provider.
  bool isConsented(String id) =>
      ((_getSettings()[_consentKey] as List?) ?? const []).contains(id);

  Future<void> consent(String id) async {
    if (isConsented(id)) return;
    await _setSettings({
      _consentKey: [...((_getSettings()[_consentKey] as List?) ?? const []), id]
    });
  }

  /// The presets the user saved, in the order they were made.
  List<Preset> customPresets() => [
        for (final r in (_getSettings()[_presetsKey] as List? ?? const []))
          Preset(r['name'], r['instruction'], id: r['id'])
      ];

  /// Adds [p], or replaces the saved preset with the same id.
  Future<void> savePreset(Preset p) async {
    final rows = [
      for (final q in customPresets())
        if (q.id != p.id) {'id': q.id, 'name': q.name, 'instruction': q.instruction}
    ];
    final at = customPresets().indexWhere((q) => q.id == p.id);
    final row = {'id': p.id, 'name': p.name, 'instruction': p.instruction};
    at < 0 ? rows.add(row) : rows.insert(at, row);
    await _setSettings({_presetsKey: rows});
  }

  Future<void> deletePreset(String id) => _setSettings({
        _presetsKey: [
          for (final q in customPresets())
            if (q.id != id) {'id': q.id, 'name': q.name, 'instruction': q.instruction}
        ]
      });

  /// The user's tone-and-voice instruction for one book ("" when none).
  String styleNote(String bookId) =>
      ((_getSettings()[_styleNotesKey] as Map?) ?? const {})[bookId] as String? ?? '';

  Future<void> setStyleNote(String bookId, String note) async {
    final notes = Map.of((_getSettings()[_styleNotesKey] as Map?) ?? const {});
    note.trim().isEmpty ? notes.remove(bookId) : notes[bookId] = note.trim();
    await _setSettings({_styleNotesKey: notes});
  }

  Future<void> setRememberKey(bool remember) async {
    if (remember == rememberKey) return;
    final all = await list();
    await _setSettings({rememberKeyKey: remember});
    // move keys to where they now belong; forget them from where they were
    for (final p in all) {
      await _vault.write(p.id, p.apiKey);
      await (remember ? _session : _persistent).delete(p.id);
    }
  }
}
