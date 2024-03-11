import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;
import 'cp1251.dart';

const _chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
Random _rnd = Random();

stringToInt(value) {
  return value is String
      ? value == "best"
          ? 100
          : int.parse(value)
      : value;
}

stringToBool(value) {
  return value is String ? value.toLowerCase() == 'true' : value;
}

String getRandomString(int length) => String.fromCharCodes(Iterable.generate(
    length, (_) => _chars.codeUnitAt(_rnd.nextInt(_chars.length))));

safeGet(Map data, String key, dynamic defaultValue) {
  final keys = key.split('.');
  return keys.fold(
          data,
          (previousValue, element) => previousValue != null &&
                  (previousValue as Map).containsKey(element)
              ? previousValue[element]
              : null) ??
      defaultValue;
}

final JsonEncoder encoder = new JsonEncoder.withIndent('  ');

prettyJson(Map<dynamic, dynamic> obj) {
  try {
    String res = encoder.convert(obj);
    return res;
  } catch (e) {
    return "$e";
  }
}

cloneMap(Map data) {
  final m = jsonDecode(encoder.convert(data));
  return m;
}

prepareList(List list) {
  List res = [];
  list.forEach((value) {
    if (value is DateTime)
      res.add(value.toString());
    else if (value is Map)
      res.add(prepareJSon(value));
    else if (value is List)
      res.add(prepareList(value));
    else
      res.add(value);
  });
  return res;
}

prepareJSon(Map map) {
  map.forEach((key, value) {
    if (value is DateTime)
      map[key] = value.toString();
    else if (value is Map)
      map[key] = prepareJSon(value);
    else if (value is List) map[key] = prepareList(value);
  });
  return map;
}

toJSonString(Map map) {
  map = prepareJSon(map);
  return prettyJson(map);
}

resizeImageBytes(bytes, width, quality) async {
  if (quality < 100) {
    try {
      final image = decodeImage(bytes)!;
      final thumbnail = copyResize(image, width: stringToInt(width));
      List<int> jpg = encodeJpg(thumbnail, quality: stringToInt(quality));
      return base64Encode(jpg);
    } catch (e) {
      print(e);
    }
  }
  return bytes;
}

resizeImage(base64, width) async {
  try {
    Uint8List bytes = decode64Image(base64);

    final image = decodeImage(bytes)!;
    final thumbnail = copyResize(image, width: width);
    List<int> jpg = encodeJpg(thumbnail, quality: 75);
    return base64Encode(jpg);
  } catch (e) {
    print(e);
  }
}

decode64Image(String img) {
  try {
    // final bs = RegExp(r'![^A-Za-z0-9+\/=]');
    img = trimSpecialChar(img);
    img = base64.normalize(img);
    return base64Decode(img);
  } catch (e) {
    print(e);
  }
}

String? toBeginningOfSentenceCase(String? input) {
  if (input == null || input.isEmpty) return input;
  return '${input[0].toUpperCase()}${input.substring(1)}';
}

Future<Uint8List> readFileByte(String filePath) async {
  Uri myUri = Uri.parse(filePath);
  File file = new File.fromUri(myUri);
  final bytes = await file.readAsBytes();
  return bytes;
}

trimSpecialChar(String? text, [char = '']) {
  return text != null
      ? text
          .replaceAll("\\\\n", char)
          .replaceAll("\\\\r", char)
          .replaceAll("\\\\t", char)
          .replaceAll('\\n', char)
          .replaceAll('\\t', char)
          .replaceAll('\\r', char)
          .replaceAll('\n', char)
          .replaceAll('\t', char)
          .replaceAll('\r', char)
      : "";
}

Future<File> moveFile(File sourceFile, String newPath) async {
  try {
    /// prefer using rename as it is probably faster
    /// if same directory path
    return await sourceFile.rename(newPath);
  } catch (e) {
    /// if rename fails, copy the source file
    final newFile = await sourceFile.copy(newPath);
    return newFile;
  }
}

moveFileTo(fileSrc, newPath) async {
  File sourceFile = File(fileSrc);
  var basNameWithExtension = path.basename(sourceFile.path);
  var file = await moveFile(sourceFile, newPath + "/" + basNameWithExtension);
  return file;
}

getXmlText(xml) {
  final document = XmlDocument.parse(xml);
  return document.rootElement.innerText;
}

class XmlItem {
  String tag;
  String text;
  String xml;
  XmlItem(this.tag, this.text, this.xml);
}

readyAscii(bytes) {
  try {
    return latin1.decode(bytes);
  } catch (ee) {
    return ascii.decode(bytes);
  }
}

readAsString(file) async {
  final bytes = await file.readAsBytes();
  try {
    String text = utf8.decode(bytes);
    return text;
  } catch (e) {
    String asci = decodeCp1251(bytes);
    return asci;
  }
  // String text = await file.readAsString(encoding: utf8);
  // return text;
}

_cleanElement(p) {
  if (p is XmlText) return trimSpecialChar(p.outerXml);
  final xml =
      p.children.where((node) => node is XmlElement).toList().map((elm) {
    return "<${elm.name.qualified}>${trimSpecialChar(elm.innerText)}</${elm.name.qualified}>";
  });
  final temp = xml.length > 0
      ? xml.join()
      : "<${p.name.qualified}>${trimSpecialChar(p.innerText)}</${p.name.qualified}>";
  return temp;
}

_removeImage(XmlElement p, items) {
  // print(p);
  final xml = p.children
      .where((node) =>
          node is XmlText || (node as XmlElement).name.qualified != 'image')
      .toList()
      .map((elm) {
    return elm is XmlText && elm.innerText.isNotEmpty
        ? elm.innerText
        : _cleanElement(elm);
  });
  // print(xml);
  final outerXml = "<p>${xml.join()}</p>";
  items.add(XmlItem('p', p.innerText, outerXml));
  final image = p.children
      .where((node) => node is XmlElement && node.name.qualified == 'image')
      .toList();
  if (image.length > 0) {
    final child = image[0];
    items.add(
        XmlItem('image', child.getAttribute('xlink:href')!, child.outerXml));
  }
}

parseXml(XmlElement root) {
  final items = [];

  root.children.forEach((child) {
    if (child is XmlText)
      items.add(XmlItem("text", child.innerText, child.outerXml));
    else if (child is XmlElement) {
      if (child.name.qualified == 'p') {
        _removeImage(child, items);
      } else if (child.name.qualified == 'image') {
        //elm.getAttribute('xlink:href')
        items.add(XmlItem(
            child.name.qualified,
            child.getAttribute('xlink:href') ?? child.getAttribute('l:href')!,
            child.outerXml));
      } else {
        items.add(
            XmlItem(child.name.qualified, child.innerText, child.outerXml));
      }
    }
  });
  return items;
}

parseSectionXml(XmlDocument document) {
  final body = document.rootElement.findElements('body');
  final bodySections = body.first.findElements('section');
  final sections = bodySections.map((XmlElement node) {
    try {
      final p = parseXml(node);
      final sectionId = node.getAttribute('section-id') ?? '';
      final _p = p.where((element) => element.tag == 'p').toList();
      final _i = p.where((element) => element.tag == 'image').toList();
      final _title =
          p.firstWhere((element) => element.tag == 'title', orElse: () {
        return _p.length > 0 ? _p[0] : null;
      });

      List<String> img = [];
      if (_i != null)
        _i.forEach((elm) {
          img.add(elm.text);
        });
      List<String> pp = [];
      if (p != null)
        p.forEach((elm) {
          if (elm.tag != 'title' && elm.tag != 'sectionId') if (elm.tag !=
              'text')
            pp.add(elm.xml);
          else {
            String trimed = trimSpecialChar(elm.text, '');
            if (trimed.isNotEmpty) pp.add(elm.xml);
          }
        });
      var title = _title != null ? _title.text : '';
      return {"title": title, "p": pp, "img": img, "sectionId": sectionId};
    } catch (e) {
      print(e);
    }
  }).toList();
  return sections;
}
