import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadFile(String fileName, String contents) async {
  final dataUri = Uri.dataFromString(
    contents,
    mimeType: 'application/xml',
    encoding: utf8,
  );
  final anchor = html.AnchorElement(href: dataUri.toString())
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
