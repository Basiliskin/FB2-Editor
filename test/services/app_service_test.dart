import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/quill_delta.dart' show Operation;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/consts.dart';

const _fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Sample</book-title><lang>en</lang></title-info>
<document-info><id>doc-1</id></document-info></description>
<body><section><title><p>Ch</p></title><p>Hi</p></section></body>
</FictionBook>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late AppService service;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('app_service_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
    service = AppService();
  });

  tearDown(() => docs.deleteSync(recursive: true));

  Map entry(String id) => {'projectId': id, 'title': id};

  group('handleDeltaInsert', () {
    String run(Map<String, dynamic>? attrs) =>
        service.handleDeltaInsert(Operation.insert('x', attrs));

    test('returns plain text without attributes', () => expect(run(null), 'x'));
    test('wraps bold in strong', () => expect(run({'bold': true}), '<strong>x</strong>'));
    test('wraps italic in emphasis',
        () => expect(run({'italic': true}), '<emphasis>x</emphasis>'));
    test('nests strong inside emphasis when both are set', () {
      expect(run({'bold': true, 'italic': true}),
          '<emphasis><strong>x</strong></emphasis>');
    });
    test('wraps blockquote in cite around inline formatting', () {
      expect(run({'blockquote': true, 'bold': true}),
          '<cite><strong>x</strong></cite>');
    });
    test('ignores false attributes', () => expect(run({'bold': false}), 'x'));
  });

  test('addXml wraps a value in a tag', () {
    expect(service.addXml('p', 'v'), '<p>v</p>');
  });

  group('settings', () {
    test('getSettings returns defaults', () {
      expect(service.getSettings()['font-size'], 12);
    });
    test('setSettings merges and persists to the workspace file', () async {
      await service.setSettings({'font-size': 18});
      expect(service.getSettings()['font-size'], 18);
      expect(service.getSettings()['language'], 'eng');
      final saved = jsonDecode(
          File('${docs.path}/fb2_workspace.json').readAsStringSync());
      expect(saved['workspaceSettings']['font-size'], 18);
    });
  });

  group('translate', () {
    test('falls back to the key when the language is unknown', () async {
      await service.setSettings({'language': 'zzz'});
      expect(service.translate(LangTranslateItems.bookTitle),
          LangTranslateItems.bookTitle);
    });
  });

  group('loadJsonFile', () {
    test('returns a copy of the default for a missing file', () async {
      final r = await service.loadJsonFile('${docs.path}/nope.json', {'a': 1});
      expect(r, {'a': 1});
    });
    test('returns the default for corrupt JSON', () async {
      final f = File('${docs.path}/bad.json')..writeAsStringSync('{oops');
      expect(await service.loadJsonFile(f.path, {'a': 1}), {'a': 1});
    });
    test('parses valid JSON', () async {
      final f = File('${docs.path}/ok.json')..writeAsStringSync('{"b":2}');
      expect(await service.loadJsonFile(f.path, {}), {'b': 2});
    });
  });

  group('init / save', () {
    test('init loads a previously saved workspace', () async {
      await service.setSettings({'font-size': 20});
      final other = AppService();
      await other.init();
      expect(other.getSettings()['font-size'], 20);
    });
    test('init falls back to defaults when no workspace file exists', () async {
      await service.init();
      expect(service.workspace['history'], isEmpty);
    });
  });

  group('removeProject', () {
    test('removes only the matching entry', () async {
      service.workspace['history'] = [entry('a'), entry('b')];
      await service.removeProject(entry('a'));
      expect(service.workspace['history'], [entry('b')]);
    });
  });

  group('addProject', () {
    Future<ProjectModel> add() async {
      final json = await service.convertXmlToJson(_fb2);
      final src = File('${docs.path}/src_${DateTime.now().microsecondsSinceEpoch}.fb2')
        ..writeAsStringSync(_fb2);
      return await service.addProject(json, FileInfo(_fb2, src.path), null);
    }

    test('moves the file into the app dir and records history', () async {
      final model = await add();
      final history = service.workspace['history'] as List;
      expect(history, hasLength(1));
      expect(history.first['projectId'], model.projectId);
      expect(history.first['title'], 'Sample');
      expect(File(history.first['path']).existsSync(), isTrue);
      expect(service.workspace['createdAt'], isNotNull);
    });

    test('drops the oldest entry once history is full', () async {
      service.workspace['history'] = [
        for (var i = 0; i < MAX_BOOK_IN_HISTORY; i++) entry('old$i')
      ];
      await add();
      final history = service.workspace['history'] as List;
      expect(history, hasLength(MAX_BOOK_IN_HISTORY));
      expect(history.any((h) => h['projectId'] == 'old0'), isFalse);
    });

    test('replaces an existing entry when updating a book', () async {
      service.workspace['history'] = [entry('a'), entry('b')];
      final json = await service.convertXmlToJson(_fb2);
      await service.addProject(json, null, {'projectId': 'a', 'title': 'new'});
      final history = service.workspace['history'] as List;
      expect(history.where((h) => h['projectId'] == 'a'), hasLength(1));
      expect(history.firstWhere((h) => h['projectId'] == 'a')['title'], 'new');
    });
  });

  group('saveProject', () {
    test('writes the book xml and upserts history', () async {
      final json = await service.convertXmlToJson(_fb2);
      final model = ProjectModel.fromJson(json);
      await service.saveProject(model);
      await service.saveProject(model);
      final file = File('${docs.path}/${model.projectId}.fb2');
      expect(file.readAsStringSync(), contains('<FictionBook'));
      expect(service.workspace['history'], hasLength(1));
    });
  });

  group('loadFile / loadBook', () {
    test('reads a UTF-8 fb2 and moves it into the app dir', () async {
      final src = Directory.systemTemp.createTempSync('src');
      addTearDown(() => src.deleteSync(recursive: true));
      final f = File('${src.path}/b.fb2')..writeAsStringSync(_fb2);
      final info = await service.loadFile(f.path);
      expect(info.data, _fb2);
      expect(info.path, '${docs.path}/b.fb2');
    });
    test('loadFile returns null for a missing file', () async {
      expect(await service.loadFile('${docs.path}/missing.fb2'), isNull);
    });
    test('loadBook loads by the entry path', () async {
      final f = File('${docs.path}/c.fb2')..writeAsStringSync(_fb2);
      final info = await service.loadBook({'path': f.path});
      expect(info.data, _fb2);
    });
  });

  group('loadZipFile', () {
    test('returns null when the archive cannot be read', () async {
      final f = File('${docs.path}/broken.zip')..writeAsStringSync('not a zip');
      expect(await service.loadZipFile(f.path), isNull);
    });
  });

  group('base64Image cache', () {
    String png(int w) =>
        base64Encode(img.encodePng(img.Image(width: w, height: 4)));

    test('returns providers that share decoded bytes for the same data', () {
      final b = png(8);
      final a1 = service.base64Image(b, true) as MemoryImage;
      final a2 = service.base64Image(b, true) as MemoryImage;
      expect(identical(a1.bytes, a2.bytes), isTrue);
      expect(a1, equals(a2));
    });

    test('different data yields different bytes', () {
      final a = service.base64Image(png(8), true) as MemoryImage;
      final b = service.base64Image(png(9), true) as MemoryImage;
      expect(identical(a.bytes, b.bytes), isFalse);
    });

    test('still decodes correctly after the cache has evicted entries', () {
      final first = png(2);
      final firstBytes = (service.base64Image(first, true) as MemoryImage).bytes;
      for (var i = 3; i < 25; i++) {
        service.base64Image(png(i), true);
      }
      final again = (service.base64Image(first, true) as MemoryImage).bytes;
      expect(again, firstBytes); // equal content, re-decoded
    });

    test('invalid data is not cached and falls back to the asset', () {
      expect(service.base64Image('!!bad!!', true), isA<AssetImage>());
      expect(service.base64Image('!!bad!!', true), isA<AssetImage>());
    });
  });

  group('base64Image', () {
    test('falls back to the default asset on invalid data', () {
      final img = service.base64Image('!!not-an-image!!', true);
      expect(img, isA<ImageProvider>());
    });
    test('falls back to the default asset for an empty string', () {
      expect(service.base64Image('', false), isA<Image>());
    });
  });
}
