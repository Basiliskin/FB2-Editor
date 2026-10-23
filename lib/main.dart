// import 'package:app/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:quill_fb2/pages/home_page.dart';
import 'package:quill_fb2/pages/start_page.dart';
import 'package:quill_fb2/prototype/prototype_switcher.dart'; // PROTOTYPE
import 'package:quill_fb2/prototype/prototype_theme.dart'; // PROTOTYPE
import 'utils/consts.dart';

import 'routes.dart';
import 'services/app.service.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final AppService _service = new AppService();
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // PROTOTYPE: rebuild on variant change; '0' keeps the original theme.
    return ValueListenableBuilder<String>(
        valueListenable: Proto.variant,
        builder: (context, v, _) => MaterialApp(
              key: ValueKey(v), // PROTOTYPE: rebuild every screen on switch
              title: _service.translate(LangTranslateItems.appTitle),
              theme: v == '0'
                  ? ThemeData(
                      primarySwatch: Colors.blue,
                      visualDensity: VisualDensity.adaptivePlatformDensity,
                    )
                  : modernTheme(),
              builder: (context, child) => PrototypeSwitcher(child: child!),
              home: StartScreen(_service),
              routes: {
                Routes.screenHome: (context) {
                  return HomeScreen(_service);
                }
              },
            ));
  }
}
