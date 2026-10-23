import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';

BinaryResources _res([List<Map> items = const []]) => BinaryResources(items);

void main() {
  group('Section constructor', () {
    test('reads title, paragraphs and id', () {
      final s = Section(
          {'title': 'T', 'p': ['<p>a</p>', '<p>b</p>'], 'sectionId': 'sid'},
          _res());
      expect(s.title, 'T');
      expect(s.p, ['<p>a</p>', '<p>b</p>']);
      expect(s.sectionId, 'sid');
    });

    test('generates a 7-char id when none is given', () {
      final s = Section({'title': 'T'}, _res());
      expect(s.sectionId.length, 7);
    });

    test('links an unowned image resource to the section', () {
      final res = _res([
        {'id': 'img1', 'data': 'AAAA', 'contentType': 'image/jpeg'}
      ]);
      final s = Section({'img': ['#img1'], 'sectionId': 'sid'}, res);
      expect(s.images, ['#img1']);
      expect(res.find('#img1').sectionId, 'sid');
    });

    test('does not steal an image already owned by another section', () {
      final res = _res([
        {'id': 'img1', 'data': 'A', 'contentType': 'x', 'sectionId': 'other'}
      ]);
      Section({'img': ['#img1'], 'sectionId': 'sid'}, res);
      expect(res.find('#img1').sectionId, 'other');
    });
  });

  group('Section.toXml', () {
    test('wraps title and paragraphs', () {
      final s = Section(
          {'title': 'T', 'p': ['<p>a</p>'], 'sectionId': 'sid'}, _res());
      expect(s.toXml(),
          '<section section-id="sid">\n<title><p>T</p></title>\n<p>a</p>\n</section>');
    });

    test('omits empty title and emits first image', () {
      final s = Section({'title': '', 'sectionId': 'sid'}, _res());
      s.setImage('#i1');
      final xml = s.toXml();
      expect(xml, isNot(contains('<title>')));
      expect(xml, contains('<image xlink:href="#i1" alt="img_sid.jpg"/>'));
    });
  });

  group('Section image helpers', () {
    late Section s;
    setUp(() => s = Section({'sectionId': 'sid'}, _res()));

    test('setImage replaces and clears', () {
      s.setImage('#a');
      expect(s.images, ['#a']);
      s.setImage('');
      expect(s.images, isEmpty);
    });

    test('addImage keeps a single image', () {
      s.addImage('#a');
      s.addImage('#b');
      expect(s.images, ['#b']);
    });

    test('containImage', () {
      s.setImage('#a');
      expect(s.containImage('#a'), isTrue);
      expect(s.containImage('#b'), isFalse);
    });
  });

  group('Section.load', () {
    test('wraps each line in <p> and replaces existing content', () {
      final s = Section({'p': ['<p>old</p>']}, _res());
      s.load('one\ntwo\r\nthree');
      expect(s.p, ['<p>one</p>', '<p>two</p>', '<p>three</p>']);
    });
  });

  group('Section.toDelta / parseP', () {
    test('empty section yields a single newline insert', () {
      final s = Section({}, _res());
      expect(s.toDelta(), [
        {'insert': '\n'}
      ]);
    });

    test('plain paragraph text becomes one insert with trailing newline', () {
      final s = Section({'p': ['<p>Hello</p>']}, _res());
      expect(s.toDelta(), [
        {'insert': 'Hello\n'}
      ]);
    });

    test('inline markup is kept as raw XML in its own insert', () {
      final s = Section({'p': ['<p>a <strong>b</strong></p>']}, _res());
      expect(s.toDelta(), [
        {'insert': 'a \n'},
        {'insert': '<strong>b</strong>\n'}
      ]);
    });

    test('malformed paragraph XML is swallowed, falling back to empty delta',
        () {
      final s = Section({'p': ['<p>unclosed']}, _res());
      expect(s.toDelta(), [
        {'insert': '\n'}
      ]);
    });

    test('getIfEmpty prefers the value over the fallback', () {
      final s = Section({}, _res());
      expect(s.getIfEmpty('', 'fb'), 'fb');
      expect(s.getIfEmpty('v', 'fb'), 'v');
    });
  });

  group('Section paging', () {
    Section make() => Section({
          'p': ['<p>a</p>', '<p>b</p>', '<p>c</p>', '<p>d</p>']
        }, _res());

    test('loadRange replaces only the page and returns the new end', () {
      final s = make();
      final end = s.loadRange(1, 3, 'x\ny\nz\n');
      expect(s.p, ['<p>a</p>', '<p>x</p>', '<p>y</p>', '<p>z</p>', '<p>d</p>']);
      expect(end, 4);
    });
  });
}
