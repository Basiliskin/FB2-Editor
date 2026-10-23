import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart' as platform;

Future<void> downloadFile(String fileName, String contents) {
  return platform.downloadFile(fileName, contents);
}

Future<void> downloadBytes(String fileName, List<int> bytes, String mimeType) {
  return platform.downloadBytes(fileName, bytes, mimeType);
}