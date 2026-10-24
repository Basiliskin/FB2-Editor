final _whitespace = RegExp(r'\s');
final _closingPunctuation = RegExp(r'[.,!?;:)\]}»”…]');

// Whisper writes sounds it hears as labels such as [Bell rings], (applause),
// *music* or ♪ ♪, and may do so on silence. A real sentence is not wrapped
// whole in brackets, so short bracketed spans and note signs are dropped.
final _soundLabel = RegExp(r'\[[^\]\[]{1,40}\]|\([^)(]{1,40}\)|\*[^*]{1,40}\*|[♪♫]+');

/// [text] without Whisper's labels for non-speech sounds, tidied and trimmed.
/// Empty when nothing but labels was heard.
String stripSoundLabels(String text) => text
    .replaceAll(_soundLabel, ' ')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAllMapped(RegExp(r' +([.,!?;:])'), (m) => m[1]!)
    .trim();

/// Puts Dictation in place of the text between [start] and [end] (equal for a
/// bare cursor), adding a space on each side that touches other text, except
/// before punctuation. Returns the new text and the cursor offset just after
/// the dictated words, or null when nothing was dictated.
({String text, int cursor})? insertDictation(
  String existing,
  String dictated,
  int start,
  int end,
) {
  final addition = dictated.trim();
  if (addition.isEmpty) return null;
  final before = existing.substring(0, start);
  final after = existing.substring(end);
  final leading =
      before.isNotEmpty && !_whitespace.hasMatch(before[before.length - 1])
          ? ' '
          : '';
  final trailing = after.isNotEmpty &&
          !_whitespace.hasMatch(after[0]) &&
          !_closingPunctuation.hasMatch(after[0])
      ? ' '
      : '';
  final inserted = '$leading$addition';
  return (
    text: '$before$inserted$trailing$after',
    cursor: before.length + inserted.length,
  );
}
