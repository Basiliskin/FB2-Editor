import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/models/section.model.dart';
import 'package:quill_fb2/services/llm/improvement.dart';
import 'package:quill_fb2/services/llm/llm_client.dart';

class _Fake implements LlmClient {
  final String answer;
  LlmRequest? seen;
  _Fake(this.answer);
  @override
  Future<String> complete(LlmRequest r) async {
    seen = r;
    return answer;
  }
}

void main() {
  const orig = ['one <strong>two</strong>', 'three'];

  group('parse', () {
    test('splits numbered paragraphs', () {
      expect(ImprovementService.parse('[1] a <strong>b</strong>\n[2] c', orig),
          ['a <strong>b</strong>', 'c']);
    });

    test('joins a paragraph the model wrapped over several lines', () {
      expect(ImprovementService.parse('[1] a <strong>b</strong>\ncontinued\n[2] c', orig)[0],
          'a <strong>b</strong> continued');
    });

    test('ignores a code fence around the answer', () {
      expect(
          ImprovementService.parse('```\n[1] a <strong>b</strong>\n[2] c\n```', orig),
          ['a <strong>b</strong>', 'c']);
    });

    test('rejects the wrong number of paragraphs', () {
      expect(() => ImprovementService.parse('[1] only', orig),
          throwsA(isA<ImprovementException>()));
    });

    test('rejects dropped or added tags', () {
      expect(() => ImprovementService.parse('[1] plain\n[2] c', orig),
          throwsA(isA<ImprovementException>()));
      expect(() => ImprovementService.parse('[1] a <strong>b</strong>\n[2] <emphasis>c</emphasis>', orig),
          throwsA(isA<ImprovementException>()));
    });

    test('rejects malformed XML', () {
      expect(() => ImprovementService.parse('[1] a <strong>b\n[2] c', orig),
          throwsA(isA<ImprovementException>()));
    });

    test('rejects an empty paragraph', () {
      expect(() => ImprovementService.parse('[1] a <strong>b</strong>\n[2] ', orig),
          throwsA(isA<ImprovementException>()));
    });
  });

  group('improve', () {
    test('sends context, instruction and numbered paragraphs', () async {
      final fake = _Fake('[1] a <strong>b</strong>\n[2] c');
      final r = await ImprovementService(fake).improve(
          orig,
          'Fix it',
          const ImprovementContext(
              bookTitle: 'Dune', language: 'en', styleNote: 'keep it terse'));
      expect(r.length, 2);
      expect(fake.seen!.system, contains('Dune'));
      expect(fake.seen!.system, contains('keep it terse'));
      expect(fake.seen!.user, contains('Instruction: Fix it'));
      expect(fake.seen!.user, contains('[2] three'));
    });

    test('refuses a request over the size limit without calling the model',
        () async {
      final fake = _Fake('');
      await expectLater(
          ImprovementService(fake)
              .improve(['x' * (ImprovementService.maxChars + 1)], 'i', const ImprovementContext()),
          throwsA(isA<ImprovementException>()));
      expect(fake.seen, isNull);
    });
  });

  group('Section', () {
    Section s(List<String> p) =>
        Section({'p': p, 'sectionId': 's'}, BinaryResources([]));

    test('only plain paragraphs can be improved', () {
      final sec = s(['<p>a</p>', '<image xlink:href="#i"/>', '<poem><stanza><v>x</v></stanza></poem>']);
      expect([for (var i = 0; i < 3; i++) sec.isTextParagraph(i)], [true, false, false]);
    });

    test('applyTexts rewrites the chosen paragraphs and keeps the rest', () {
      final sec = s(['<p>a</p>', '<p>b</p>', '<p>c</p>']);
      sec.applyTexts({0: 'A <emphasis>x</emphasis>', 2: 'C'});
      expect(sec.p, ['<p>A <emphasis>x</emphasis></p>', '<p>b</p>', '<p>C</p>']);
    });
  });
}
