import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/utils/file_download.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import 'fb2.service.dart';
import 'open_failure.dart';

const bool isProduction = bool.fromEnvironment('dart.vm.product');
final JsonEncoder encoder = new JsonEncoder.withIndent('  ');
const DEFAULT_MAP = {};
const DEFAULT_WORKSPACE = {
  "workspaceSettings": {
    "auto-save": "false",
    "show-image": false,
    "image-width": "600",
    "font-size": 12,
    "image-quality": 'best',
    "language": "eng",
  },
  "currentProject": "",
  "history": [],
  "createdAt": null,
  "updatedAt": null,
};
const DEFAULT_PROJECT = {"createdAt": null, "updatedAt": null, "image": ""};
const DEFAULT_IMAGE = 'images/book.png';

class FileInfo {
  final String data;
  final String path;
  FileInfo(this.data, this.path);
}

/// Parse time budget: generous for slow phones, finite so a bad file cannot spin forever.
Duration defaultParseTimeout(int chars) =>
    Duration(seconds: 90 + 10 * (chars / (1024 * 1024)).ceil());

class AppService {
  Duration Function(int chars) parseTimeout = defaultParseTimeout;
  late TranslationService _translationService = new TranslationService();
  late Fb2Service _fb2Service = Fb2Service();
  String _workspaceFile = 'fb2_workspace.json';
  Map _workspace = cloneMap(DEFAULT_WORKSPACE);
  late Map _project = {};
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  setLanguage(String language) async {
    _workspace["language"] = language;
    await save();
  }

  translate(LangTranslateItems name) {
    try {
      final settings = getSettings();
      Map tranlation = _translationService.getTranslations(
        settings["language"] ?? "eng",
      );
      return tranlation[name] ?? name;
    } catch (e) {
      print(e);
    }
    return name;
  }

  Future<String> get _workspacePath async {
    final path = await _localPath;
    return '$path/$_workspaceFile';
  }

  /// Saves the book into the app first, so the exported file is never older than
  /// the screen, then asks where to put it. Returns the saved location, or null
  /// when the user cancelled the dialog.
  exportProject(ProjectModel model) async {
    // coverage:ignore-start
    if (kIsWeb) {
      await downloadFile(model.exportFileName, model.getBookXml());
      return model.exportFileName;
    }
    // coverage:ignore-end
    await saveProject(model);
    final path = await _localPath;
    String currentProjectPath = '$path/${model.projectId}$BOOK_EXT';
    final params = SaveFileDialogParams(
        sourceFilePath: currentProjectPath, fileName: model.exportFileName);
    return FlutterFileDialog.saveFile(params: params);
  }

  // fingerprint of each book as last written to the app, to detect unsaved edits
  final Map<String, int> _savedFingerprint = {};

  void markSaved(ProjectModel model, [String? xml]) {
    _savedFingerprint[model.projectId] = (xml ?? model.getBookXml()).hashCode;
  }

  /// True when [model] differs from what was last saved or opened.
  bool hasUnsavedChanges(ProjectModel model) {
    final saved = _savedFingerprint[model.projectId];
    return saved != null && saved != model.getBookXml().hashCode;
  }

  saveProject(ProjectModel model) async {
    // coverage:ignore-start
    if (kIsWeb) {
      final currentProjectPath = '${model.projectId}$BOOK_EXT';
      final info = await model.getInfo(null, currentProjectPath);
      final filtered = _workspace["history"]
          .where((i) => i['projectId'] != model.projectId)
          .toList();
      _workspace["history"] = [...filtered, info];
      await save();
      await downloadFile(model.exportFileName, model.getBookXml());
      markSaved(model);
      return;
    }
    // coverage:ignore-end
    final path = await _localPath;
    String currentProjectPath = '$path/${model.projectId}$BOOK_EXT';
    Map info = await model.getInfo(null, currentProjectPath);
    final filtered = _workspace["history"]
        .where((i) => i['projectId'] != model.projectId)
        .toList();
    _workspace["history"] = [...filtered, info];
    await save();
    final bookXml = model.getBookXml();
    final file = File(currentProjectPath);
    await file.writeAsString(bookXml);
    markSaved(model, bookXml);
  }

  removeProject(model) async {
    final filtered = _workspace["history"]
        .where((i) => i['projectId'] != model['projectId'])
        .toList();
    _workspace["history"] = [...filtered];

    await save();
  }

  getSettings() {
    Map settings =
        _workspace["workspaceSettings"] ??
        DEFAULT_WORKSPACE["workspaceSettings"];
    return settings;
  }

  setSettings(settings) async {
    Map current =
        _workspace["workspaceSettings"] ??
        DEFAULT_WORKSPACE["workspaceSettings"];

    var settingsMap = {};
    settingsMap.addAll(current);
    settingsMap.addAll(settings);
    _workspace["workspaceSettings"] = settingsMap;
    await save();
  }

  addProject(projectData, fileInfo, book) async {
    String projId = book != null ? book['projectId'] : '';
    final sw = Stopwatch()..start();
    ProjectModel model = ProjectModel.fromJson(projectData, projId);
    markSaved(model);
    if (kDebugMode) debugPrint('[load] build model: ${sw.elapsedMilliseconds} ms');
    if (fileInfo != null && book == null) {
      final currentProjectPath = kIsWeb
          ? fileInfo.path // coverage:ignore-line
          : '${await _localPath}/${model.projectId}$BOOK_EXT';
      Map info = await timed('book info + cover thumbnail',
          () async => await model.getInfo(
                kIsWeb ? null : fileInfo,
                currentProjectPath,
              ));

      _workspace["currentProject"] = currentProjectPath;
      if (_workspace["history"].length >= MAX_BOOK_IN_HISTORY)
        _workspace["history"].removeAt(0);
      _workspace["history"].add(info);
      if (workspace["createdAt"] == null)
        _workspace["createdAt"] = DateTime.now();
      await save();
    } else {
      //book
      final filtered = _workspace["history"]
          .where((i) => i['projectId'] != book['projectId'])
          .toList();
      _workspace["history"] = [...filtered, book];

      await save();
    }
    return model;
  }

  addXml(tag, value) {
    return "<$tag>$value</$tag>";
  }

  handleDeltaInsert(item) {
    bool isEmphasis =
        item.attributes != null && item.attributes.containsKey('italic')
        ? item.attributes['italic']
        : false;
    bool isStrong =
        item.attributes != null && item.attributes.containsKey('bold')
        ? item.attributes['bold']
        : false;
    bool isBlockquote =
        item.attributes != null && item.attributes.containsKey('blockquote')
        ? item.attributes['blockquote']
        : false;
    var result = item.value;
    if (isEmphasis && isStrong) {
      result = addXml('emphasis', addXml('strong', item.value));
    } else if (isEmphasis) {
      result = addXml('emphasis', item.value);
    } else if (isStrong) {
      result = addXml('strong', item.value);
    }
    return isBlockquote ? addXml('cite', result) : result;
  }

  deltaToXml(delta) {
    return delta.toList().map(handleDeltaInsert).join();
  }

  sectionToDeltaJson(Section section) {
    return section.toDelta();
  }

  get currentProject {
    return _project;
  }

  // decoded bytes by base64 string; a stable list keeps MemoryImage cache hits
  final Map<String, Uint8List> _imageCache = {};

  base64Image(base64, provider) {
    if (base64 != "")
      try {
        Uint8List? _image = _imageCache.remove(base64);
        _image ??= decode64Image(base64) as Uint8List;
        _imageCache[base64] = _image;
        if (_imageCache.length > 16) _imageCache.remove(_imageCache.keys.first);
        final img = provider
            ? MemoryImage(_image)
            : Image.memory(
                _image,
                gaplessPlayback: true,
              ); // assign it value here
        return img;
      } catch (e) {
        print(e);
      }
    return provider ? AssetImage(DEFAULT_IMAGE) : Image.asset(DEFAULT_IMAGE);
  }

  get workspace {
    return _workspace;
  }

  init() async {
    if (kIsWeb) {
      return;
    }
    final path = await _workspacePath;
    _workspace = await loadJsonFile(path, DEFAULT_WORKSPACE);
  }

  Future<File?> save() async {
    _workspace["updatedAt"] = DateTime.now();

    if (kIsWeb) {
      return null;
    }

    final path = await _workspacePath;
    final file = File(path);
    String json = toJSonString(_workspace);
    return file.writeAsString(json);
  }

  Future loadJsonFile(filePath, defaultValue) async {
    try {
      final file = File('$filePath');
      String json = await file.readAsString();
      Map map = jsonDecode(json);
      return map;
    } catch (e) {
      print(e);
    }
    return cloneMap(defaultValue);
  }

  /// Throws [OpenFailure] when the text is not an FB2 book or parsing times out.
  convertXmlToJson(xml) async {
    final json = await timed(
        'parse xml (${(xml.length / 1024).round()} KB)',
        () async => _fb2Service.convertXmlToJson(xml).timeout(
            parseTimeout(xml.length),
            onTimeout: () => throw const OpenFailure(OpenFailureKind.timeout)));
    if (json == null) throw const OpenFailure(OpenFailureKind.notFb2);
    return json;
  }

  loadBook(Map book) async {
    try {
      final xml = await loadFile(book['path']);
      return xml;
    } catch (e) {
      print(e);
    }
  }

  Future loadFile(filePath) async {
    try {
      final appPath = await _localPath;
      File file = await timed<File>('copy to app dir',
          () async => await moveFileTo(filePath, appPath) as File);
      String text = await timed<String>(
          'read+decode', () async => await readAsString(file) as String);
      print(filePath);
      print(text.length);
      return FileInfo(text, file.path);
    } catch (e) {
      print(e);
    }
    return null;
  }

  Future loadZipFile(filePath) async {
    try {
      final appPath = await _localPath;
      File zipFile = File(filePath);
      final destinationDir = Directory("$appPath/${getRandomString(16)}");
      await ZipFile.extractToDirectory(
        zipFile: zipFile,
        destinationDir: destinationDir,
      );
      final file = findFb2File(destinationDir);
      if (file == null) {
        await destinationDir.delete(recursive: true);
        return null;
      }
      String text = await readAsString(file); //.readAsString(encoding: utf8);
      print(filePath);
      print(text.length);
      return FileInfo(text, file.path);
    } catch (e) {
      print(e);
    }
    return null;
  }

  /// An empty book with one empty chapter, ready to open like any picked file.
  Future<FileInfo> createBook(String title, String chapter) =>
      _storeNewBook(newBookXml(title, chapter));

  Future<FileInfo> _storeNewBook(String xml) async {
    final name = 'new-${getRandomString(8)}$BOOK_EXT';
    if (kIsWeb) return FileInfo(xml, name); // coverage:ignore-line
    final file = File('${await _localPath}/$name');
    await file.writeAsString(xml);
    return FileInfo(xml, file.path);
  }

  /// Returns null when the user cancels the picker; throws [OpenFailure] otherwise.
  openFile(Map extensionNames) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: kIsWeb,
      // allowedExtensions: [extensionName],
    );
    if (result == null) return null;
    final file = result.files.first;
    final ext = file.extension?.toLowerCase();
    if (extensionNames[ext] != true) {
      throw OpenFailure(OpenFailureKind.unsupportedType, ext);
    }
    // coverage:ignore-start
    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null || ext != 'fb2') {
        throw OpenFailure(OpenFailureKind.unsupportedType, ext);
      }
      return FileInfo(decodeFb2Bytes(bytes), file.name);
    }
    // coverage:ignore-end
    final path = file.path;
    if (ext == 'txt') {
      try {
        final text = decodeFb2Bytes(await File(path!).readAsBytes());
        final title = file.name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');
        return await _storeNewBook(txtToFb2Xml(text, title));
      } catch (e) {
        throw OpenFailure(OpenFailureKind.unreadable, '$e');
      }
    }
    dynamic info;
    try {
      info = ext == 'fb2' ? await loadFile(path) : await loadZipFile(path);
    } catch (e) {
      throw OpenFailure(OpenFailureKind.unreadable, '$e');
    }
    if (info == null) {
      throw OpenFailure(ext == 'fb2'
          ? OpenFailureKind.unreadable
          : OpenFailureKind.noFb2InZip);
    }
    return info;
  }
}
