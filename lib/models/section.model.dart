import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:xml/xml.dart';

class Section {
  String title = '';
  List<String> p = [];
  String sectionId = '';
  List<String> images = [];
  Section(Map json, BinaryResources binRes) {
    try {
      sectionId = safeGet(json, 'sectionId', '');
      if (sectionId.isEmpty) sectionId = getRandomString(7);
      title = safeGet(json, 'title', '');
      final _p = safeGet(json, 'p', []);
      final _img = safeGet(json, 'img', []);
      _p.forEach((e) {
        p.add(e);
      });
      _img.forEach((e) {
        final res = binRes.find(e);
        if (res.id.isNotEmpty && res.sectionId.isEmpty) {
          res.sectionId = sectionId;
        }
        images.add(e);
      });
    } catch (e) {
      print(e);
    }
  }
  toXml() {
    List<String> xml = [];
    xml.add('<section section-id="${escapeXml(sectionId)}">');
    if (title.isNotEmpty) xml.add('<title><p>${escapeXml(title)}</p></title>');
    for (final image in images) {
      xml.add('<image xlink:href="${escapeXml(image)}"/>');
    }

    p.forEach((element) {
      xml.add(element);
    });
    xml.add('</section>');
    return xml.join('\n');
  }

  setImage(imgId) {
    images = imgId.isEmpty ? [] : [imgId];
  }

  addImage(imgId) {
    images = [imgId];
  }

  containImage(imgId) {
    return images.firstWhere((f) => f == imgId, orElse: () {
      return "";
    }).isNotEmpty;
  }

  removeImage(imgId) {
    images = images.where((f) => f == imgId).toList();
  }

  load(String text) {
    final _p = splitStringByEof(text);
    p = [];
    _p.forEach((line) {
      p.add(addXml('p', line));
    });
  }

  /// Replaces paragraphs [start, end) with the lines of [text]; returns the new end.
  int loadRange(int start, int end, String text) {
    final List<String> lines = [
      for (final String l in splitStringByEof(text)) addXml('p', l)
    ];
    p.replaceRange(start, end, lines);
    return start + lines.length;
  }

  addXml(tag, value) {
    return "<$tag>$value</$tag>";
  }

  getIfEmpty(String value, String xml) {
    return value.isEmpty ? xml : value;
  }

  parseP(pXml) {
    final document = XmlDocument.parse(pXml);
    // final tag = document.rootElement.name.qualified;
    final items = parseXml(document.rootElement);
    final delta = [];
    items.forEach((item) {
      var toInsert = "${getIfEmpty(item.xml, item.text)}\n";
      delta.add({"insert": toInsert});
      // var toInsert = "${getIfEmpty(item.text, item.xml)}\n";
      // if (item.tag == "strong") {
      //   delta.add({
      //     "insert": toInsert,
      //     "attributes": {"bold": true}
      //   });
      // } else if (item.tag == "emphasis") {
      //   delta.add({
      //     "insert": toInsert,
      //     "attributes": {"italic": true}
      //   });
      // } else {
      //   delta.add({"insert": toInsert});
      // }
    });
    // r'[{"insert":"\n","attributes":{"blockquote":true}},{"insert":"Hello "},{"insert":"Markdown","attributes":{"bold":true}},{"insert":"\n"}]';
    return delta;
  }

  toDelta() {
    final delta = [];
    if (p.length > 0)
      try {
        p.forEach((element) {
          delta.addAll(parseP(element));
        });
      } catch (e) {
        print(e);
      }
    if (delta.length == 0) {
      delta.add({"insert": "\n"});
    }
    return delta;
  }
}
