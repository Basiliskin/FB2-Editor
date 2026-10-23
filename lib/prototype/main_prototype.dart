// PROTOTYPE - THROWAWAY. Standalone entry that avoids the editor imports
// (flutter_quill 11.5.0 does not compile on Flutter 3.47, so the real app
// cannot be built). Same variants as HomeScreen, with stub books + no-op actions.
//   flutter run -d chrome -t lib/prototype/main_prototype.dart
import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';

import 'home_variants.dart';
import 'prototype_switcher.dart';
import 'prototype_theme.dart';
import 'screens_b.dart';

void main() => runApp(const _ProtoApp());

class _ProtoApp extends StatelessWidget {
  const _ProtoApp();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: Proto.variant,
        builder: (_, v, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:
              v == '0' ? ThemeData(primarySwatch: Colors.blue) : modernTheme(),
          builder: (_, child) => PrototypeSwitcher(child: child!),
          home: const _ProtoHome(),
        ),
      );
}

class _ProtoHome extends StatelessWidget {
  const _ProtoHome();
  @override
  Widget build(BuildContext context) {
    final service = AppService();
    void note(String s) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Prototype: $s (no-op)')));
    final modern = Proto.variant.value != '0';
    final actions = HomeActions(
        () async => note('open file'),
        (b) async => modern
            ? Navigator.push(context,
                MaterialPageRoute(builder: (_) => BookScreenB(b, service)))
            : note('open book'),
        (_) async => note('remove'),
        () => modern
            ? Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreenB()))
            : note('settings'));
    return ValueListenableBuilder<String>(
      valueListenable: Proto.variant,
      builder: (_, v, __) => switch (v) {
        'A' => HomeVariantA(service, actions),
        'B' => HomeVariantB(service, actions),
        'C' => HomeVariantC(service, actions),
        _ => HomeVariantOriginal(service, actions),
      },
    );
  }
}
