import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';

void main() {
  test('BinaryResources.first returns the first resource', () {
    final r = BinaryResources([
      {'id': 'a', 'data': 'x', 'contentType': 'image/png'},
      {'id': 'b', 'data': 'y', 'contentType': 'image/png'}
    ]);
    expect(r.first().id, 'a');
  });

  group('Section', () {
    test('constructor swallows malformed input', () {
      final s = Section({'p': 5}, BinaryResources([]));
      expect(s.p, isEmpty);
    });

    test('removeImage keeps only the matching image', () {
      final s = Section({'sectionId': 's'}, BinaryResources([]))
        ..images = ['a', 'b'];
      s.removeImage('a');
      expect(s.images, ['a']);
    });
  });
}
