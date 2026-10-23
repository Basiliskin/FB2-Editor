import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Image;
import 'package:image/image.dart' as img;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart' as app;
import 'package:quill_fb2/services/app.service.dart' show AppService;
import 'package:quill_fb2/utils/consts.dart';

const _fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Sample</book-title><lang>en</lang></title-info>
<document-info><id>doc-1</id></document-info></description>
<body><section><title><p>Ch</p></title><p>Hi</p></section></body>
</FictionBook>''';

class _FakePicker extends FilePicker with MockPlatformInterfaceMixin {
  FilePickerResult? result;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

class _ThrowingMap extends MapBase<String, dynamic> {
  @override
  dynamic operator [](Object? key) => throw StateError('boom');
  @override
  void operator []=(String key, dynamic value) {}
  @override
  void clear() {}
  @override
  Iterable<String> get keys => const [];
  @override
  dynamic remove(Object? key) => null;
}

class _ThrowingLoadService extends AppService {
  @override
  Future loadFile(filePath) async => throw StateError('boom');
}

PlatformFile _pf(String name, String path) =>
    PlatformFile(name: name, size: 1, path: path);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late AppService service;
  late _FakePicker picker;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('app_service_io_test');
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path);
    service = AppService();
    picker = _FakePicker();
    FilePicker.platform = picker;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_archive'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_file_dialog'), null);
    docs.deleteSync(recursive: true);
  });

  test('setLanguage stores the language and persists', () async {
    await service.setLanguage('ru');
    expect(service.workspace['language'], 'ru');
    expect(File('${docs.path}/fb2_workspace.json').existsSync(), isTrue);
  });

  test('translate returns the key when settings are broken', () {
    service.workspace['workspaceSettings'] = 'not a map';
    expect(service.translate(LangTranslateItems.bookTitle),
        LangTranslateItems.bookTitle);
  });

  test('getSettings falls back to defaults without workspaceSettings', () {
    service.workspace['workspaceSettings'] = null;
    expect(service.getSettings()['font-size'], 12);
  });

  test('setSettings falls back to defaults without workspaceSettings',
      () async {
    service.workspace['workspaceSettings'] = null;
    await service.setSettings({'font-size': 9});
    expect(service.getSettings()['font-size'], 9);
    expect(service.getSettings()['language'], 'eng');
  });

  test('deltaToXml converts every op and sectionToDeltaJson is a delta', () {
    final delta = Delta()
      ..insert('a', {'bold': true})
      ..insert('b');
    expect(service.deltaToXml(delta), '<strong>a</strong>b');
  });

  test('encoder pretty prints JSON with two-space indent', () {
    expect(app.encoder.convert({'a': 1}), '{\n  "a": 1\n}');
  });

  test('base64Image returns an Image widget for valid data when not asking '
      'for a provider', () {
    final b = base64Encode(img.encodePng(img.Image(width: 2, height: 2)));
    expect(service.base64Image(b, false), isA<Image>());
  });

  test('loadBook returns null when reading the entry throws', () async {
    expect(await service.loadBook(_ThrowingMap()), isNull);
  });

  test('currentProject starts empty', () {
    expect(service.currentProject, isEmpty);
  });

  test('exportProject asks the file dialog to save the stored book',
      () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_file_dialog'),
        (call) async {
      seen = call;
      return '/saved/here.fb2';
    });
    final model =
        ProjectModel.fromJson(await service.convertXmlToJson(_fb2));
    final r = await service.exportProject(model);
    expect(r, '/saved/here.fb2');
    expect(seen!.method, 'saveFile');
    expect(seen!.arguments['sourceFilePath'],
        '${docs.path}/${model.projectId}$BOOK_EXT');
  });

  test('sectionToDeltaJson delegates to the section', () async {
    final model =
        ProjectModel.fromJson(await service.convertXmlToJson(_fb2));
    final section = model.section.first;
    expect(service.sectionToDeltaJson(section), isNotNull);
  });

  group('loadZipFile', () {
    void mockUnzip(void Function(Directory dest) onUnzip) {
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_archive'),
          (call) async {
        final dest = Directory(call.arguments['destinationDir'] as String);
        dest.createSync(recursive: true);
        onUnzip(dest);
        return null;
      });
    }

    test('returns the fb2 found in the extracted archive', () async {
      mockUnzip((d) => File('${d.path}/inner.fb2').writeAsStringSync(_fb2));
      final zip = File('${docs.path}/a.zip')..writeAsStringSync('zip');
      final info = await service.loadZipFile(zip.path);
      expect(info.data, _fb2);
      expect(info.path, endsWith('inner.fb2'));
    });

    test('returns null and cleans up when the archive has no fb2', () async {
      late Directory dest;
      mockUnzip((d) {
        dest = d;
        File('${d.path}/readme.txt').writeAsStringSync('x');
      });
      final zip = File('${docs.path}/a.zip')..writeAsStringSync('zip');
      expect(await service.loadZipFile(zip.path), isNull);
      expect(dest.existsSync(), isFalse);
    });
  });

  group('openFile', () {
    const exts = {'fb2': true, 'zip': true, 'txt': false};

    test('returns null when the user cancels', () async {
      picker.result = null;
      expect(await service.openFile(exts), isNull);
    });

    test('returns null for an extension that is not accepted', () async {
      picker.result = FilePickerResult([_pf('a.txt', '${docs.path}/a.txt')]);
      expect(await service.openFile(exts), isNull);
    });

    test('loads an fb2 file', () async {
      final src = Directory.systemTemp.createTempSync('picked');
      addTearDown(() => src.deleteSync(recursive: true));
      final f = File('${src.path}/Book.FB2')..writeAsStringSync(_fb2);
      picker.result = FilePickerResult([_pf('Book.FB2', f.path)]);
      final info = await service.openFile(exts);
      expect(info.data, _fb2);
    });

    test('loads a zip file via the archive plugin', () async {
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_archive'),
          (call) async {
        final dest = Directory(call.arguments['destinationDir'] as String)
          ..createSync(recursive: true);
        File('${dest.path}/x.fb2').writeAsStringSync(_fb2);
        return null;
      });
      final zip = File('${docs.path}/a.zip')..writeAsStringSync('zip');
      picker.result = FilePickerResult([_pf('a.zip', zip.path)]);
      final info = await service.openFile(exts);
      expect(info.data, _fb2);
    });

    test('swallows errors from loading and returns null', () async {
      picker.result = FilePickerResult([_pf('a.fb2', '${docs.path}/a.fb2')]);
      expect(await _ThrowingLoadService().openFile(exts), isNull);
    });
  });
}
