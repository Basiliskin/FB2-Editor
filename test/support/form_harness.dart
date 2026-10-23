import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';

/// Hosts [child] in an [EasyForm] and records the values of every save.
class FormHarness {
  final saves = <Map<String, dynamic>>[];
  final _trigger = StreamController<void>.broadcast();

  Map<String, dynamic> get lastValues => saves.last;

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(_trigger.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EasyForm(
          triggerSave: _trigger.stream,
          onSave: (values, form) async => saves.add(values),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ));
  }

  Future<void> save(WidgetTester tester) async {
    _trigger.add(null);
    await tester.pumpAndSettle();
  }
}

/// Points `getApplicationDocumentsDirectory()` at a fresh temp dir.
Directory mockDocumentsDir() {
  final dir = Directory.systemTemp.createTempSync('widget_test_docs');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => dir.path,
  );
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Lets real (non-fake-async) work started by the widget finish.
///
/// Real IO and fake-async continuations only make progress when the two are
/// interleaved, so alternate between waiting and pumping. Fixed frames rather
/// than pumpAndSettle: some screens animate forever.
Future<void> settleIO(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
