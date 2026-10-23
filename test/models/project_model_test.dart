import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/utils/consts.dart';

Map<String, dynamic> _json({
  List sections = const [],
  List resources = const [],
  Map description = const {},
  String bodyTitle = '',
}) =>
    {
      'bodyTitle': bodyTitle,
      'description': {'description': description},
      'resources': resources,
      'sections': sections,
    };

void main() {
  group('CoverImage', () {
    test('picks href and alt from namespaced keys', () {
      final c = CoverImage({'@l:href': '#cover', '@alt': 'a'});
      expect(c.href, '#cover');
      expect(c.alt, 'a');
    });
    test('defaults to empty', () {
      final c = CoverImage({});
      expect([c.href, c.alt], ['', '']);
    });
  });

  group('Author', () {
    test('loads from a single author map', () {
      final a = Author({
        'author': {
          'first-name': {r'$': 'Leo'},
          'last-name': {r'$': 'Tolstoy'},
        }
      });
      expect(a.firstName, 'Leo');
      expect(a.lastName, 'Tolstoy');
      expect(a.middleName, '');
    });

    test('last author wins when a list is given', () {
      final a = Author({
        'author': [
          {'first-name': {r'$': 'A'}},
          {'first-name': {r'$': 'B'}},
        ]
      });
      expect(a.firstName, 'B');
    });

    test('missing author leaves all fields empty', () {
      final a = Author({});
      expect(a.firstName + a.lastName + a.nickname, '');
    });

    test('toXml serializes every field', () {
      final a = Author({})
        ..firstName = 'F'
        ..lastName = 'L';
      expect(
          a.toXml(),
          '<author><first-name>F</first-name><middle-name></middle-name>'
          '<last-name>L</last-name><home-page></home-page><id></id>'
          '<nickname></nickname></author>');
    });
  });

  group('BinaryResources', () {
    final item = {
      'id': 'a.jpg',
      'contentType': 'image/jpeg',
      'data': 'DATA',
      'sectionId': 's1'
    };

    test('accepts a single map or a list', () {
      expect(BinaryResources(item).resources, hasLength(1));
      expect(BinaryResources([item, item]).resources, hasLength(2));
    });

    test('find matches by "#id" and returns an empty Resource if absent', () {
      final r = BinaryResources([item]);
      expect(r.find('#a.jpg').data, 'DATA');
      expect(r.find('#nope').id, '');
    });

    test('findBySectionId', () {
      final r = BinaryResources([item]);
      expect(r.findBySectionId('s1').id, 'a.jpg');
      expect(r.findBySectionId('zzz').id, '');
    });

    test('removeSectionImage removes only that section', () {
      final r = BinaryResources([
        item,
        {...item, 'id': 'b.jpg', 'sectionId': 's2'}
      ]);
      r.removeSectionImage('s1');
      expect(r.resources.map((e) => e.id), ['b.jpg']);
    });

    group('replace', () {
      test('updates data of an existing resource', () {
        final r = BinaryResources([item]);
        r.replace('#a.jpg', 'NEW');
        expect(r.find('#a.jpg').data, 'NEW');
      });
      test('removes the resource when data is empty', () {
        final r = BinaryResources([item]);
        r.replace('#a.jpg', '');
        expect(r.resources, isEmpty);
      });
      test('adds a jpg resource when id is unknown', () {
        final r = BinaryResources([]);
        r.replace('#new', 'D');
        expect(r.resources.single.id, 'new');
        expect(r.resources.single.contentType, 'image/jpg');
      });
      test('is a no-op for unknown id with empty data', () {
        final r = BinaryResources([]);
        r.replace('#new', '');
        expect(r.resources, isEmpty);
      });
    });

    test('toXml emits one <binary> element per resource', () {
      final xml = BinaryResources([item]).toXml();
      expect(
          xml,
          '<binary content-type="image/jpeg" id="a.jpg" section-id="s1">'
          'DATA</binary>\n');
    });
  });

  group('ProjectModel construction', () {
    test('uses supplied project id, else generates a 16-char one', () {
      expect(ProjectModel(_json(), 'pid').projectId, 'pid');
      expect(ProjectModel(_json()).projectId.length, 16);
    });

    test('reads title-info and document-info', () {
      final p = ProjectModel(_json(description: {
        'title-info': {
          'book-title': {r'$': 'Book'},
          'lang': {r'$': 'ru'},
          'date': {r'$': '2020'},
          'author': {
            'first-name': {r'$': 'Ann'},
            'last-name': {r'$': 'Lee'}
          },
          'annotation': {
            'p': [
              {r'$': 'one'},
              {r'$': 'two'}
            ]
          },
          'genre': [
            {r'$': 'prose'},
            {r'$': 'sf'}
          ],
          'sequence': {'@name': 'Saga'},
        },
        'document-info': {
          'program-used': {r'$': 'prog'},
          'id': {r'$': 'doc-id'},
          'version': {r'$': '1.2'},
          'src-url': {r'$': 'http://x'},
        }
      }));
      expect(p.bookTitle, 'Book');
      expect(p.lang, 'ru');
      expect(p.date, '2020');
      expect(p.getAuthor(), 'Ann Lee');
      expect(p.annotation, ['one', 'two']);
      expect(p.genre, ['prose', 'sf']);
      expect(p.sequence, ['Saga']);
      expect(p.programUsed, 'prog');
      expect(p.id, 'doc-id');
      expect(p.version, '1.2');
      expect(p.srcUrl, 'http://x');
    });

    test('bodyTitle takes precedence over book-title', () {
      final p = ProjectModel(_json(bodyTitle: 'Body', description: {
        'title-info': {
          'book-title': {r'$': 'Info'}
        }
      }));
      expect(p.getBookTitle(), 'Body');
    });

    test('single genre / annotation paragraph maps are supported', () {
      final p = ProjectModel(_json(description: {
        'title-info': {
          'genre': {r'$': 'prose'},
          'annotation': {
            'p': {r'$': 'only'}
          }
        }
      }));
      expect(p.genre, ['prose']);
      expect(p.annotation, ['only']);
    });

    test('tolerates a completely empty description', () {
      final p = ProjectModel(_json());
      expect(p.bookTitle, '');
      expect(p.section, isEmpty);
      expect(p.getSequence(), '');
    });

    test('falls back to the first resource as coverpage', () {
      final p = ProjectModel(_json(resources: [
        {'id': 'c.jpg', 'contentType': 'image/jpeg', 'data': 'D'}
      ]));
      expect(p.coverpage.href, '#c.jpg');
    });

    test('marks the declared cover resource with sectionId "cover"', () {
      final p = ProjectModel(_json(resources: [
        {'id': 'c.jpg', 'contentType': 'image/jpeg', 'data': 'D'}
      ], description: {
        'title-info': {
          'coverpage': {
            'image': {'@l:href': '#c.jpg'}
          }
        }
      }));
      expect(p.binaryResource.find('#c.jpg').sectionId, 'cover');
    });

    test('getSequence joins with "| "', () {
      final p = ProjectModel(_json())..sequence = ['a', 'b'];
      expect(p.getSequence(), 'a| b');
    });
  });

  group('ProjectModel sections', () {
    test('loads a section and keeps its id', () {
      final p = ProjectModel(_json(sections: [
        {'title': 'Ch1', 'p': ['<p>x</p>'], 'sectionId': 's1', 'img': []}
      ]));
      expect(p.section.single.title, 'Ch1');
      expect(p.section.single.sectionId, 's1');
    });

    test('skips sections without paragraphs', () {
      final p = ProjectModel(_json(sections: [
        {'title': 'Empty', 'p': [], 'sectionId': 's1'}
      ]));
      expect(p.section, isEmpty);
    });

    test('splits oversized sections into MAX_SECTION_LENGTH chunks', () {
      final paras = List.generate(MAX_SECTION_LENGTH * 2 + 1, (i) => '<p>$i</p>');
      final p = ProjectModel(_json(sections: [
        {'title': 'Big', 'p': paras, 'sectionId': 's1'}
      ]));
      expect(p.section, hasLength(3));
      expect(p.section[0].title, 'Big - 0');
      expect(p.section[1].title, 'Big - $MAX_SECTION_LENGTH');
      expect(p.section[0].p, hasLength(MAX_SECTION_LENGTH));
      expect(p.section[2].p, hasLength(1));
    });

    test('keeps only the first image that has a resource', () {
      final p = ProjectModel(_json(resources: [
        {'id': 'i2', 'contentType': 'image/jpeg', 'data': 'D'}
      ], sections: [
        {
          'title': 'T',
          'p': ['<p>x</p>'],
          'img': ['#missing', '#i2'],
          'sectionId': 's1'
        }
      ]));
      expect(p.section.single.images, ['i2']);
    });

    test('addSection appends a titled empty section', () {
      final p = ProjectModel(_json());
      final s = p.addSection('Hello');
      expect(p.section, [s]);
      expect(s.title, 'Hello');
      expect(p.addSection().title, 'New Section');
    });

    test('removeSelected drops sections by id', () {
      final p = ProjectModel(_json());
      final a = p.addSection('a');
      final b = p.addSection('b');
      p.removeSelected({a.sectionId: a});
      expect(p.section, [b]);
    });

    test('addSecionImage replaces the section image', () {
      final p = ProjectModel(_json());
      final s = p.addSection('a');
      p.addSecionImage(s, 'DATA1');
      expect(s.images, hasLength(1));
      expect(p.binaryResource.resources, hasLength(1));
      p.addSecionImage(s, 'DATA2');
      expect(p.binaryResource.resources, hasLength(1));
      expect(p.binaryResource.resources.single.data, 'DATA2');
      p.addSecionImage(s, '');
      expect(s.images, isEmpty);
      expect(p.binaryResource.resources, isEmpty);
    });

    test('getImageBySectionId returns data or empty string', () {
      final p = ProjectModel(_json());
      final s = p.addSection('a');
      p.addSecionImage(s, 'DATA');
      expect(p.getImageBySectionId(s.sectionId), 'DATA');
      expect(p.getImageBySectionId('none'), '');
    });
  });

  group('ProjectModel.getBookXml', () {
    test('emits a well-formed FictionBook with metadata and sections', () {
      final p = ProjectModel(_json(bodyTitle: 'My Book'))
        ..genre = ['prose']
        ..sequence = ['Saga']
        ..annotation = ['line1\nline2', '']
        ..lang = 'en';
      p.author.firstName = 'Ann';
      p.addSection('Ch1');
      final xml = p.getBookXml() as String;
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<genre>prose</genre>'));
      expect(xml, contains('<sequence name="Saga"/>'));
      expect(xml, contains('<annotation>'));
      expect(xml, contains('<p>line1</p>'));
      expect(xml, contains('<p>line2</p>'));
      expect(xml, contains('<lang>en</lang>'));
      expect(xml, contains('<first-name>Ann</first-name>'));
      expect(xml, contains('<title>My Book</title>'));
      expect(xml, contains('<title><p>Ch1</p></title>'));
      expect(xml.trimRight(), endsWith('</FictionBook>'));
    });

    test('omits <annotation> and <coverpage> when absent', () {
      final xml = ProjectModel(_json()).getBookXml() as String;
      expect(xml, isNot(contains('<annotation>')));
      expect(xml, isNot(contains('<coverpage>')));
    });

    test('references the cover resource', () {
      final p = ProjectModel(_json(resources: [
        {'id': 'c.jpg', 'contentType': 'image/jpeg', 'data': 'D'}
      ], description: {
        'title-info': {
          'coverpage': {
            'image': {'@l:href': '#c.jpg'}
          }
        }
      }));
      final xml = p.getBookXml() as String;
      expect(xml, contains('<image l:href="#c.jpg" alt="coverpage"/>'));
      expect(xml, contains('<binary content-type="image/jpeg" id="c.jpg"'));
    });
  });
}
