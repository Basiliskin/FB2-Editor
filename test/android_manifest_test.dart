import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the release manifest asks for no storage or media permission', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final declared = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
        .allMatches(manifest)
        .map((m) => m.group(1))
        .toList();
    expect(declared, ['com.google.android.gms.permission.AD_ID']);
  });
}
