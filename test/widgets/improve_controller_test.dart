import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/llm/key_vault.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:quill_fb2/services/llm/provider_store.dart';
import 'package:quill_fb2/widgets/section_editor/improve_controller.dart';

http.Response _ok(String text) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': text}
        }
      ]
    }),
    200);

void main() {
  late Map settings;
  late ProviderStore store;
  late Section section;
  late int flushed, applied;
  late List<String> sent;

  ImproveController make(http.Response Function(http.Request) answer) =>
      ImproveController(
          store: store,
          section: section,
          bookId: 'book',
          bookInfo: () => (title: 'T', lang: 'en', genre: 'prose'),
          flush: () => flushed++,
          afterApply: () => applied++,
          httpFactory: () => MockClient((r) async {
                sent.add(r.body);
                return answer(r);
              }));

  Future<bool> yes(Provider p, int n, int t) async => true;

  setUp(() async {
    settings = {};
    flushed = applied = 0;
    sent = [];
    store = ProviderStore(
        getSettings: () => settings,
        setSettings: (m) async => settings.addAll(m),
        session: MemoryKeyVault(),
        persistent: MemoryKeyVault(),
        isWeb: false);
    await store.save(const Provider(
        id: 'p', name: 'P', vendor: LlmVendor.openai, model: 'm', apiKey: 'k'));
    section = Section({
      'p': ['<p>one</p>', '<image xlink:href="#i"/>', '<p>two <strong>x</strong></p>'],
      'sectionId': 's'
    }, BinaryResources([]));
  });

  test('opening starts at the active paragraph and loads the providers',
      () async {
    final c = make((_) => _ok(''));
    await c.toggle(2);
    expect((c.open, c.start, c.end, c.current?.id), (true, 2, 2, 'p'));
    expect(flushed, 1);
  });

  test('tapping widens then narrows the range; pictures are skipped', () async {
    final c = make((_) => _ok(''));
    await c.toggle(0);
    c.tapParagraph(2);
    expect((c.start, c.end), (0, 2));
    expect(c.eligible, [0, 2]);
    c.tapParagraph(0);
    expect((c.start, c.end), (1, 2));
    c.selectAll();
    expect((c.start, c.end), (0, 2));
  });

  test('a good answer becomes suggestions that accept, then undo', () async {
    final c = make((_) => _ok('[1] ONE\n[2] TWO <strong>x</strong>'));
    await c.toggle(0);
    c.selectAll();
    await c.ask('shout', yes);
    expect(c.suggestions, {0: 'ONE', 2: 'TWO <strong>x</strong>'});
    expect(sent.single, contains('[2] two <strong>x</strong>'));
    expect(settings['llm-consented'], ['p']);

    c.accept([0]);
    expect(section.p[0], '<p>ONE</p>');
    expect(section.p[2], '<p>two <strong>x</strong></p>');
    expect(c.suggestions.keys, [2]);
    expect(applied, 1);

    c.undo();
    expect(section.p[0], '<p>one</p>');
    expect(c.canUndo, isFalse);
  });

  test('a suggestion that changes tags is discarded and nothing changes',
      () async {
    final c = make((_) => _ok('[1] ONE\n[2] TWO'));
    await c.toggle(0);
    c.selectAll();
    await c.ask('shout', yes);
    expect(c.error, ImproveError.rejected);
    expect(c.suggestions, isEmpty);
    expect(section.p[0], '<p>one</p>');
  });

  test('declining the consent prompt sends nothing', () async {
    final c = make((_) => _ok(''));
    await c.toggle(0);
    await c.ask('x', (p, n, t) async => false);
    expect(sent, isEmpty);
    expect(c.busy, isFalse);
    expect(store.isConsented('p'), isFalse);
  });

  test('consent is asked once per provider', () async {
    final c = make((_) => _ok('[1] ONE'));
    await c.toggle(0);
    var asked = 0;
    Future<bool> counting(Provider p, int n, int t) async {
      asked++;
      return true;
    }

    await c.ask('x', counting);
    await c.ask('x', counting);
    expect(asked, 1);
  });

  test('provider failures map to errors', () async {
    final c = make((_) => http.Response('', 401));
    await c.toggle(0);
    await c.ask('x', yes);
    expect(c.error, ImproveError.invalidKey);
    expect(c.busy, isFalse);
  });

  test('a request over the size limit is refused before sending', () async {
    section.p = ['<p>${'x' * 13000}</p>'];
    final c = make((_) => _ok(''));
    await c.toggle(0);
    await c.ask('x', yes);
    expect(c.error, ImproveError.tooLarge);
    expect(sent, isEmpty);
  });

  test('cancel drops the late answer', () async {
    final gate = Completer<void>();
    final c = ImproveController(
        store: store,
        section: section,
        bookId: 'book',
        bookInfo: () => (title: 'T', lang: 'en', genre: 'prose'),
        flush: () {},
        afterApply: () {},
        httpFactory: () => MockClient((r) async {
              await gate.future;
              return _ok('[1] ONE');
            }));
    await c.toggle(0);
    final pending = c.ask('x', yes);
    while (!c.busy) {
      await Future<void>.delayed(Duration.zero);
    }
    c.cancel();
    gate.complete();
    await pending;
    expect(c.busy, isFalse);
    expect(c.suggestions, isEmpty);
    expect(c.error, isNull);
  });

  test('a paragraph the answer leaves unchanged yields no suggestion',
      () async {
    final c = make((_) => _ok('[1] one'));
    await c.toggle(0);
    await c.ask('x', yes);
    expect(c.error, ImproveError.nothing);
  });
}
