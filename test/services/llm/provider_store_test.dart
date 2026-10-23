import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/llm/improvement.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';

Provider _p(String id, {String key = 'k', String? baseUrl}) => Provider(
    id: id,
    name: 'P$id',
    vendor: LlmVendor.openai,
    model: 'm',
    apiKey: key,
    baseUrl: baseUrl);

void main() {
  late Map settings;
  late MemoryKeyVault session, persistent;

  ProviderStore store({bool web = false}) => ProviderStore(
      getSettings: () => settings,
      setSettings: (m) async => settings.addAll(m),
      session: session,
      persistent: persistent,
      isWeb: web);

  setUp(() {
    settings = {};
    session = MemoryKeyVault();
    persistent = MemoryKeyVault();
  });

  test('keys never appear in the workspace settings', () async {
    final s = store();
    await s.save(_p('1', key: 'SECRET'));
    expect(settings.toString(), isNot(contains('SECRET')));
    expect((await s.list()).single.apiKey, 'SECRET');
  });

  test('first saved Provider becomes default; later ones only on request',
      () async {
    final s = store();
    await s.save(_p('1'));
    await s.save(_p('2'));
    expect(s.defaultId, '1');
    await s.save(_p('2'), makeDefault: true);
    expect((await s.defaultProvider())!.id, '2');
  });

  test('saving again updates in place', () async {
    final s = store();
    await s.save(_p('1'));
    await s.save(_p('2'));
    await s.save(_p('1', baseUrl: ' http://x '));
    final all = await s.list();
    expect(all.map((p) => p.id), ['1', '2']);
    expect(all.first.baseUrl, 'http://x');
  });

  test('deleting the default hands it to the next Provider', () async {
    final s = store();
    await s.save(_p('1'));
    await s.save(_p('2'));
    await s.delete('1');
    expect((await s.defaultProvider())!.id, '2');
    await s.delete('2');
    expect(await s.defaultProvider(), isNull);
    expect(await persistent.read('1'), isNull);
  });

  test('on web keys stay in the session vault until the user opts in',
      () async {
    final s = store(web: true);
    await s.save(_p('1', key: 'K'));
    expect(await persistent.read('1'), isNull);
    expect(await session.read('1'), 'K');

    await s.setRememberKey(true);
    expect(await persistent.read('1'), 'K');
    expect(await session.read('1'), isNull);

    await s.setRememberKey(false);
    expect(await persistent.read('1'), isNull);
    expect(await session.read('1'), 'K');
  });

  test('off web keys always go to the persistent vault', () async {
    await store().save(_p('1', key: 'K'));
    expect(await persistent.read('1'), 'K');
  });

  test('consent and style notes are remembered; deleting forgets consent',
      () async {
    final s = store();
    await s.save(_p('1'));
    expect(s.isConsented('1'), isFalse);
    await s.consent('1');
    expect(s.isConsented('1'), isTrue);
    await s.setStyleNote('book', '  terse  ');
    expect(s.styleNote('book'), 'terse');
    await s.setStyleNote('book', ' ');
    expect(s.styleNote('book'), '');
    await s.delete('1');
    expect(s.isConsented('1'), isFalse);
  });

  test('custom presets save, replace in place and delete', () async {
    final s = store();
    await s.savePreset(const Preset('A', 'do a', id: '1'));
    await s.savePreset(const Preset('B', 'do b', id: '2'));
    await s.savePreset(const Preset('A2', 'do a2', id: '1'));
    expect(s.customPresets().map((p) => (p.id, p.name)), [('1', 'A2'), ('2', 'B')]);
    expect(s.customPresets().every((p) => p.custom), isTrue);
    await s.deletePreset('1');
    expect(s.customPresets().single.id, '2');
  });
}
