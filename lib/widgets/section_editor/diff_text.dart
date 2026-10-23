import 'package:flutter/material.dart';

/// One word of a diff: 0 unchanged, -1 removed, 1 added.
typedef DiffWord = (int, String);

List<DiffWord> wordDiff(String a, String b) {
  final x = a.split(' '), y = b.split(' ');
  final l = List.generate(x.length + 1, (_) => List.filled(y.length + 1, 0));
  for (var i = x.length - 1; i >= 0; i--) {
    for (var j = y.length - 1; j >= 0; j--) {
      l[i][j] = x[i] == y[j]
          ? l[i + 1][j + 1] + 1
          : (l[i + 1][j] > l[i][j + 1] ? l[i + 1][j] : l[i][j + 1]);
    }
  }
  final out = <DiffWord>[];
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    if (x[i] == y[j]) {
      out.add((0, x[i]));
      i++;
      j++;
    } else if (l[i + 1][j] >= l[i][j + 1]) {
      out.add((-1, x[i++]));
    } else {
      out.add((1, y[j++]));
    }
  }
  while (i < x.length) {
    out.add((-1, x[i++]));
  }
  while (j < y.length) {
    out.add((1, y[j++]));
  }
  return out;
}

/// [before] with removed words struck through and added words highlighted.
class DiffText extends StatelessWidget {
  final String before, after;
  final double fontSize;
  const DiffText(this.before, this.after, {super.key, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(TextSpan(
        style: TextStyle(fontSize: fontSize, height: 1.3, color: scheme.onSurface),
        children: [
          for (final (op, w) in wordDiff(before, after))
            TextSpan(
                text: '$w ',
                style: op == 0
                    ? null
                    : op < 0
                        ? TextStyle(
                            color: scheme.error,
                            decoration: TextDecoration.lineThrough)
                        : TextStyle(
                            backgroundColor: Colors.green.withValues(alpha: .3))),
        ]));
  }
}
