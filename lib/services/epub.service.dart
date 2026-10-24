import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/utils/common.dart';

/// Thrown when the bytes are not a readable EPUB.
class EpubException implements Exception {
  final String message;
  const EpubException(this.message);
  @override
  String toString() => 'EpubException($message)';
}

// ---------------------------------------------------------------- import

/// An EPUB as FB2 XML, ready for the same pipeline as a picked .fb2 file.
/// Chapters follow the reading order; a first- or second-level heading starts a
/// section. Formatting is reduced to what FB2 has (emphasis, strong, quotes,
/// subtitles, pictures). Throws [EpubException] when it is not an EPUB.
String epubToFb2Xml(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw const EpubException('not a zip archive');
  }
  final files = {for (final f in zip.files) if (f.isFile) _unescapePath(f.name): f};

  XmlDocument readXml(String path) {
    final file = files[path];
    if (file == null) throw EpubException('missing $path');
    final text = _decodeXhtml(file.content as List<int>);
    try {
      return XmlDocument.parse(text);
    } on XmlException {
      try {
        return XmlDocument.parse(sanitizeXml(text));
      } on XmlException catch (e) {
        throw EpubException('$path: ${e.message}');
      }
    }
  }

  final container = readXml('META-INF/container.xml');
  final opfPath = container
      .findAllElements('rootfile')
      .map((e) => e.getAttribute('full-path'))
      .whereType<String>()
      .firstOrNull;
  if (opfPath == null) throw const EpubException('no package document');
  final opf = readXml(_unescapePath(opfPath));
  final opfDir = _dirOf(opfPath);

  final manifest = <String, _Item>{};
  for (final e in opf.findAllElements('item')) {
    final id = e.getAttribute('id');
    final href = e.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = _Item(
        _resolve(opfDir, _unescapePath(href.split('#').first)),
        e.getAttribute('media-type') ?? '',
        e.getAttribute('properties') ?? '');
  }

  // dc:* elements are matched by prefix and local name
  String dc(String local) => opf.descendantElements
      .where((e) => e.name.local == local && e.name.prefix == 'dc')
      .map((e) => e.innerText.trim())
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  List<String> dcAll(String local) => opf.descendantElements
      .where((e) => e.name.local == local && e.name.prefix == 'dc')
      .map((e) => e.innerText.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  final title = dc('title');
  final language = dc('language');
  final date = dc('date');
  final description = dc('description');
  final subjects = dcAll('subject');
  final (first, last) = _splitAuthor(dc('creator'));

  // binaries: pictures are added the first time a chapter or the cover uses them
  final binaries = <String, String>{}; // path -> id
  final binaryXml = StringBuffer();
  String? addImage(String path) {
    final known = binaries[path];
    if (known != null) return known;
    final file = files[path];
    if (file == null) return null;
    final data = file.content as List<int>;
    final type = sniffImageType(data);
    final id = 'img${binaries.length + 1}.${type.ext}';
    binaries[path] = id;
    binaryXml.write('<binary id="$id" content-type="${type.contentType}">'
        '${base64Encode(data)}</binary>\n');
    return id;
  }

  // cover: EPUB 3 "cover-image" property, else EPUB 2 <meta name="cover">
  String? coverId;
  final coverItem = manifest.values
          .where((i) => i.properties.split(' ').contains('cover-image'))
          .firstOrNull ??
      () {
        final ref = opf
            .findAllElements('meta')
            .where((e) => e.getAttribute('name') == 'cover')
            .map((e) => e.getAttribute('content'))
            .firstOrNull;
        return ref == null ? null : manifest[ref];
      }();
  if (coverItem != null && coverItem.mediaType.startsWith('image/')) {
    coverId = addImage(coverItem.path);
  }

  final sections = <_Sec>[];
  for (final ref in opf.findAllElements('itemref')) {
    final item = manifest[ref.getAttribute('idref')];
    if (item == null || !item.mediaType.contains('html')) continue;
    if (item.properties.split(' ').contains('nav')) continue;
    if (!files.containsKey(item.path)) continue;
    XmlDocument doc;
    try {
      doc = readXml(item.path);
    } on EpubException {
      continue; // one broken chapter should not lose the book
    }
    final body = doc.findAllElements('body').firstOrNull;
    if (body == null) continue;
    final dir = _dirOf(item.path);
    final fileTitle = doc.findAllElements('title').map((e) => e.innerText.trim()).firstOrNull ?? '';
    final reader = _ChapterReader(
        resolveImage: (src) => addImage(_resolve(dir, _unescapePath(src.split('#').first))),
        fallbackTitle: fileTitle == title ? '' : fileTitle);
    sections.addAll(reader.read(body));
  }
  // A page that only shows the cover picture is the cover, not a chapter; left
  // in, the picture would belong to that section instead of being the cover.
  if (coverId != null) {
    final coverBlock = imageBlock('#$coverId');
    sections.removeWhere((s) => s.blocks.isNotEmpty && s.blocks.every((b) => b == coverBlock));
  }
  final used = sections.where((s) => s.title.isNotEmpty || s.blocks.isNotEmpty).toList();
  if (used.isEmpty) throw const EpubException('no readable chapters');

  final bookTitle = title.isNotEmpty ? title : 'Untitled';
  final annotation = description.isEmpty
      ? ''
      : '<annotation>${_plainParagraphs(description).map((l) => '<p>${escapeXml(l)}</p>').join()}</annotation>';
  final body = used.map((s) {
    final t = s.title.isEmpty ? '' : '<title><p>${escapeXml(s.title)}</p></title>';
    return '<section>$t${s.blocks.join()}</section>';
  }).join('\n');

  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" '
      'xmlns:l="http://www.w3.org/1999/xlink" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
      '<description><title-info><genre>prose</genre>'
      '<author><first-name>${escapeXml(first)}</first-name><last-name>${escapeXml(last)}</last-name></author>'
      '<book-title>${escapeXml(bookTitle)}</book-title>$annotation'
      '${subjects.isEmpty ? '' : '<keywords>${escapeXml(subjects.join(', '))}</keywords>'}'
      '${date.isEmpty ? '' : '<date>${escapeXml(date)}</date>'}'
      '${coverId == null ? '' : '<coverpage><image l:href="#$coverId"/></coverpage>'}'
      '<lang>${escapeXml(language.isEmpty ? 'en' : language)}</lang></title-info>'
      '<document-info><author><nickname>FB2 Editor</nickname></author>'
      '<date>${DateTime.now().toIso8601String().substring(0, 10)}</date>'
      '<id>${getRandomString(16)}</id><version>1.0</version></document-info></description>\n'
      '<body><title><p>${escapeXml(bookTitle)}</p></title>\n$body</body>\n'
      '$binaryXml</FictionBook>';
}

class _Item {
  final String path;
  final String mediaType;
  final String properties;
  _Item(this.path, this.mediaType, this.properties);
}

class _Sec {
  String title;
  final List<String> blocks = [];
  _Sec(this.title);
}

/// Splits "Last, First" or "First Middle Last" into (first, last).
(String, String) _splitAuthor(String name) {
  name = name.trim();
  if (name.isEmpty) return ('', '');
  if (name.contains(',')) {
    final i = name.indexOf(',');
    return (name.substring(i + 1).trim(), name.substring(0, i).trim());
  }
  final parts = name.split(RegExp(r'\s+'));
  if (parts.length == 1) return ('', parts.first);
  return (parts.sublist(0, parts.length - 1).join(' '), parts.last);
}

/// Text of a (possibly HTML) description as paragraphs.
List<String> _plainParagraphs(String html) {
  final text = html
      .replaceAll(RegExp(r'</(p|div|br)\s*>|<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&nbsp;', ' ');
  return text.split(RegExp(r'\n+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
}

String _decodeXhtml(List<int> bytes) {
  var text = utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
  // HTML entities that are not XML; EPUB 2 files still carry them
  const named = {
    'nbsp': ' ', 'mdash': '—', 'ndash': '–', 'hellip': '…', 'laquo': '«',
    'raquo': '»', 'ldquo': '“', 'rdquo': '”', 'lsquo': '‘', 'rsquo': '’',
    'copy': '©', 'times': '×',
  };
  return text.replaceAllMapped(RegExp(r'&([a-zA-Z]+);'), (m) {
    final key = m.group(1)!;
    if (const {'amp', 'lt', 'gt', 'quot', 'apos'}.contains(key)) return m.group(0)!;
    return named[key] ?? m.group(0)!;
  });
}

String _unescapePath(String p) {
  try {
    return Uri.decodeComponent(p);
  } catch (_) {
    return p;
  }
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// [href] relative to [dir], with "." and ".." segments folded.
String _resolve(String dir, String href) {
  final out = <String>[];
  for (final part in [...(dir.isEmpty ? <String>[] : dir.split('/')), ...href.split('/')]) {
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      out.add(part);
    }
  }
  return out.join('/');
}

/// Turns one XHTML body into FB2 sections.
class _ChapterReader {
  final String? Function(String src) resolveImage;
  final String fallbackTitle;
  _ChapterReader({required this.resolveImage, required this.fallbackTitle});

  final List<_Sec> _sections = [];
  _Sec? _current;
  List<String>? _target; // set while collecting a quote

  List<_Sec> read(XmlElement body) {
    _walk(body);
    final firstHasContent = _sections.isNotEmpty;
    // a chapter file without any heading is named after the file's <title>
    if (firstHasContent && _sections.first.title.isEmpty && fallbackTitle.isNotEmpty) {
      _sections.first.title = fallbackTitle;
    }
    return _sections;
  }

  void _add(String block) {
    if (_target != null) {
      _target!.add(block);
      return;
    }
    if (_current == null) _startSection('');
    _current!.blocks.add(block);
  }

  void _startSection(String title) {
    _current = _Sec(title);
    _sections.add(_current!);
  }

  void _walk(XmlNode node) {
    for (final child in node.children) {
      if (child is XmlText) {
        final t = _squash(child.value);
        if (t.trim().isNotEmpty) _add('<p>${escapeText(t.trim())}</p>');
      } else if (child is XmlElement) {
        _element(child);
      }
    }
  }

  void _element(XmlElement e) {
    switch (e.name.local.toLowerCase()) {
      case 'head' || 'script' || 'style' || 'nav':
        return;
      case 'h1' || 'h2':
        final t = _squash(e.innerText).trim();
        if (t.isNotEmpty) _startSection(t);
      case 'h3' || 'h4' || 'h5' || 'h6':
        final t = _inline(e).trim();
        if (t.isNotEmpty) _add('<subtitle>$t</subtitle>');
      case 'p' when (e.getAttribute('class') ?? '').contains('empty-line'):
        _add('<empty-line/>');
      case 'p' || 'li' || 'dt' || 'dd' || 'caption' || 'figcaption' || 'td' || 'th':
        _paragraph(e);
      case 'pre':
        for (final line in e.innerText.split(RegExp(r'\r\n|\r|\n'))) {
          if (line.trim().isNotEmpty) _add('<p>${escapeText(line.trimRight())}</p>');
        }
      case 'blockquote':
        final saved = _target;
        final inner = <String>[];
        _target = inner;
        _walk(e);
        _target = saved;
        final texts = inner.where((b) => !b.startsWith('<image')).toList();
        if (texts.isNotEmpty) _add('<cite>${texts.join()}</cite>');
        inner.where((b) => b.startsWith('<image')).forEach(_add);
      case 'img' || 'image':
        _image(e);
      case 'hr':
        _add('<empty-line/>');
      case 'tr':
        final cells = e.childElements.map((c) => _squash(c.innerText).trim()).where((t) => t.isNotEmpty);
        if (cells.isNotEmpty) _add('<p>${escapeText(cells.join(' | '))}</p>');
      default:
        _walk(e); // div, section, ul, ol, table, figure, body ...
    }
  }

  void _image(XmlElement e) {
    String? src = e.getAttribute('src');
    for (final a in e.attributes) {
      if (a.name.local == 'href') src ??= a.value;
    }
    if (src == null || src.startsWith('data:')) return;
    final id = resolveImage(src);
    if (id != null) _add(imageBlock('#$id'));
  }

  /// A paragraph; a picture inside it is lifted out as its own block.
  void _paragraph(XmlElement e) {
    final buf = StringBuffer();
    void flush() {
      final t = buf.toString().trim();
      if (t.isNotEmpty) _add('<p>$t</p>');
      buf.clear();
    }

    void visit(XmlNode n) {
      if (n is XmlText) {
        buf.write(escapeText(_squash(n.value)));
      } else if (n is XmlElement) {
        final name = n.name.local.toLowerCase();
        if (name == 'img' || name == 'image') {
          flush();
          _image(n);
        } else if (name == 'br') {
          flush(); // lines separated by <br/> are separate paragraphs
        } else if (_isBlock(name)) {
          flush();
          _element(n);
        } else {
          final tag = _inlineTag(name);
          if (tag == null) {
            n.children.forEach(visit);
          } else {
            final inner = StringBuffer();
            final outer = StringBuffer()..write(buf);
            buf.clear();
            n.children.forEach(visit);
            inner.write(buf);
            buf
              ..clear()
              ..write(outer);
            if (inner.toString().trim().isNotEmpty) buf.write('<$tag>$inner</$tag>');
          }
        }
      }
    }

    e.children.forEach(visit);
    flush();
  }

  /// Inline markup of a heading or other element, as FB2 inline XML.
  String _inline(XmlElement e) {
    final saved = _target;
    final sink = <String>[];
    _target = sink;
    _paragraph(e);
    _target = saved;
    return sink
        .where((b) => b.startsWith('<p>'))
        .map((b) => b.substring(3, b.length - 4))
        .join(' ');
  }

  static bool _isBlock(String n) =>
      const {'p', 'div', 'ul', 'ol', 'li', 'blockquote', 'table', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'hr'}
          .contains(n);

  static String? _inlineTag(String n) => switch (n) {
        'em' || 'i' || 'cite' || 'dfn' => 'emphasis',
        'strong' || 'b' => 'strong',
        's' || 'strike' || 'del' => 'strikethrough',
        'sub' => 'sub',
        'sup' => 'sup',
        'code' || 'tt' || 'kbd' => 'code',
        _ => null,
      };
}

// plain whitespace only: a no-break space ("— Hello") is deliberate
String _squash(String s) => s.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');

// ---------------------------------------------------------------- export

const _xhtmlNs = 'http://www.w3.org/1999/xhtml';
const _epubNs = 'http://www.idpf.org/2007/ops';

/// The book as an EPUB 3 file (with an EPUB 2 table of contents for old readers):
/// one XHTML file per section, pictures, cover and footnotes included.
Uint8List projectToEpub(ProjectModel book) {
  // pictures: id ("#abc.jpg") -> file name in the package
  final imageFiles = <String, ({String name, String type, List<int> bytes})>{};
  for (final r in book.binaryResource.resources) {
    if (r.id.isEmpty || r.data.isEmpty) continue;
    try {
      final bytes = decode64Image(r.data);
      final sniffed = sniffImageType(bytes);
      // the bytes win over the declared type: books often call a PNG image/jpeg.
      // Only when the bytes are not a known format (sniff falls back to jpeg)
      // is a declared type such as image/svg+xml kept.
      final known = sniffed.contentType != 'image/jpeg' || _isJpeg(bytes);
      final type = known || !r.contentType.startsWith('image/') || r.contentType == 'image/jpg'
          ? sniffed.contentType
          : r.contentType;
      final base = r.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final ext = sniffed.ext;
      final name = base.toLowerCase().endsWith('.$ext') ? base : '$base.$ext';
      imageFiles['#${r.id}'] = (name: 'images/$name', type: type, bytes: bytes);
    } catch (_) {
      // an undecodable picture is left out, not fatal
    }
  }

  // footnote targets: element id -> true; they live in notes.xhtml
  final noteIds = <String>{};
  final noteBodies = <XmlElement>[];
  for (final b in book.extraBodies) {
    try {
      final body = XmlDocument.parse(b).rootElement;
      noteBodies.add(body);
      for (final e in body.descendantElements) {
        final id = e.getAttribute('id');
        if (id != null) noteIds.add(id);
      }
    } catch (_) {}
  }

  final conv = _Fb2ToXhtml(imageFiles, noteIds);
  final coverRes = book.binaryResource.findBySectionId('cover');
  final coverImage = coverRes.id.isEmpty ? null : imageFiles['#${coverRes.id}'];

  final chapters = <({String file, String title, String xhtml})>[];
  var n = 0;
  for (final sec in book.section) {
    n++;
    final inner = StringBuffer();
    if (sec.title.isNotEmpty) inner.write('<h2>${escapeText(sec.title)}</h2>\n');
    for (final href in sec.images) {
      inner.write(conv.block(imageBlock(href)));
    }
    for (final block in sec.p) {
      inner.write(conv.block(block));
    }
    final title = sec.title.isEmpty ? 'Section $n' : sec.title;
    chapters.add((
      file: 'text/chapter$n.xhtml',
      title: title,
      xhtml: _page(title, book.lang, inner.toString(), css: '../style.css')
    ));
  }
  if (noteBodies.isNotEmpty) {
    final inner = StringBuffer('<h2>Notes</h2>\n');
    for (final body in noteBodies) {
      for (final sec in body.childElements.where((e) => e.name.local == 'section')) {
        inner.write(conv.note(sec));
      }
    }
    chapters.add((
      file: 'text/notes.xhtml',
      title: 'Notes',
      xhtml: _page('Notes', book.lang, inner.toString(), css: '../style.css')
    ));
  }
  if (chapters.isEmpty) {
    chapters.add((
      file: 'text/chapter1.xhtml',
      title: book.bookTitle,
      xhtml: _page(book.bookTitle, book.lang, '<h2>${escapeText(book.bookTitle)}</h2>', css: '../style.css')
    ));
  }

  final uid = book.id.isNotEmpty ? book.id : 'urn:uuid:${book.projectId}';
  final lang = book.lang.isEmpty ? 'en' : book.lang;
  final author = '${book.author.firstName} ${book.author.lastName}'.trim();
  final modified = '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

  final manifest = StringBuffer()
    ..write('<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n')
    ..write('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n')
    ..write('<item id="css" href="style.css" media-type="text/css"/>\n');
  final spine = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    manifest.write('<item id="c$i" href="${chapters[i].file}" media-type="application/xhtml+xml"/>\n');
    spine.write('<itemref idref="c$i"/>\n');
  }
  var k = 0;
  String? coverItemId;
  for (final img in imageFiles.values) {
    final isCover = identical(img, coverImage);
    if (isCover) coverItemId = 'i$k';
    manifest.write('<item id="i$k" href="${img.name}" media-type="${img.type}"'
        '${isCover ? ' properties="cover-image"' : ''}/>\n');
    k++;
  }

  final opf = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">\n'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
      '<dc:identifier id="uid">${escapeText(uid)}</dc:identifier>\n'
      '<dc:title>${escapeText(book.bookTitle.isEmpty ? 'Untitled' : book.bookTitle)}</dc:title>\n'
      '<dc:language>${escapeText(lang)}</dc:language>\n'
      '${book.date.isEmpty ? '' : '<dc:date>${escapeText(book.date)}</dc:date>\n'}'
      '${author.isEmpty ? '' : '<dc:creator>${escapeText(author)}</dc:creator>\n'}'
      '${book.annotation.isEmpty ? '' : '<dc:description>${escapeText(book.annotation.join('\n'))}</dc:description>\n'}'
      '${book.keywords.isEmpty ? '' : book.keywords.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).map((s) => '<dc:subject>${escapeText(s)}</dc:subject>\n').join()}'
      '<meta property="dcterms:modified">$modified</meta>\n'
      '${coverItemId == null ? '' : '<meta name="cover" content="$coverItemId"/>\n'}'
      '</metadata>\n<manifest>\n$manifest</manifest>\n'
      '<spine toc="ncx">\n$spine</spine>\n</package>';

  final navItems = [
    for (final c in chapters) '<li><a href="${c.file}">${escapeText(c.title)}</a></li>'
  ].join('\n');
  final nav = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<html xmlns="$_xhtmlNs" xmlns:epub="$_epubNs"><head><title>Contents</title></head>'
      '<body><nav epub:type="toc"><h1>Contents</h1><ol>\n$navItems\n</ol></nav></body></html>';

  final ncxPoints = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    ncxPoints.write('<navPoint id="n$i" playOrder="${i + 1}"><navLabel><text>'
        '${escapeText(chapters[i].title)}</text></navLabel><content src="${chapters[i].file}"/></navPoint>\n');
  }
  final ncx = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head>'
      '<meta name="dtb:uid" content="${escapeText(uid)}"/></head>'
      '<docTitle><text>${escapeText(book.bookTitle)}</text></docTitle>'
      '<navMap>\n$ncxPoints</navMap></ncx>';

  final archive = Archive();
  // the mimetype entry must be first and stored uncompressed
  final mime = utf8.encode('application/epub+zip');
  archive.addFile(ArchiveFile.noCompress('mimetype', mime.length, mime));
  void text(String name, String content) =>
      archive.addFile(ArchiveFile.string('OEBPS/$name', content));
  archive.addFile(ArchiveFile.string(
      'META-INF/container.xml',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
      '</rootfiles></container>'));
  text('content.opf', opf);
  text('nav.xhtml', nav);
  text('toc.ncx', ncx);
  text('style.css', _css);
  for (final c in chapters) {
    text(c.file, c.xhtml);
  }
  for (final img in imageFiles.values) {
    archive.addFile(ArchiveFile.bytes('OEBPS/${img.name}', img.bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _css = 'body{line-height:1.4}p{margin:0;text-indent:1.2em;text-align:justify}'
    'h2,h3{text-align:center;text-indent:0}.subtitle{text-align:center;font-weight:bold;text-indent:0}'
    'blockquote{margin:1em 2em}.poem{margin:1em 2em}.poem p{text-indent:0}.stanza{margin-bottom:1em}'
    '.author{text-align:right;font-style:italic}img{max-width:100%}'
    '.image{text-align:center;text-indent:0}.note{margin:.5em 0}';

String _page(String title, String lang, String body, {required String css}) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<html xmlns="$_xhtmlNs" xmlns:epub="$_epubNs" xml:lang="${escapeXml(lang.isEmpty ? 'en' : lang)}">'
    '<head><meta charset="utf-8"/><title>${escapeText(title)}</title>'
    '<link rel="stylesheet" type="text/css" href="$css"/></head><body>\n$body</body></html>';

/// FB2 blocks as XHTML.
class _Fb2ToXhtml {
  final Map<String, ({String name, String type, List<int> bytes})> images;
  final Set<String> noteIds;
  _Fb2ToXhtml(this.images, this.noteIds);

  /// A stored section block; unreadable XML falls back to its plain text.
  String block(String xml) {
    try {
      return _node(XmlDocument.parse(xml).rootElement);
    } catch (_) {
      return '<p>${escapeText(xml.replaceAll(RegExp(r'<[^>]*>'), ''))}</p>\n';
    }
  }

  /// One footnote section, as an aside the note links can point at.
  String note(XmlElement sec) {
    final id = sec.getAttribute('id') ?? '';
    final inner = sec.childElements
        .where((e) => e.name.local != 'title')
        .map(_node)
        .join();
    final label = sec.childElements
        .where((e) => e.name.local == 'title')
        .map((e) => escapeText(e.innerText.trim()))
        .join(' ');
    return '<aside class="note" epub:type="footnote"${id.isEmpty ? '' : ' id="${escapeXml(id)}"'}>'
        '${label.isEmpty ? '' : '<p><strong>$label</strong></p>'}$inner</aside>\n';
  }

  String _children(XmlElement e) => e.children.map(_any).join();

  String _any(XmlNode n) => switch (n) {
        XmlText() => escapeText(n.value),
        XmlElement() => _inlineOrBlock(n),
        _ => '',
      };

  String _inlineOrBlock(XmlElement e) => switch (e.name.local) {
        'emphasis' => '<em>${_children(e)}</em>',
        'strong' => '<strong>${_children(e)}</strong>',
        'strikethrough' => '<del>${_children(e)}</del>',
        'sub' => '<sub>${_children(e)}</sub>',
        'sup' => '<sup>${_children(e)}</sup>',
        'code' => '<code>${_children(e)}</code>',
        'style' || 'span' => _children(e),
        'a' => _link(e),
        'image' => _image(e, inline: true),
        _ => _node(e),
      };

  String _href(XmlElement e) {
    for (final a in e.attributes) {
      if (a.name.local == 'href') return a.value;
    }
    return '';
  }

  String _link(XmlElement e) {
    final href = _href(e);
    final text = _children(e);
    if (href.startsWith('#')) {
      final id = href.substring(1);
      if (noteIds.contains(id)) {
        return '<a epub:type="noteref" href="notes.xhtml#${escapeXml(id)}">$text</a>';
      }
      return text; // an anchor inside the book that has no counterpart here
    }
    if (href.isEmpty) return text;
    return '<a href="${escapeXml(href)}">$text</a>';
  }

  String _image(XmlElement e, {bool inline = false}) {
    final img = images[_href(e)];
    if (img == null) return '';
    final tag = '<img src="../${escapeXml(img.name)}" alt="${escapeXml(e.getAttribute('alt') ?? '')}"/>';
    return inline ? tag : '<div class="image">$tag</div>\n';
  }

  String _node(XmlElement e) {
    switch (e.name.local) {
      case 'p':
        return '<p>${_children(e)}</p>\n';
      case 'subtitle':
        return '<p class="subtitle">${_children(e)}</p>\n';
      case 'empty-line':
        return '<p class="empty-line">&#160;</p>\n';
      case 'image':
        return _image(e);
      case 'text-author':
        return '<p class="author">${_children(e)}</p>\n';
      case 'cite' || 'epigraph':
        return '<blockquote>\n${e.childElements.map(_node).join()}</blockquote>\n';
      case 'poem':
        final b = StringBuffer('<div class="poem">\n');
        for (final c in e.childElements) {
          if (c.name.local == 'stanza') {
            b.write('<div class="stanza">');
            for (final v in c.childElements) {
              b.write(v.name.local == 'v' ? '<p>${_children(v)}</p>' : _node(v));
            }
            b.write('</div>\n');
          } else {
            b.write(_node(c));
          }
        }
        return (b..write('</div>\n')).toString();
      case 'title':
        return '<h3>${e.childElements.map((p) => _children(p)).join(' ')}</h3>\n';
      case 'table':
        return '<table>${e.childElements.map(_node).join()}</table>\n';
      case 'tr' || 'th' || 'td':
        return '<${e.name.local}>${_children(e)}</${e.name.local}>';
      case 'section':
        return e.childElements.map(_node).join();
      default:
        final inner = _children(e);
        return inner.trim().isEmpty ? '' : '<p>$inner</p>\n';
    }
  }
}

bool _isJpeg(List<int> b) => b.length > 2 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
