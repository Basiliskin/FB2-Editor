import 'package:flutter/widgets.dart';

import 'badge_position.dart';

class BadgePositioned extends StatelessWidget {
  final Widget? child;
  final BadgePosition? position;

  const BadgePositioned({Key? key, this.position, this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (position == null) {
      final topRight = BadgePosition.topEnd();
      return PositionedDirectional(
        top: topRight.top,
        end: topRight.end,
        child: child!,
      );
    }
    return PositionedDirectional(
      top: position!.top,
      end: position!.end,
      bottom: position!.bottom,
      start: position!.start,
      child: child!,
    );
  }
}
