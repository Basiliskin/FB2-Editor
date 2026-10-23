import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:quill_fb2/models/story_map.model.dart';
import 'package:quill_fb2/services/story_map_analyzer.dart';
import 'package:xml/xml.dart';

import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';

import 'section.model.dart';

copyTo(list, dest, key) {
  list.forEach((elm) => dest.add(safeGet(elm, key, '')));
}

class CoverImage {
  String href = '';
  String alt = '';
  CoverImage(Map json) {
    json.keys.forEach((element) {
      if (element.indexOf('href') >= 0)
        href = json[element];
      else if (element.indexOf('alt') >= 0) alt = json[element];
    });
  }
}

class Author {
  String firstName = '';
  String middleName = '';
  String lastName = '';
  String homePage = '';
  String id = '';
  String nickname = '';
  String email = '';
  process(json) {
    final author = safeGet(json, 'author', []);
    if (author is Map) {
      load(author);
    } else {
      author.forEach((elm) => load(elm));
    }
  }

  Author(Map json) {
    process(json);
  }
  load(Map json, [attributeName = '.\$']) {
    firstName = safeGet(json, 'first-name$attributeName', firstName);
    middleName = safeGet(json, 'middle-name$attributeName', middleName);
    lastName = safeGet(json, 'last-name$attributeName', lastName);
    homePage = safeGet(json, 'home-page$attributeName', homePage);
    id = safeGet(json, 'id$attributeName', id);
    nickname = safeGet(json, 'nickname$attributeName', nickname);
    email = safeGet(json, 'email$attributeName', email);
  }

  toXml() {
    // first and last name are required by the schema; the rest only when filled in
    String tag(String name, String value, [bool always = false]) =>
        value.isEmpty && !always ? '' : '<$name>${escapeXml(value)}</$name>';
    return '<author>${tag('first-name', firstName, true)}'
        '${tag('middle-name', middleName)}${tag('last-name', lastName, true)}'
        '${tag('nickname', nickname)}${tag('home-page', homePage)}'
        '${tag('email', email)}${tag('id', id)}</author>';
  }
}

class Resource {
  late String id;
  late String contentType;
  late String data;
  late String sectionId;
  Resource(json) {
    id = safeGet(json, 'id', '');
    contentType = safeGet(json, 'contentType', '');
    data = safeGet(json, 'data', '');
    sectionId = safeGet(json, 'sectionId', '');
  }
}

class BinaryResources {
  List<Resource> resources = [];
  add(json) {
    Resource res = Resource(json);
    resources.add(res);
  }

  first() {
    return resources.first;
  }

  BinaryResources(json) {
    if (json is Map) {
      add(json);
    } else {
      json.forEach((elm) => add(elm));
    }
  }
  find(id) {
    return resources.firstWhere((element) => "#${element.id}" == id,
        orElse: () {
      return Resource({});
    });
  }

  findBySectionId(sectionId) {
    return resources.firstWhere(
        (element) => "${element.sectionId}" == sectionId, orElse: () {
      return Resource({});
    });
  }

  removeSectionImage(sectionId) {
    resources = resources.where((i) => "${i.sectionId}" != sectionId).toList();
    print(resources);
  }

  replace(id, data) {
    final item = find(id);
    if (item.id.isNotEmpty) {
      if (data.isEmpty) {
        resources = resources.where((i) => "#${i.id}" != id).toList();
      } else {
        item.data = data;
      }
    } else if (data.isNotEmpty) {
      add({"id": id.substring(1), "data": data, "contentType": "image/jpg"});
    }
  }

  toXml() {
    List<String> xml = [];
    resources.forEach((element) {
      xml.add(
          '<binary content-type="${element.contentType}" id="${element.id}" section-id="${element.sectionId}">');
      xml.add(element.data);
      xml.add('</binary>\n');
    });
    return xml.join();
  }
}

class ProjectModel {
  List<String> genre = [];
  List<String> sequence = [];
  String bookTitle = '';
  // The body heading as loaded, written back while the title is not edited:
  // it often holds more than the title (author line, line breaks).
  String _bodyTitle = '';
  String _loadedTitle = '';
  List<String> annotation = [];
  String date = '';
  String lang = '';
  String programUsed = '';
  String srcUrl = '';
  String documentDate = '';
  /// Raw XML of the bodies after the first (footnotes etc.), written back unchanged.
  List<String> extraBodies = [];
  String keywords = '';
  String id = '';
  String version = '';
  /// Raw description parts the editor does not model, per place, as {name, xml}.
  List<Map> titleInfoExtras = [];
  List<Map> documentInfoExtras = [];
  List<Map> descriptionExtras = [];
  String projectId = '';
  late CoverImage coverpage;
  late Author author;
  late BinaryResources binaryResource;
  List<Section> section = [];
  getAnnotation(json) {
    final a = safeGet(json, 'annotation.p', []);
    if (a is Map) {
      annotation.add(safeGet(a, '\$', ''));
    } else {
      a.forEach((elm) => {annotation.add(safeGet(elm, '\$', ''))});
    }
  }

  loadSection(Map json) {
    final title = safeGet(json, 'title', '');
    final sectionId = safeGet(json, 'sectionId', '');
    final _p = safeGet(json, 'p', []);
    var img = safeGet(json, 'img', []);
    final hadImage = img.length > 0;
    if (hadImage) {
      final imgRes = img
          .map((name) => binaryResource.find(name))
          .where((i) => i.id.isNotEmpty as bool)
          .toList();
      img = imgRes.map((res) => '#${res.id}').toList();
    }

    // A chapter is kept whole however long it is (the editor pages its paragraphs),
    // and so is one that has only a title or a picture, such as a new empty section.
    if (_p.length > 0 || '$title'.isNotEmpty || hadImage) {
      section.add(Section(
          {"title": "$title", "p": _p, "img": img, "sectionId": sectionId},
          binaryResource));
    }
  }

  loadSections(sections) {
    sections.forEach((s) => {loadSection(s)});
  }

  ProjectModel(json, [String projId = '']) {
    projectId = projId.isNotEmpty ? projId : getRandomString(16);
    _bodyTitle = safeGet(json, 'bodyTitle', '');
    final descriptionValue = safeGet(json, 'description.description', {});
    final description =
        descriptionValue is Map ? descriptionValue : <dynamic, dynamic>{};
    final titleValue = safeGet(description, 'title-info', {});
    final title = titleValue is Map ? titleValue : <dynamic, dynamic>{};
    final documentValue = safeGet(description, 'document-info', {});
    final document =
        documentValue is Map ? documentValue : <dynamic, dynamic>{};
    final sections = safeGet(json, 'sections', []);
    final resources = safeGet(json, 'resources', []);
    binaryResource = BinaryResources(resources);
    loadSections(sections);
    author = Author(title);
    getAnnotation(title);
    date = safeGet(title, 'date.\$', '');
    lang = safeGet(title, 'lang.\$', '');
    keywords = safeGet(title, 'keywords.\$', '');
    coverpage = CoverImage(safeGet(title, 'coverpage.image', {}));
    final coverPageFile = binaryResource.find(coverpage.href);
    if (coverPageFile.sectionId.isEmpty) {
      coverPageFile.sectionId = "cover";
    }
    bookTitle = safeGet(title, 'book-title.\$', '');
    if (bookTitle.isEmpty) bookTitle = _bodyTitle;
    _loadedTitle = bookTitle;
    programUsed = safeGet(document, 'program-used.\$', '');
    srcUrl = safeGet(document, 'src-url.\$', '');
    documentDate = safeGet(document, 'date.\$', '');
    final extras = safeGet(json, 'descriptionExtras', {});
    List<Map> extra(String k) => [...safeGet(extras, k, [])];
    titleInfoExtras = extra('titleInfo');
    documentInfoExtras = extra('documentInfo');
    descriptionExtras = extra('description');
    extraBodies = [...safeGet(json, 'extraBodies', <String>[])];
    id = safeGet(document, 'id.\$', '');
    version = safeGet(document, 'version.\$', '');
    print(title);

    // final d = safeGet(document, 'date.\$', date);
    final g = safeGet(title, 'genre', []);
    if (g is Map) {
      genre.add(safeGet(g, '\$', ''));
    } else {
      copyTo(g, genre, '\$');
    }
    final s = safeGet(title, 'sequence', []);
    if (s is Map) {
      sequence.add(safeGet(s, '\$', safeGet(s, '@name', '')));
    } else {
      copyTo(s, sequence, '@name');
    }

    if (coverpage.href.isEmpty && binaryResource.resources.length > 0) {
      coverpage.href = "#${binaryResource.resources[0].id}";
    }
  }
  factory ProjectModel.fromJson(json, [String projId = '']) {
    return ProjectModel(json, projId);
  }
  // thumbnail of the last cover resized, reused while the cover data is unchanged
  String? _thumbSource;
  Future? _thumb;

  getImage(res) async {
    if (res != null) {
      if (_thumb == null || !identical(_thumbSource, res.data)) {
        _thumbSource = res.data;
        _thumb = resizeImage(res.data, 120);
      }
      return _thumb;
    }
  }

  addSecionImage(section, data) {
    binaryResource.removeSectionImage(section.sectionId);
    (section.images as List).clear();
    if (data.isNotEmpty) {
      final type = sniffBase64ImageType(data);
      final json = {
        "id": "${getRandomString(7)}.${type.ext}",
        "contentType": type.contentType,
        "data": data,
        "sectionId": section.sectionId
      };
      binaryResource.add(json);
      section.setImage("#${json['id']}");
    }
  }

  /// Stores a picture and puts it in [section] after paragraph [after]
  /// (-1: before the first). Returns the index of the new block, or -1 when
  /// [data] is empty.
  int addInlineImage(Section section, String data, int after) {
    if (data.isEmpty) return -1;
    final type = sniffBase64ImageType(data);
    final id = "${getRandomString(7)}.${type.ext}";
    binaryResource.add({
      "id": id,
      "contentType": type.contentType,
      "data": data,
      "sectionId": section.sectionId
    });
    return section.insertImage(after, '#$id');
  }

  /// Removes picture block [index] of [section] and its data once nothing else uses it.
  void removeInlineImage(Section section, int index) {
    final href = imageHref(section.p[index]);
    section.p.removeAt(index);
    if (href == null) return;
    final used = this.section.any((s) => s.pictureRefs.contains(href)) ||
        coverpage.href == href;
    if (!used) {
      binaryResource.resources =
          binaryResource.resources.where((r) => '#${r.id}' != href).toList();
    }
  }

  getCoverPageImage() async {
    if (coverpage.href.isNotEmpty) {
      final res = binaryResource.findBySectionId('cover');
      return getImage(res);
    }
    return '';
  }

  getImageBySectionId(sectionId) {
    final res = binaryResource.findBySectionId(sectionId);
    if (res != null) return res.data;
    return '';
  }

  getAuthor() {
    return "${author.firstName} ${author.lastName}";
  }

  /// The book as plain text: title and author, then each section's title and
  /// paragraphs, separated by blank lines. Pictures are left out.
  String toPlainText() {
    String textOf(String block) {
      try {
        final root = XmlDocument.parse(block).rootElement;
        if (root.name.local == 'image') return '';
        if (root.name.local == 'poem') {
          return root
              .findAllElements('stanza')
              .map((st) => st.findElements('v').map((v) => v.innerText).join('\n'))
              .join('\n\n');
        }
        return root.innerText.trim();
      } catch (_) {
        return '';
      }
    }

    final out = <String>[
      [bookTitle, getAuthor().trim()].where((e) => e.isNotEmpty).join('\n')
    ];
    for (final sec in section) {
      out.add(sec.title);
      out.addAll(sec.p.map(textOf).where((t) => t.isNotEmpty));
    }
    return '${out.where((e) => e.isNotEmpty).join('\n\n')}\n';
  }

  /// "Author - Title.fb2", falling back to the project id so the name is never empty.
  String get exportFileName => '$exportBaseName$BOOK_EXT';

  /// "Author - Title" without an extension.
  String get exportBaseName {
    final who = safeFileName('${author.lastName} ${author.firstName}');
    final what = safeFileName(bookTitle);
    final name = [who, what].where((s) => s.isNotEmpty).join(' - ');
    return name.isEmpty ? projectId : name;
  }

  getBookTitle() {
    return "$bookTitle";
  }

  getLang() {
    return "$lang";
  }

  getSequence() {
    return sequence.join("| ");
  }

  getInfo(fileInfo, [String path = '']) async {
    if (path.isNotEmpty && fileInfo != null) {
      await moveFile(File(fileInfo.path), path);
    }
    return {
      "projectId": projectId,
      "updated": DateTime.now(),
      "cover": await getCoverPageImage(),
      "author": trimSpecialChar(getAuthor()),
      "lang": getLang(),
      "version": version,
      "sequence": getSequence(),
      "title": trimSpecialChar(getBookTitle()),
      "path": path.isNotEmpty ? path : fileInfo.path
    };
  }

  addSection([String? title = "New Section"]) {
    Section item = Section({"title": title, "p": []}, binaryResource);
    section.add(item);
    return item;
  }

  updateInfo(values) {
    final _bookCoverPage = values['bookCoverPage'];
    final _authorFirst = values['authorFirst'];
    final _authorMid = values['authorMid'];
    final _authorLast = values['authorLast'];
    final _authorHomePage = values['authorHomePage'];
    final _bookTitle = values['bookTitle'];
    final _genre = values['genre'];
    final _sequence = values['sequence'];
    final _annotation = values['annotation'];
    // fields the form may not carry (older callers) keep their value
    id = values['bookId'] ?? id;
    version = values['bookVersion'] ?? version;
    lang = (values['bookLang'] ?? lang).toString().trim();
    date = values['bookDate'] ?? date;
    keywords = values['bookKeywords'] ?? keywords;

    final current = binaryResource.findBySectionId('cover');
    if (_bookCoverPage.isEmpty) {
      binaryResource.removeSectionImage('cover');
      coverpage.href = '';
    } else if (current.id.isEmpty || current.data != _bookCoverPage) {
      // A new picture gets a new id so readers do not show their cached cover;
      // an untouched cover keeps its id, type and bytes.
      binaryResource.removeSectionImage('cover');
      final type = sniffBase64ImageType(_bookCoverPage);
      final json = {
        "id": "cover-${getRandomString(7)}.${type.ext}",
        "contentType": type.contentType,
        "data": _bookCoverPage,
        "sectionId": 'cover'
      };
      coverpage.href = "#${json["id"]}";
      binaryResource.add(json);
    }
    genre = [..._genre.items];
    sequence = [..._sequence.items];
    annotation = [..._annotation.items];
    print(annotation);
    bookTitle = _bookTitle;
    author.load({
      'first-name': _authorFirst,
      'middle-name': _authorMid,
      'last-name': _authorLast,
      'home-page': _authorHomePage,
      'email': values['authorEmail'] ?? author.email
    }, '');
  }

  addXml(tag, value) {
    return "<$tag>${escapeXml(value)}</$tag>";
  }

  /// Carried-through description parts with these names, in file order.
  static String _raw(List<Map> extras, Set<String> names) =>
      extras.where((e) => names.contains(e['name'])).map((e) => e['xml']).join();

  /// Carried-through parts whose name is not one of [placed].
  static String _rest(List<Map> extras, Set<String> placed) =>
      extras.where((e) => !placed.contains(e['name'])).map((e) => e['xml']).join();

  getBookXml() {
    List<String> xml = [];
    xml.add('<?xml version="1.0" encoding="UTF-8"?>');
    xml.add(
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink" xmlns:xlink="http://www.w3.org/1999/xlink">');
    xml.add('<description>');
    // element order follows the FB2 schema; strict readers drop out-of-order elements
    xml.add('<title-info>');
    genre.forEach((element) {
      xml.add(addXml('genre', element));
    });
    xml.add(author.toXml());
    xml.add(_raw(titleInfoExtras, {'author'}));
    xml.add(addXml('book-title', bookTitle));
    if (annotation.length > 0) {
      xml.add('<annotation>');
      annotation.forEach((element) {
        final lines = element.split('\n');
        lines.forEach((line) {
          if (line.isNotEmpty) xml.add(addXml('p', line));
        });
      });
      xml.add('</annotation>');
    }
    if (keywords.isNotEmpty) xml.add(addXml('keywords', keywords));
    if (date.isNotEmpty) xml.add(addXml('date', date));
    final coverRes = binaryResource.findBySectionId('cover');
    if (coverRes.id.isNotEmpty) {
      xml.add(
          '<coverpage><image l:href="#${escapeXml(coverRes.id)}" alt="coverpage"/></coverpage>');
    }
    if (lang.isNotEmpty) xml.add(addXml('lang', lang));
    xml.add(_raw(titleInfoExtras, {'src-lang', 'translator'}));
    sequence.forEach((element) {
      xml.add('<sequence name="${escapeXml(element)}"/>');
    });
    xml.add(_rest(titleInfoExtras, {'author', 'src-lang', 'translator'}));
    xml.add('</title-info>');
    xml.add(_raw(descriptionExtras, {'src-title-info'}));
    xml.add('<document-info>');
    // the file's own authors (scanner, editor) if it had any, else the book author
    final docAuthors = _raw(documentInfoExtras, {'author'});
    xml.add(docAuthors.isEmpty ? author.toXml() : docAuthors);
    xml.add(addXml('program-used', programUsed));
    xml.add(addXml('date', documentDate.isNotEmpty ? documentDate : date));
    xml.add(addXml('src-url', srcUrl));
    xml.add(_raw(documentInfoExtras, {'src-ocr'}));
    xml.add(addXml('id', id));
    xml.add(addXml('version', version));
    xml.add(_rest(documentInfoExtras, {'author', 'src-ocr'}));
    xml.add('</document-info>');
    xml.add(_rest(descriptionExtras, {'src-title-info'}));
    xml.add('</description>');
    xml.add('<body>');
    final heading = _bodyTitle.isNotEmpty && bookTitle == _loadedTitle
        ? _bodyTitle
        : bookTitle;
    xml.add('<title><p>${escapeXml(heading)}</p></title>');
    section.forEach((element) {
      xml.add(element.toXml());
    });
    xml.add('</body>');
    xml.addAll(extraBodies);
    xml.add(binaryResource.toXml());
    xml.add('</FictionBook>');
    return xml.join('\n');
  }

  // ---- story map ----
  // The map is kept in the book's description as <custom-info info-type="story-map">: a
  // standard FB2 element other readers ignore, carried through save and load like the other
  // description parts the editor does not model.

  StoryMap? _storyMap;

  static bool _isStoryMapPart(Map e) =>
      e['name'] == 'custom-info' && '${e['xml']}'.contains('info-type="story-map"');

  List<String> get _sectionIds => [for (final s in section) s.sectionId];
  List<String> get _sectionTitles => [
        for (var i = 0; i < section.length; i++)
          section[i].title.trim().isEmpty ? 'Section ${i + 1}' : trimSpecialChar(section[i].title, ' ')
      ];

  /// The map if it has been loaded already, lined up with the current sections; else null.
  StoryMap? get loadedStoryMap {
    final m = _storyMap;
    m?.realign(_sectionIds, _sectionTitles);
    return m;
  }

  /// The saved map, or one built from the text (people only), lined up with the current
  /// sections. Building runs off the main thread. Nothing is written to the book until
  /// [saveStoryMap], so merely opening the map never marks the book as changed.
  Future<StoryMap> loadStoryMap() async {
    var m = _storyMap;
    if (m == null) {
      for (final part in descriptionExtras) {
        if (!_isStoryMapPart(part)) continue;
        try {
          m = StoryMap.decode(XmlDocument.parse('${part['xml']}').rootElement.innerText, _sectionIds, _sectionTitles);
        } catch (_) {}
        if (m != null) break;
      }
    }
    final StoryMap map = m ?? await compute(analyzeSections, [for (final s in section) StorySection(s.sectionId, s.title, List.of(s.p))]);
    map.realign(_sectionIds, _sectionTitles);
    return _storyMap = map;
  }

  /// Writes [map] into the book so the next save or export carries it.
  void saveStoryMap(StoryMap map) {
    _storyMap = map;
    descriptionExtras.removeWhere(_isStoryMapPart);
    descriptionExtras.add({
      'name': 'custom-info',
      'xml': '<custom-info info-type="story-map">${escapeText(map.encode())}</custom-info>',
    });
  }

  /// Drops the saved map and any hand edits; the next [loadStoryMap] builds a fresh one.
  void discardStoryMap() {
    _storyMap = null;
    descriptionExtras.removeWhere(_isStoryMapPart);
  }

  static final _hrefRef = RegExp(r'((?:xlink|l):href=")#([^"]+)"');
  static final _idAttr = RegExp(r'(\sid=")([^"]+)"');

  /// Appends the chapters of [other] after this book's own, behind a heading
  /// section named after it. Pictures and footnotes come along under new ids
  /// (every id of [other] gets a prefix) so nothing clashes; the cover and
  /// metadata of this book stay as they are. Returns the number of sections added.
  int mergeFrom(ProjectModel other) {
    final taken = {
      ...binaryResource.resources.map((r) => r.id),
      ...extraBodies.expand((b) => _idAttr.allMatches(b).map((m) => m.group(2)!)),
    };
    var n = 1;
    String prefix() => 'm${n}_';
    while (taken.any((id) => id.startsWith(prefix()))) n++;
    final pre = prefix();

    final idMap = <String, String>{
      for (final r in other.binaryResource.resources) r.id: '$pre${r.id}',
      for (final b in other.extraBodies)
        for (final m in _idAttr.allMatches(b)) m.group(2)!: '$pre${m.group(2)}',
    };
    String rewrite(String xml) => xml.replaceAllMapped(_hrefRef,
        (m) => '${m.group(1)}#${idMap[m.group(2)] ?? m.group(2)}"');

    final used = <String>{};
    void note(String xml) {
      for (final m in _hrefRef.allMatches(xml)) {
        used.add(m.group(2)!);
      }
    }

    final added = <Section>[];
    if (other.bookTitle.isNotEmpty) {
      added.add(Section({"title": other.bookTitle, "p": [], "img": []}, binaryResource));
    }
    for (final sec in other.section) {
      final p = [for (final block in sec.p) rewrite(block)];
      p.forEach(note);
      added.add(Section({"title": sec.title, "p": p, "img": []}, binaryResource));
    }
    final bodies = [
      for (final b in other.extraBodies)
        b.replaceAllMapped(_idAttr, (m) => '${m.group(1)}${idMap[m.group(2)]}"')
    ];
    bodies.forEach(note);
    for (final r in other.binaryResource.resources) {
      if (!used.contains('$pre${r.id}')) continue;
      binaryResource.add({
        "id": '$pre${r.id}',
        "contentType": r.contentType,
        "data": r.data,
        "sectionId": ''
      });
    }
    // pictures are owned by the section that shows them
    for (final sec in added) {
      for (final ref in sec.pictureRefs) {
        final res = binaryResource.find(ref);
        if (res.id.isNotEmpty && res.sectionId.isEmpty) res.sectionId = sec.sectionId;
      }
    }
    section.addAll(added);
    extraBodies = [...extraBodies, ...bodies.map(rewrite)];
    return added.length;
  }

  removeSelected(Map<String, Section> list) {
    final newList = section
        .where((element) => list.containsKey(element.sectionId) == false)
        .toList();
    section = newList;
  }
}
