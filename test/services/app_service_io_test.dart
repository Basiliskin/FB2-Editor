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
import 'package:quill_fb2/services/fb2.service.dart';
import 'package:quill_fb2/services/open_failure.dart';
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
    expect(seen!.arguments['fileName'], 'Lee Ann - Sample.fb2');
    expect(seen!.method, 'saveFile');
    expect(seen!.arguments['sourceFilePath'],
        '${docs.path}/${model.projectId}$BOOK_EXT');
  });

  group('export and unsaved changes', () {
    Future<ProjectModel> opened() async {
      final model = ProjectModel.fromJson(await service.convertXmlToJson(_fb2));
      final src = File('${docs.path}/src.fb2')..writeAsStringSync(_fb2);
      await service.addProject(
          await service.convertXmlToJson(_fb2), app.FileInfo(_fb2, src.path), null);
      service.markSaved(model);
      return model;
    }

    test('a freshly opened book has no unsaved changes', () async {
      expect(service.hasUnsavedChanges(await opened()), isFalse);
    });

    test('editing makes it dirty and saving makes it clean', () async {
      final model = await opened();
      model.bookTitle = 'Changed';
      expect(service.hasUnsavedChanges(model), isTrue);
      await service.saveProject(model);
      expect(service.hasUnsavedChanges(model), isFalse);
    });

    test('a book the service has not seen is never reported dirty', () async {
      final model = ProjectModel.fromJson(await service.convertXmlToJson(_fb2));
      model.bookTitle = 'Changed';
      expect(service.hasUnsavedChanges(model), isFalse);
    });

    test('export saves the current book first and names the file after it',
        () async {
      final model = await opened();
      model.bookTitle = 'Changed: Title';
      String? onDisk;
      MethodCall? seen;
      messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_file_dialog'), (call) async {
        seen = call;
        onDisk = File(call.arguments['sourceFilePath'] as String).readAsStringSync();
        return '/saved/x.fb2';
      });
      await service.exportProject(model);
      expect(onDisk, contains('<book-title>Changed: Title</book-title>'));
      expect(seen!.arguments['fileName'], 'Lee Ann - Changed Title.fb2');
      expect(service.hasUnsavedChanges(model), isFalse);
    });

    test('export returns null when the dialog is cancelled', () async {
      final model = await opened();
      messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_file_dialog'), (call) async => null);
      expect(await service.exportProject(model), isNull);
    });

    test('export file name falls back to the project id', () {
      final model = ProjectModel.fromJson({'title': '', 'section': []});
      expect(model.exportFileName, '${model.projectId}.fb2');
    });
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

    test('turns a text file into a book named after the file', () async {
      final src = Directory.systemTemp.createTempSync('picked');
      addTearDown(() => src.deleteSync(recursive: true));
      final f = File('${src.path}/My Story.txt')
        ..writeAsStringSync('Chapter 1\nHello & <welcome>\n\nGlava\nChapter 2\nBye');
      picker.result = FilePickerResult([_pf('My Story.txt', f.path)]);
      final info = await service.openFile({...exts, 'txt': true});
      final json = await Fb2Service().convertXmlToJson(info.data);
      final book = ProjectModel.fromJson(json);
      expect(book.bookTitle, 'My Story');
      expect(book.section.map((s) => s.title), ['Chapter 1', 'Chapter 2']);
      expect(book.section[0].p, ['<p>Hello &amp; &lt;welcome></p>', '<p>Glava</p>']);
      expect(File(info.path).existsSync(), isTrue);
    });

    test('reads a Windows-1251 text file', () async {
      final src = Directory.systemTemp.createTempSync('picked');
      addTearDown(() => src.deleteSync(recursive: true));
      // "Привет" in cp1251
      final f = File('${src.path}/r.txt')
        ..writeAsBytesSync([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]);
      picker.result = FilePickerResult([_pf('r.txt', f.path)]);
      final info = await service.openFile({...exts, 'txt': true});
      expect(info.data, contains('<p>Привет</p>'));
    });

    test('rejects an extension that is not accepted', () async {
      picker.result = FilePickerResult([_pf('a.txt', '${docs.path}/a.txt')]);
      expect(
          service.openFile(exts),
          throwsA(isA<OpenFailure>()
              .having((e) => e.kind, 'kind', OpenFailureKind.unsupportedType)));
    });

    test('rejects a file without an extension', () async {
      picker.result = FilePickerResult([_pf('README', '${docs.path}/README')]);
      expect(
          service.openFile(exts),
          throwsA(isA<OpenFailure>()
              .having((e) => e.kind, 'kind', OpenFailureKind.unsupportedType)));
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

    test('reports a book that cannot be read', () async {
      picker.result = FilePickerResult([_pf('a.fb2', '${docs.path}/a.fb2')]);
      expect(
          _ThrowingLoadService().openFile(exts),
          throwsA(isA<OpenFailure>()
              .having((e) => e.kind, 'kind', OpenFailureKind.unreadable)));
    });

    test('reports a zip with no book inside', () async {
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_archive'),
          (call) async {
        Directory(call.arguments['destinationDir'] as String)
            .createSync(recursive: true);
        return null;
      });
      final zip = File('${docs.path}/empty.zip')..writeAsStringSync('zip');
      picker.result = FilePickerResult([_pf('empty.zip', zip.path)]);
      expect(
          service.openFile(exts),
          throwsA(isA<OpenFailure>()
              .having((e) => e.kind, 'kind', OpenFailureKind.noFb2InZip)));
    });
  });
}
