import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/utils/file_download.dart';

void main() {
  test('downloadFile is unsupported outside web', () {
    expect(() => downloadFile('a.fb2', '<x/>'), throwsUnsupportedError);
  });
}
