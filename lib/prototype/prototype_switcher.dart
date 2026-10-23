// PROTOTYPE - THROWAWAY. Floating variant switcher + variant state.
// Question: "modern, user-friendly UI that doesn't scare existing users".
// Three variants of HomeScreen (+ '0' = current UI as control), `?variant=`.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prototype_url_stub.dart' if (dart.library.html) 'prototype_url_web.dart'
    as url;

const kVariants = {
  '0': 'Original (control)',
  'A': 'Familiar, refreshed',
  'B': 'Library shelf',
  'C': 'Workspace',
};

class Proto {
  static final ValueNotifier<String> variant = ValueNotifier(_initial());
  static bool get enabled => !kReleaseMode;
  /// Everything except the original control variant uses the new design.
  static bool get modern => variant.value != '0';

  static String _initial() {
    final v = url.readVariantFromUrl()?.toUpperCase();
    return kVariants.containsKey(v) ? v! : 'A';
  }

  static void set(String v) {
    variant.value = v;
    url.writeVariantToUrl(v);
  }

  static void cycle(int delta) {
    final keys = kVariants.keys.toList();
    final i = keys.indexOf(variant.value);
    set(keys[(i + delta) % keys.length]);
  }
}

class PrototypeSwitcher extends StatefulWidget {
  final Widget child;
  const PrototypeSwitcher({super.key, required this.child});
  @override
  State<PrototypeSwitcher> createState() => _PrototypeSwitcherState();
}

class _PrototypeSwitcherState extends State<PrototypeSwitcher> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.findAncestorWidgetOfExactType<EditableText>() != null ||
        focus?.widget is EditableText) return false;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) Proto.cycle(-1);
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) Proto.cycle(1);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!Proto.enabled) return widget.child;
    return Stack(children: [
      widget.child,
      Positioned(
        left: 0,
        right: 0,
        bottom: 16,
        child: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: Proto.variant,
            builder: (_, v, __) => Material(
              color: const Color(0xFF111111),
              elevation: 8,
              shape: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => Proto.cycle(-1)),
                  Text('$v  ${kVariants[v]}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          decoration: TextDecoration.none)),
                  IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => Proto.cycle(1)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
