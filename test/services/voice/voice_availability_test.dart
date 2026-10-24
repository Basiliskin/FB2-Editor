import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/services/voice/voice_availability.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('is supported on Android only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(voiceInputSupported, isTrue);
    for (final p in [
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux
    ]) {
      debugDefaultTargetPlatformOverride = p;
      expect(voiceInputSupported, isFalse, reason: '$p');
    }
  });

  test('is off by default and follows the setting on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(voiceInputEnabled({}), isFalse);
    expect(voiceInputEnabled({'voice-input': false}), isFalse);
    expect(voiceInputEnabled({'voice-input': 'false'}), isFalse);
    expect(voiceInputEnabled({'voice-input': true}), isTrue);
    expect(voiceInputEnabled({'voice-input': 'true'}), isTrue);
  });

  test('stays off elsewhere even when the setting is on', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(voiceInputEnabled({'voice-input': true}), isFalse);
  });
}
