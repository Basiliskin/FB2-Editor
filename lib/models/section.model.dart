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

  /// Replaces the content with pasted plain text: one paragraph per line, with
  /// every character kept as text (nothing in it is treated as markup).
  load(String text) {
    p = [for (final line in splitStringByEof(text)) '<p>${escapeText(line)}</p>'];
  }

  /// Replaces paragraphs [start, end) with the lines of [text]; returns the new end.
  int loadRange(int start, int end, String text) {
    final List<String> lines = [
      for (final String l in splitStringByEof(text)) _inlineToP(l)
    ];
    p.replaceRange(start, end, lines);
    return start + lines.length;
  }

  /// What the editor shows for one stored paragraph: a `<p>` as a single line of
  /// inline markup (so bold, italics and footnote links stay in place), any other
  /// block (poem, table, ...) as its whole XML.
  String editableText(String pXml) {
    try {
      final root = XmlDocument.parse(pXml).rootElement;
      if (root.name.local != 'p') return root.outerXml;
      return root.children
          .map((n) => n.outerXml)
          .join()
          .replaceAll(RegExp(r'[\r\n]+'), ' ');
    } catch (e) {
      return pXml;
    }
  }

  /// Writes edited [text] back over paragraph [index] and returns how many
  /// paragraphs it now occupies (0 when the text was cleared). A new line starts
  /// a new paragraph. A block element that was edited into broken XML is left as
  /// it was.
  int replaceParagraph(int index, String text) {
    if (!_isParagraph(p[index])) {
      final fragment = text.trim();
      try {
        XmlDocument.parse(fragment);
        p[index] = fragment;
      } catch (e) {
        // keep the original block
      }
      return 1;
    }
    return loadRange(index, index + 1, text) - index;
  }

  bool _isParagraph(String xml) {
    try {
      return XmlDocument.parse(xml).rootElement.name.local == 'p';
    } catch (e) {
      return true;
    }
  }

  /// One edited line as a paragraph. Typed tags stay tags, a stray "&" or "<" is
  /// escaped, and a line that still cannot be parsed is kept as plain text, so a
  /// slip never makes the saved book unreadable.
  String _inlineToP(String line) {
    final fixed = sanitizeXml(line);
    try {
      XmlDocument.parse('<p>$fixed</p>');
      return '<p>$fixed</p>';
    } catch (e) {
      return '<p>${escapeText(line)}</p>';
    }
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
