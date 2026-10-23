import 'package:flutter/material.dart';

const _cream = Color(0xFFF1E4D0);
const _amber = Color(0xFFE9A23B);
const _ink = Color(0xFF2B1E1A);

/// App logo (book spines on a shelf) that builds itself up in a loop.
class LogoLoader extends StatefulWidget {
  final double size;
  const LogoLoader({this.size = 140, super.key});

  @override
  State<LogoLoader> createState() => _LogoLoaderState();
}

class _LogoLoaderState extends State<LogoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size * 66 / 72),
        painter: _LogoPainter(_controller.value),
      ),
    );
  }
}

double _segment(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

class _LogoPainter extends CustomPainter {
  final double t;
  _LogoPainter(this.t);

  // x, top of the full-height spine, full height (logo viewBox units)
  static const _spines = [
    [26.0, 30.0, 50.0],
    [40.0, 38.0, 42.0],
    [54.0, 30.0, 50.0],
    [69.0, 38.0, 42.0],
  ];
  static const _leanDegrees = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 72);
    canvas.translate(-18, -24); // crop the 108 viewBox to the artwork

    final fadeOut = 1 - Curves.easeIn.transform(_segment(t, 0.88, 1.0));
    final grow = [
      for (var i = 0; i < 4; i++)
        Curves.easeOutBack.transform(_segment(t, i * 0.12, i * 0.12 + 0.35)) *
            fadeOut,
    ];
    final lean = _leanDegrees *
        Curves.easeOut.transform(_segment(t, 0.55, 0.8)) *
        grow[3];
    final shelfWidth = 64 * Curves.easeOut.transform(_segment(t, 0, 0.2));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(54 - shelfWidth / 2, 83, shelfWidth, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = _amber,
    );

    for (var i = 0; i < 4; i++) {
      final height = _spines[i][2] * grow[i];
      if (height <= 0.01) continue;
      final x = _spines[i][0];
      canvas.save();
      if (i == 3) {
        canvas.translate(74, 80);
        canvas.rotate(lean * 3.1415926535 / 180);
        canvas.translate(-74, -80);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 80 - height, 11, height), const Radius.circular(2)),
        Paint()..color = i == 3 ? _amber : _cream,
      );
      if ((i == 0 || i == 2) && grow[i] > 0.9) {
        for (final y in [40.0, 45.0]) {
          canvas.drawRect(Rect.fromLTWH(x, y, 11, 2), Paint()..color = _ink);
        }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.t != t;
}
