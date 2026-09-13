// import 'package:app/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:quill_fb2/pages/home_page.dart';
import 'package:quill_fb2/pages/start_page.dart';
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
    return MaterialApp(
      title: _service.translate(LangTranslateItems.appTitle),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: StartScreen(_service),
      routes: {
        Routes.screenHome: (context) {
          return HomeScreen(_service);
        }
      },
    );
  }
}
