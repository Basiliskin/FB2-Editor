import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_fb2/models/project.model.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/ui/book_info.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';
import 'package:quill_fb2/widgets/forms/book_form.dart';

import '../support/form_harness.dart';

const _fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><genre>prose</genre>
<author><first-name>Ann</first-name><last-name>Lee</last-name></author>
<book-title>Sample</book-title><lang>en</lang></title-info>
<document-info><id>doc-1</id></document-info></description>
<body><title><p>Sample</p></title><section><title><p>Ch</p></title><p>Hi</p></section></body>
</FictionBook>''';

/// Cannot read its settings, which breaks building the form.
class _BrokenService extends AppService {
  @override
  getSettings() => throw StateError('no settings');

  @override
  translate(LangTranslateItems name) => name.name;
}

void main() {
  late ProjectModel book;
  late StreamController<void> trigger;

  setUp(() async {
    mockDocumentsDir();
    book = ProjectModel.fromJson(await AppService().convertXmlToJson(_fb2));
    trigger = StreamController<void>.broadcast();
    addTearDown(trigger.close);
  });

  Future<void> pump(WidgetTester tester, AppService service) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookComponent(service, book, trigger.stream))));
  }

  testWidgets('non-flat text fields render a bordered, validated input',
      (tester) async {
    await pump(tester, AppService());
    final kit = tester.widget<BookInfoLayout>(find.byType(BookInfoLayout)).k;
    final fk = GlobalKey<EasyFormState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EasyForm(
      key: fk,
      triggerSave: const Stream<void>.empty(),
      child: kit.text(LangTranslateItems.bookTitle, 'Hello',
          maxLines: 1, flat: false),
    ))));
    final decoration =
        tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(decoration.border, isA<OutlineInputBorder>());
    expect(decoration.filled, isTrue);
    expect(fk.currentState!.validate(), isTrue);
  });

  testWidgets('a failure while building the form shows the error message',
      (tester) async {
    await pump(tester, _BrokenService());
    expect(tester.takeException(), isNull);
    expect(find.text(LangTranslateItems.messageError.name), findsOneWidget);
  });
}
