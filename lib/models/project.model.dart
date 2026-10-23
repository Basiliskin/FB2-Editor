import 'dart:io';

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
  }

  toXml() {
    List<String> xml = [];
    xml.add('<author>');
    xml.add('<first-name>${escapeXml(firstName)}</first-name>');
    xml.add('<middle-name>${escapeXml(middleName)}</middle-name>');
    xml.add('<last-name>${escapeXml(lastName)}</last-name>');
    xml.add('<home-page>${escapeXml(homePage)}</home-page>');
    xml.add('<id>${escapeXml(id)}</id>');
    xml.add('<nickname>${escapeXml(nickname)}</nickname>');

    xml.add('</author>');
    return xml.join();
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
  List<String> annotation = [];
  String date = '';
  String lang = '';
  String programUsed = '';
  String srcUrl = '';
  String documentDate = '';
  /// Raw XML of the bodies after the first (footnotes etc.), written back unchanged.
  List<String> extraBodies = [];
  String id = '';
  String version = '';
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
    bookTitle = safeGet(json, 'bodyTitle', '');
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
    coverpage = CoverImage(safeGet(title, 'coverpage.image', {}));
    final coverPageFile = binaryResource.find(coverpage.href);
    if (coverPageFile.sectionId.isEmpty) {
      coverPageFile.sectionId = "cover";
    }
    if (bookTitle.isEmpty) {
      bookTitle = safeGet(title, 'book-title.\$', '');
    }
    author.load(document);
    programUsed = safeGet(document, 'program-used.\$', '');
    srcUrl = safeGet(document, 'src-url.\$', '');
    documentDate = safeGet(document, 'date.\$', '');
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

  /// "Author - Title.fb2", falling back to the project id so the name is never empty.
  String get exportFileName {
    final who = safeFileName('${author.lastName} ${author.firstName}');
    final what = safeFileName(bookTitle);
    final name = [who, what].where((s) => s.isNotEmpty).join(' - ');
    return '${name.isEmpty ? projectId : name}$BOOK_EXT';
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
      'home-page': _authorHomePage
    }, '');
  }

  addXml(tag, value) {
    return "<$tag>${escapeXml(value)}</$tag>";
  }

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
    if (date.isNotEmpty) xml.add(addXml('date', date));
    final coverRes = binaryResource.findBySectionId('cover');
    if (coverRes.id.isNotEmpty) {
      xml.add(
          '<coverpage><image l:href="#${escapeXml(coverRes.id)}" alt="coverpage"/></coverpage>');
    }
    if (lang.isNotEmpty) xml.add(addXml('lang', lang));
    sequence.forEach((element) {
      xml.add('<sequence name="${escapeXml(element)}"/>');
    });
    xml.add('</title-info>');
    xml.add('<document-info>');
    xml.add(author.toXml());
    xml.add(addXml('program-used', programUsed));
    xml.add(addXml('date', documentDate.isNotEmpty ? documentDate : date));
    xml.add(addXml('src-url', srcUrl));
    xml.add(addXml('id', id));
    xml.add(addXml('version', version));
    xml.add('</document-info>');
    xml.add('</description>');
    xml.add('<body>');
    xml.add('<title><p>${escapeXml(bookTitle)}</p></title>');
    section.forEach((element) {
      xml.add(element.toXml());
    });
    xml.add('</body>');
    xml.addAll(extraBodies);
    xml.add(binaryResource.toXml());
    xml.add('</FictionBook>');
    return xml.join('\n');
  }

  removeSelected(Map<String, Section> list) {
    final newList = section
        .where((element) => list.containsKey(element.sectionId) == false)
        .toList();
    section = newList;
  }
}
