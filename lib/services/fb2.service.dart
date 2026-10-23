import 'dart:convert';

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

  convertXmlToJson(xml) async {
    try {
      final parsed = await tryParse(xml, 1000);
      final document = XmlDocument.parse(parsed.xml);
      final description =
          document.rootElement.findElements('description').first;
      final descriptionJson = xmlToJson(description.innerXml, 'description');
      final body = document.rootElement.findElements('body');
      final binary = document.rootElement.findElements('binary');
      final resources = binary.map((elm) {
        var contentType = elm.getAttribute('content-type');
        var sectionId = elm.getAttribute('section-id');
        var id = elm.getAttribute('id');
        var data = elm.innerText;
        return {
          "id": id,
          "contentType": contentType,
          "data": data,
          "sectionId": sectionId
        };
      }).toList();
      final bodyTitle = safeGetXmlText(body.first, 'title');
      final sections = parseSectionXml(document);
      return {
        "bodyTitle": bodyTitle,
        "description": descriptionJson,
        "resources": resources,
        "sections": sections
      };
      // final myTransformer = Xml2Json();
      // myTransformer.parse(parsed.xml);
      // return myTransformer.toBadgerfish();
    } catch (e) {
      print(e);
    }
    // json = myTransformer.toGData();
    //json = myTransformer.toParker();
  }

  tryParse(xml, level) async {
    try {
      final doc = XmlDocument.parse(xml);
      return XmlResult(true, xml, level, doc);
    } on XmlException catch (e) {
      await Future.delayed(Duration(milliseconds: 50));
      final invalid =
          XmlResult(false, xml, level, XmlDocument.parse('<xml></xml>'));
      final int? position = (e as dynamic).position;
      if (level <= 0 || position == null || position < 0 || position >= xml.length) {
        return invalid;
      }
      // drop the offending character and retry
      // xml 6 reports the position just after a stray "<"
      final drop = position > 0 && xml[position - 1] == '<' ? position - 1 : position;
      xml = xml.substring(0, drop) + xml.substring(drop + 1);
      return tryParse(xml, level - 1);
    } catch (e) {
      print(e);
    }
  }
}
