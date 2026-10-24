import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'dictation_text.dart';

/// Where in a target's text a Dictation goes: the cursor, or a selection.
typedef DictationAnchor = ({int start, int end});

/// A text control that can receive Dictation.
abstract interface class DictationTarget {
  /// The cursor or selection to dictate into, clamped to the text. At the end
  /// of the text when the control has no selection yet.
  DictationAnchor anchor();

  /// Puts [dictated] at [anchor] and returns whether anything was inserted.
  bool insert(DictationAnchor anchor, String dictated);
}

DictationAnchor _clamp(int start, int end, int length) {
  if (start < 0 || end < 0) return (start: length, end: length);
  final s = start > length ? length : start;
  final e = end > length ? length : end;
  return s <= e ? (start: s, end: e) : (start: e, end: s);
}

/// A plain text field.
class TextFieldDictationTarget implements DictationTarget {
  TextFieldDictationTarget(this.controller);

  final TextEditingController controller;

  @override
  DictationAnchor anchor() {
    final selection = controller.selection;
    return _clamp(selection.start, selection.end, controller.text.length);
  }

  @override
  bool insert(DictationAnchor anchor, String dictated) {
    final text = controller.text;
    final a = _clamp(anchor.start, anchor.end, text.length);
    final result = insertDictation(text, dictated, a.start, a.end);
    if (result == null) return false;
    controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
    return true;
  }
}

/// The paragraph being edited in Quill. The edit is a single replaceText call,
/// so one Undo takes the whole Dictation back, and the text takes the
/// formatting at the cursor as if it had been typed.
class QuillDictationTarget implements DictationTarget {
  QuillDictationTarget(this.controller);

  final QuillController controller;

  // Quill always keeps one trailing newline that no edit may replace.
  String get _text {
    final plain = controller.document.toPlainText();
    return plain.endsWith('\n') ? plain.substring(0, plain.length - 1) : plain;
  }

  @override
  DictationAnchor anchor() {
    final selection = controller.selection;
    return _clamp(selection.start, selection.end, _text.length);
  }

  @override
  bool insert(DictationAnchor anchor, String dictated) {
    final text = _text;
    final a = _clamp(anchor.start, anchor.end, text.length);
    final result = insertDictation(text, dictated, a.start, a.end);
    if (result == null) return false;
    final replacement = result.text.substring(
      a.start,
      result.text.length - (text.length - a.end),
    );
    controller.replaceText(
      a.start,
      a.end - a.start,
      replacement,
      TextSelection.collapsed(offset: result.cursor),
    );
    return true;
  }
}
