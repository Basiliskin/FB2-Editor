class BadgePosition {
  final double top;
  final double end;
  final double bottom;
  final double start;

  const BadgePosition(
      {this.top = 0, this.end = 0, this.bottom = 0, this.start = 0});

  factory BadgePosition.topStart({double top = -8, double start = -10}) {
    return BadgePosition(top: top, start: start);
  }

  factory BadgePosition.topEnd({double top = -8, double end = 0}) {
    return BadgePosition(top: top, end: end);
  }

  factory BadgePosition.bottomEnd({double bottom = -8, double end = -10}) {
    return BadgePosition(bottom: bottom, end: end);
  }

  factory BadgePosition.bottomStart({double bottom = -8, double start = -10}) {
    return BadgePosition(bottom: bottom, start: start);
  }
}
