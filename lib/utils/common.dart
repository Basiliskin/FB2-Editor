import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;
import 'cp1251.dart';

/// Runs [body] and logs its duration in debug builds (`[load] label: N ms`).
Future<T> timed<T>(String label, Future<T> Function() body) async {
  if (!kDebugMode) return body(); // coverage:ignore-line
  final sw = Stopwatch()..start();
  try {
    return await body();
  } finally {
    debugPrint('[load] $label: ${sw.elapsedMilliseconds} ms');
  }
}

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

safeGet(dynamic data, String key, dynamic defaultValue) {
  final keys = key.split('.');
  return keys.fold(
          data,
          (previousValue, element) =>
              previousValue is Map && previousValue.containsKey(element)
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
      final image = decodeImage(Uint8List.fromList(List<int>.from(bytes)))!;
      final target = stringToInt(width) as int;
      // never enlarge: a small picture stays as sharp as it was
      final thumbnail =
          image.width > target ? copyResize(image, width: target) : image;
      List<int> jpg = encodeJpg(thumbnail, quality: stringToInt(quality));
      return base64Encode(jpg);
    } catch (e) {
      print(e);
    }
  }
  return bytes;
}

/// Content type and file extension of an image, read from its first bytes.
/// Falls back to JPEG, which is what most pickers hand over.
({String contentType, String ext}) sniffImageType(List<int> b) {
  bool starts(List<int> sig, [int at = 0]) {
    if (b.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts([0x89, 0x50, 0x4E, 0x47])) {
    return (contentType: 'image/png', ext: 'png');
  }
  if (starts([0x47, 0x49, 0x46, 0x38])) {
    return (contentType: 'image/gif', ext: 'gif');
  }
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
    return (contentType: 'image/webp', ext: 'webp');
  }
  return (contentType: 'image/jpeg', ext: 'jpg');
}

/// Same, for base64 text (only the head is decoded).
({String contentType, String ext}) sniffBase64ImageType(String data) {
  try {
    final head = data.trim().replaceAll(RegExp(r'\s'), '');
    final n = head.length < 24 ? head.length : 24;
    return sniffImageType(base64Decode(base64.normalize(head.substring(0, n - n % 4))));
  } catch (_) {
    return (contentType: 'image/jpeg', ext: 'jpg');
  }
}

/// Thumbnail as base64 jpg, or null. The native codec decodes and downscales
/// (fast, off the UI thread); only the tiny result is re-encoded in Dart. Falls
/// back to the pure-Dart path in an isolate if the platform can't decode it.
Future resizeImage(base64, width) async {
  try {
    // base64 of a large cover is megabytes: strip/decode it off the UI isolate
    final bytes = await compute(_decode64Bytes, base64 as String);
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    final frame = await codec.getNextFrame();
    final small = frame.image;
    final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    final thumb = Image.fromBytes(
        width: small.width,
        height: small.height,
        bytes: data!.buffer,
        numChannels: 4);
    small.dispose();
    codec.dispose();
    return base64Encode(encodeJpg(thumb, quality: 75));
  } catch (e) {
    print(e);
  }
  return compute(_resizeImageSync, [base64, width]);
}

Uint8List? _decode64Bytes(String img) => decode64Image(img) as Uint8List?;

String? _resizeImageSync(List args) {
  try {
    // coverage:ignore-start
    Uint8List bytes = decode64Image(args[0]);

    final image = decodeImage(bytes)!;
    final thumbnail = copyResize(image, width: args[1]);
    List<int> jpg = encodeJpg(thumbnail, quality: 75);
    return base64Encode(jpg);
    // coverage:ignore-end
  } catch (e) {
    print(e);
  }
  return null;
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

final _specialChars = RegExp(r'\\{1,2}[nrt]|[\n\r\t]');

trimSpecialChar(String? text, [char = '']) {
  return text != null ? text.replaceAll(_specialChars, char) : "";
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

/// First `.fb2` file under [dir] (recursive, case-insensitive), or null.
File? findFb2File(Directory dir) {
  final matches = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.fb2'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return matches.isEmpty ? null : matches.first;
}

final _declaredEncoding = RegExp(r'encoding\s*=\s*["\x27]([^"\x27]+)', caseSensitive: false);

/// Decodes FB2 bytes using the encoding declared in the XML header, so
/// windows-1251 files skip a failed full-file UTF-8 pass.
String decodeFb2Bytes(List<int> bytes) {
  final head = latin1.decode(bytes.take(200).toList(), allowInvalid: true);
  final enc = _declaredEncoding.firstMatch(head)?.group(1)?.toLowerCase();
  if (enc == 'windows-1251' || enc == 'cp1251') return decodeCp1251(bytes);
  try {
    return utf8.decode(bytes);
  } catch (e) {
    return decodeCp1251(bytes);
  }
}

readAsString(file) async => decodeFb2Bytes(await file.readAsBytes());

final _lineBreakRun = RegExp(r'[ \t]*[\r\n]+[ \t]*');

/// Keeps inline markup (links, nested formatting) and the text itself intact.
/// A line break inside a paragraph, with the indentation around it, is one space,
/// as in any XML reader. Backslashes are ordinary characters.
_cleanElement(XmlNode node) => node.outerXml.replaceAll(_lineBreakRun, ' ');

/// A file name that every file system accepts: no separators or reserved
/// characters, collapsed spaces, at most [maxLength] characters.
String safeFileName(String name, {int maxLength = 100}) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[.\s]+'), '');
  return cleaned.length > maxLength
      ? cleaned.substring(0, maxLength).trim()
      : cleaned;
}

// A "<" that cannot start a tag, and a "&" that does not start an entity.
final _strayLt = RegExp(r'<(?![A-Za-z_:/!?])');
final _strayAmp = RegExp(r'&(?!(?:amp|lt|gt|quot|apos|#[0-9]+|#[xX][0-9A-Fa-f]+);)');

/// Escapes stray "<" and "&" in one pass.
String sanitizeXml(String xml) =>
    xml.replaceAll(_strayAmp, '&amp;').replaceAll(_strayLt, '&lt;');

/// Escapes text for use as element content (quotes are left alone).
String escapeText(String? text) => (text ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Escapes text for use as element content or inside a double-quoted attribute.
String escapeXml(String? text) => (text ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

_removeImage(XmlElement p, items) {
  // print(p);
  final xml = p.children
      .where((node) =>
          node is XmlText || (node as XmlElement).name.qualified != 'image')
      .toList()
      .map(_cleanElement);
  // print(xml);
  final outerXml = "<p>${xml.join()}</p>";
  items.add(XmlItem('p', p.innerText, outerXml));
  final image = p.children
      .where((node) => node is XmlElement && node.name.qualified == 'image')
      .toList();
  if (image.length > 0) {
    final child = image[0];
    items.add(XmlItem(
        'image',
        child.getAttribute('xlink:href') ?? child.getAttribute('l:href') ?? '',
        child.outerXml));
  }
}

parseXml(XmlElement root) {
  final items = [];

  root.children.forEach((child) {
    if (child is XmlText)
      items.add(XmlItem("text", child.text, child.outerXml));
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

/// A picture as a stored section block; [href] is `#id`.
String imageBlock(String href) => '<image xlink:href="${escapeXml(href)}"/>';

/// The `#id` a stored block points to, or null when the block is not a picture.
String? imageHref(String blockXml) {
  if (!blockXml.startsWith('<image')) return null;
  try {
    final e = XmlDocument.parse(blockXml).rootElement;
    if (e.name.local != 'image') return null;
    for (final a in e.attributes) {
      if (a.name.local == 'href') return a.value;
    }
  } catch (_) {}
  return null;
}

parseSectionXml(XmlDocument document) {
  final body = document.rootElement.findElements('body');
  final bodySections = body.first.findElements('section');
  final sections = bodySections.map((XmlElement node) {
    try {
      final p = parseXml(node);
      final sectionId = node.getAttribute('section-id') ?? '';
      final _p = p.where((element) => element.tag == 'p').toList();
      final _title =
          p.firstWhere((element) => element.tag == 'title', orElse: () {
        return _p.length > 0 ? _p[0] : null;
      });

      List<String> pp = [];
      if (p != null)
        p.forEach((elm) {
          if (elm.tag == 'title' || elm.tag == 'sectionId') return;
          if (elm.tag == 'image') {
            // pictures stay where the author put them, between the paragraphs
            pp.add(imageBlock(elm.text));
          } else if (elm.tag == 'text') {
            // bare text is kept as a paragraph, whitespace-only is dropped
            if (trimSpecialChar(elm.text, '').trim().isNotEmpty)
              pp.add('<p>${elm.xml}</p>');
          } else {
            pp.add(elm.xml);
          }
        });
      var title = _title != null ? _title.text : '';
      return {"title": title, "p": pp, "img": [], "sectionId": sectionId};
    } catch (e) {
      print(e);
    }
  }).toList();
  return sections;
}

/// Template for a book created in the app: valid FB2 with one titled, empty chapter.
String newBookXml(String title, String chapter) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" '
    'xmlns:l="http://www.w3.org/1999/xlink" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
    '<description><title-info><genre>prose</genre>'
    '<author><first-name></first-name><last-name></last-name></author>'
    '<book-title>${escapeXml(title)}</book-title><lang>en</lang></title-info>'
    '<document-info><author><nickname>FB2 Editor</nickname></author>'
    '<date>${DateTime.now().toIso8601String().substring(0, 10)}</date>'
    '<id>${getRandomString(16)}</id><version>1.0</version></document-info></description>\n'
    '<body><title><p>${escapeXml(title)}</p></title>'
    '<section><title><p>${escapeXml(chapter)}</p></title></section></body>\n'
    '</FictionBook>';

final _chapterHeading = RegExp(
    r'^(chapter|part|book|prologue|epilogue|глава|часть|книга|пролог|эпилог)(?![\p{L}\p{N}_])',
    caseSensitive: false, unicode: true);

/// Plain text as a book: one paragraph per non-empty line; a short line that
/// starts like a chapter heading ("Chapter 3", "Глава 2", "Prologue") opens a new
/// section. Without any heading the whole text is one section named [title].
String txtToFb2Xml(String text, String title) {
  final sections = <(String, StringBuffer)>[];
  for (final raw in text.replaceFirst('\uFEFF', '').split(RegExp(r'\r\n|\r|\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.length <= 80 && _chapterHeading.hasMatch(line)) {
      sections.add((line, StringBuffer()));
      continue;
    }
    if (sections.isEmpty) sections.add((title, StringBuffer()));
    sections.last.$2.write('<p>${escapeXml(line)}</p>');
  }
  if (sections.isEmpty) sections.add((title, StringBuffer()));
  final body = sections
      .map((s) => '<section><title><p>${escapeXml(s.$1)}</p></title>${s.$2}</section>')
      .join();
  return newBookXml(title, '')
      .replaceFirst(RegExp(r'<section>.*</section>', dotAll: true), body);
}
