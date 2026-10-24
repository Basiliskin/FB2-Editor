import 'package:quill_fb2/services/llm/llm_client.dart';
import 'package:xml/xml.dart';

/// What the model is told about the book.
class ImprovementContext {
  final String bookTitle;
  final String language;
  final String genre;
  final String styleNote;
  const ImprovementContext(
      {this.bookTitle = '',
      this.language = '',
      this.genre = '',
      this.styleNote = ''});
}

class Preset {
  final String name;
  final String instruction;

  /// Empty for the built-in presets; set for ones the user saved.
  final String id;
  const Preset(this.name, this.instruction, {this.id = ''});
  bool get custom => id.isNotEmpty;
}

const defaultPresets = [
  Preset('Proofread',
      'Fix spelling, grammar and punctuation. Do not change wording or meaning.'),
  Preset('Shorten',
      'Make each paragraph shorter while keeping its meaning and voice.'),
  Preset('Restyle',
      'Rewrite in a more vivid literary style. Keep the meaning, names and facts.'),
];

class ImprovementException implements Exception {
  final String message;

  /// The model ran out of room and the answer was cut off.
  final bool truncated;
  const ImprovementException(this.message, {this.truncated = false});
  @override
  String toString() => message;
}

/// Asks a [LlmClient] to rewrite paragraphs and checks the answer is safe to apply.
class ImprovementService {
  /// Largest request (characters of paragraph text) when no Provider sets one.
  static const maxChars = defaultChunkChars;

  final LlmClient client;
  const ImprovementService(this.client);

  static int estimateTokens(Iterable<String> texts) =>
      (texts.fold<int>(0, (n, t) => n + t.length) / 4).ceil();

  static int _size(Iterable<String> texts) =>
      texts.fold<int>(0, (n, t) => n + t.length);

  static bool tooLarge(Iterable<String> texts, [int limit = maxChars]) =>
      _size(texts) > limit;

  /// Groups paragraph indexes so each request stays under [limit]. A single
  /// paragraph over the limit cannot be sent at all.
  static List<List<int>> chunk(List<String> texts, [int limit = maxChars]) {
    final groups = <List<int>>[];
    var current = <int>[];
    var size = 0;
    for (var i = 0; i < texts.length; i++) {
      final n = texts[i].length;
      if (n > limit) throw const ImprovementException('too large');
      if (size + n > limit && current.isNotEmpty) {
        groups.add(current);
        current = [];
        size = 0;
      }
      current.add(i);
      size += n;
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  static String systemPrompt(ImprovementContext c) => [
        'You are an editor working on a fiction book.',
        if (c.bookTitle.isNotEmpty) 'Book: ${c.bookTitle}.',
        if (c.language.isNotEmpty) 'Language of the text: ${c.language}.',
        if (c.genre.isNotEmpty) 'Genre: ${c.genre}.',
        if (c.styleNote.isNotEmpty) 'Style note from the author: ${c.styleNote}',
        'You receive numbered paragraphs like "[1] text". Rewrite each one '
            'according to the instruction and answer with the same number of '
            'paragraphs, each starting with its marker on its own line, e.g. "[1] new text".',
        'Paragraphs may contain inline FB2 tags such as <emphasis>, <strong> or '
            '<a>. Keep every tag, valid and in place. Do not add tags.',
        'Answer with the paragraphs only: no comments, quotes or markdown.',
      ].join('\n');

  static String userPrompt(String instruction, List<String> texts) =>
      'Instruction: $instruction\n\n'
      '${[for (var i = 0; i < texts.length; i++) '[${i + 1}] ${texts[i]}'].join('\n')}';

  /// Rewrites [texts]. A request over [limit] is refused; an answer that was
  /// cut off is retried once as two halves.
  Future<List<String>> improve(
      List<String> texts, String instruction, ImprovementContext context,
      {int limit = maxChars}) async {
    if (texts.isEmpty) throw const ImprovementException('nothing to improve');
    if (tooLarge(texts, limit)) throw const ImprovementException('too large');
    return _ask(texts, instruction, context, canSplit: true);
  }

  Future<List<String>> _ask(
      List<String> texts, String instruction, ImprovementContext context,
      {required bool canSplit}) async {
    final answer = await client.complete(LlmRequest.sized(
        system: systemPrompt(context),
        user: userPrompt(instruction, texts),
        inputChars: _size(texts)));
    if (!answer.truncated) return parse(answer.text, texts);
    if (!canSplit || texts.length < 2) {
      throw const ImprovementException('the answer was cut off', truncated: true);
    }
    final mid = texts.length ~/ 2;
    return [
      ...await _ask(texts.sublist(0, mid), instruction, context, canSplit: false),
      ...await _ask(texts.sublist(mid), instruction, context, canSplit: false),
    ];
  }

  /// Splits [answer] into one text per paragraph and rejects anything that
  /// would damage the book: a wrong count, broken XML, or changed tags.
  static List<String> parse(String answer, List<String> originals) {
    final cleaned =
        answer.replaceAll(RegExp(r'^\s*```\w*\s*|\s*```\s*$'), '').trim();
    final markers = RegExp(r'^\[(\d+)\][ \t]?', multiLine: true).allMatches(cleaned).toList();
    if (markers.length != originals.length) {
      throw const ImprovementException('unexpected number of paragraphs');
    }
    final out = <String>[];
    for (var i = 0; i < markers.length; i++) {
      if (int.parse(markers[i].group(1)!) != i + 1) {
        throw const ImprovementException('paragraphs out of order');
      }
      final end = i + 1 < markers.length ? markers[i + 1].start : cleaned.length;
      final text =
          cleaned.substring(markers[i].end, end).replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();
      if (text.isEmpty) throw const ImprovementException('empty paragraph');
      if (!_sameTags(originals[i], text)) {
        throw const ImprovementException('tags were changed');
      }
      out.add(text);
    }
    return out;
  }

  static List<String>? _tags(String inline) {
    try {
      final names = XmlDocument.parse('<p>$inline</p>')
          .rootElement
          .descendantElements
          .map((e) => e.name.local)
          .toList()
        ..sort();
      return names;
    } catch (_) {
      return null;
    }
  }

  static bool _sameTags(String original, String result) {
    final a = _tags(original), b = _tags(result);
    if (b == null) return false; // malformed XML
    if (a == null) return true; // original already odd: nothing to compare
    return a.join(',') == b.join(',');
  }
}
