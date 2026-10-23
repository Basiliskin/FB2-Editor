import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadBytes(String fileName, List<int> bytes, String mimeType) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

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
