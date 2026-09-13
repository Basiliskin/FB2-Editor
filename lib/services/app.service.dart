import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'fb2.service.dart';

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
    "language": "eng"
  },
  "currentProject": "",
  "history": [],
  "createdAt": null,
  "updatedAt": null
};
const DEFAULT_PROJECT = {"createdAt": null, "updatedAt": null, "image": ""};
const DEFAULT_IMAGE = 'images/book.png';

class FileInfo {
  final String data;
  final String path;
  FileInfo(this.data, this.path);
}

class AppService {
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
      Map tranlation =
          _translationService.getTranslations(settings["language"] ?? "eng");
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

  exportProject(ProjectModel model) async {
    final path = await _localPath;
    String currentProjectPath = '$path/${model.projectId}$BOOK_EXT';
    final params = SaveFileDialogParams(sourceFilePath: currentProjectPath);
    final filePath = await FlutterFileDialog.saveFile(params: params);
    return filePath;
  }

  saveProject(ProjectModel model) async {
    final path = await _localPath;
    String currentProjectPath = '$path/${model.projectId}$BOOK_EXT';
    Map info = await model.getInfo(null, currentProjectPath);
    final filtered = _workspace["history"]
        .where((i) => i['projectId'] != model.projectId)
        .toList();
    _workspace["history"] = [...filtered, info];
    await save();
    final bookXml = model.getBookXml();
    print(currentProjectPath);
    print(bookXml.length);
    final file = File(currentProjectPath);
    await file.writeAsString(bookXml);
  }

  removeProject(model) async {
    final filtered = _workspace["history"]
        .where((i) => i['projectId'] != model['projectId'])
        .toList();
    _workspace["history"] = [...filtered];

    await save();
  }

  getSettings() {
    Map settings = _workspace["workspaceSettings"] ??
        DEFAULT_WORKSPACE["workspaceSettings"];
    return settings;
  }

  setSettings(settings) async {
    Map current = _workspace["workspaceSettings"] ??
        DEFAULT_WORKSPACE["workspaceSettings"];

    var settingsMap = {};
    settingsMap.addAll(current);
    settingsMap.addAll(settings);
    _workspace["workspaceSettings"] = settingsMap;
    await save();
  }

  addProject(projectData, fileInfo, book) async {
    String projId = book != null ? book['projectId'] : '';
    ProjectModel model = ProjectModel.fromJson(projectData, projId);
    if (fileInfo != null && book == null) {
      final path = await _localPath;
      String currentProjectPath = '$path/${model.projectId}$BOOK_EXT';
      Map info = await model.getInfo(fileInfo, currentProjectPath);

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
    var json = delta.toJson();
    print(json);
    List<String> xml = [];
    json.forEach((d) {
      xml.add(handleDeltaInsert(d));
    });
    return xml.join();
  }

  sectionToDeltaJson(Section section) {
    return section.toDelta();
  }

  get currentProject {
    return _project;
  }

  base64Image(base64, provider) {
    if (base64 != "")
      try {
        Uint8List _image = decode64Image(base64);
        final img = provider
            ? MemoryImage(_image)
            : Image.memory(_image,
                gaplessPlayback: true); // assign it value here
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
    final path = await _workspacePath;
    _workspace = await loadJsonFile(path, DEFAULT_WORKSPACE);
  }

  Future<File> save() async {
    _workspace["updatedAt"] = DateTime.now();

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

  convertXmlToJson(xml) async {
    return _fb2Service.convertXmlToJson(xml);
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
      File file = await moveFileTo(filePath, appPath);
      String text = await readAsString(file); //.readAsString(encoding: utf8);
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
          zipFile: zipFile, destinationDir: destinationDir);
      final files = destinationDir.listSync();
      File file = File(files.first.path);
      String text = await readAsString(file); //.readAsString(encoding: utf8);
      print(filePath);
      print(text.length);
      return FileInfo(text, file.path);
    } catch (e) {
      print(e);
    }
    return null;
  }

  openFile(Map extensionNames) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      // allowedExtensions: [extensionName],
    );
    if (result != null) {
      final file = result.files.first;
      final ext = file.extension;
      if (extensionNames[ext]) {
        try {
          // final name = file.name;
          final path = file.path;
          // final size = file.size;
          final xml =
              ext == 'fb2' ? await loadFile(path) : await loadZipFile(path);
          return xml;
        } catch (e) {
          print(e);
        }
      }
    }
  }
}
