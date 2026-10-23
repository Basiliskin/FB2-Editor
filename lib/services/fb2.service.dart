import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:quill_fb2/utils/common.dart';
import 'package:xml2json/xml2json.dart';
import 'package:xml/xml.dart';

class XmlResult {
  final XmlDocument doc;
  final bool valid;
  final String xml;
  final int level;
  XmlResult(this.valid, this.xml, this.level, this.doc);
}

class Fb2Service {
  getAllChildren(xmlNode) {
    return xmlNode.length > 0
        ? (xmlNode.first as XmlNode)
            .children
            .where((XmlNode item) => item.innerText != "")
            .map((XmlNode elm) {
            return {"name": (elm as XmlElement).name, "text": elm.outerXml};
          }).toList()
        : [];
  }

  xmlToJson(xmlString, tag) {
    final myTransformer = Xml2Json();
    myTransformer.parse("<$tag>$xmlString</$tag>");
    return jsonDecode(myTransformer.toBadgerfish());
  }

  safeGetXmlText(XmlElement node, tag) {
    final list = node.findElements(tag);
    if (list.length > 0) {
      return list.first.innerText;
    }
    return '';
  }

  /// Parses off the UI isolate (plain `compute` on web); returns null on failure.
  convertXmlToJson(String xml) => compute(_convertXml, xml);

  tryParse(xml, level) async => _tryParseSync(xml, level);
}

/// Max number of stray characters dropped while repairing malformed XML.
const _maxRepairs = 100;

// A "<" that cannot start a tag, and a "&" that does not start an entity.
final _strayLt = RegExp(r'<(?![A-Za-z_:/!?])');
final _strayAmp = RegExp(r'&(?!(?:amp|lt|gt|quot|apos|#[0-9]+|#[xX][0-9A-Fa-f]+);)');

/// Escapes stray "<" and "&" in one pass.
String sanitizeXml(String xml) =>
    xml.replaceAll(_strayAmp, '&amp;').replaceAll(_strayLt, '&lt;');

XmlResult _tryParseSync(String xml, int level) {
  while (true) {
    try {
      return XmlResult(true, xml, level, XmlDocument.parse(xml));
    } on XmlException catch (e) {
      final int? position = (e as dynamic).position;
      if (level <= 0 ||
          position == null ||
          position < 0 ||
          position >= xml.length) {
        return XmlResult(false, xml, level, XmlDocument.parse('<xml></xml>'));
      }
      // drop the offending character and retry
      // xml 6 reports the position just after a stray "<"
      final drop =
          position > 0 && xml[position - 1] == '<' ? position - 1 : position;
      xml = xml.substring(0, drop) + xml.substring(drop + 1);
      level--;
    }
  }
}

Map<String, dynamic>? _convertXml(String xml) {
  try {
    final service = Fb2Service();
    // Escape everything fixable in one pass; the per-character repair below
    // re-parses the whole book for every stray character.
    var parsed = _tryParseSync(xml, 0);
    if (!parsed.valid) parsed = _tryParseSync(sanitizeXml(xml), _maxRepairs);
    final document = parsed.doc;
    final description = document.rootElement.findElements('description').first;
    final descriptionJson = service.xmlToJson(description.innerXml, 'description');
    final body = document.rootElement.findElements('body');
    final binary = document.rootElement.findElements('binary');
    final resources = binary.map((elm) {
      return {
        "id": elm.getAttribute('id'),
        "contentType": elm.getAttribute('content-type'),
        "data": elm.innerText,
        "sectionId": elm.getAttribute('section-id')
      };
    }).toList();
    final bodyTitle = service.safeGetXmlText(body.first, 'title');
    final sections = parseSectionXml(document);
    return {
      "bodyTitle": bodyTitle,
      "description": descriptionJson,
      "resources": resources,
      "sections": sections,
      // bodies after the main one (e.g. footnotes) are carried through untouched
      "extraBodies": body.skip(1).map((b) => b.outerXml).toList()
    };
  } catch (e) {
    print(e);
  }
  return null;
}
