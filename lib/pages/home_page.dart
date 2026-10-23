// ignore_for_file: close_sinks

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quill_fb2/pages/book_page.dart';
import 'package:quill_fb2/pages/help_page.dart';
import 'package:quill_fb2/pages/settings_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/services/open_failure.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';
import 'package:intl/intl.dart';
import 'package:quill_fb2/ui/library_view.dart';

class HomeScreen extends StatefulWidget {
  final AppService service;
  HomeScreen(this.service);
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool isLoading = false;
  StreamController<void>? changeController;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    changeController!.close();
    super.dispose();
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    changeController = StreamController<void>.broadcast();
    super.initState();
    changeController!.stream.asBroadcastStream().listen((event) {
      try {
        print('HomeScreen.update history list');
      } catch (e) {
        print(e);
      }
    });
  }

  @override
  void reassemble() {
    super.reassemble();
  }

  _openProject(Map project) async {
    setState(() {
      isLoading = true;
    });
    try {
      final info = await widget.service.loadBook(project);
      if (info != null) await _showBook(info, project);
    } catch (e) {
      _reportOpenError(e);
    }
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  _loadFile() async {
    setState(() {
      isLoading = true;
    });
    try {
      // null means the user cancelled the picker
      final info = await widget.service.openFile({'fb2': true, 'zip': true});
      if (info != null) await _showBook(info, null);
    } catch (e) {
      _reportOpenError(e);
    }
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  _showBook(FileInfo info, Map? project) async {
    final json = await widget.service.convertXmlToJson(info.data);
    final book = await widget.service.addProject(json, info, project);
    if (book != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookPage(widget.service, book, changeController),
        ),
      ).then((value) => setState(() {}));
    }
  }

  /// Tells the user why the file could not be opened.
  _reportOpenError(Object error) {
    print(error);
    if (!mounted) return;
    final item = switch (error is OpenFailure ? error.kind : OpenFailureKind.unreadable) {
      OpenFailureKind.unsupportedType => LangTranslateItems.openErrorUnsupported,
      OpenFailureKind.unreadable => LangTranslateItems.openErrorUnreadable,
      OpenFailureKind.noFb2InZip => LangTranslateItems.openErrorNoFb2InZip,
      OpenFailureKind.notFb2 => LangTranslateItems.openErrorNotFb2,
      OpenFailureKind.timeout => LangTranslateItems.openErrorTimeout,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.service.translate(item)}')),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Map settings = widget.service.getSettings();
    bool autoSave = stringToBool(settings["auto-save"]) ?? false;
    print('page.state = ${state.name} - autoSave=$autoSave');
    print(autoSave);
  }

  @override
  Widget build(BuildContext context) {
    final actions = HomeActions(
        () async => await _loadFile(),
        (b) async => await _openProject(b),
        (b) async {
          await widget.service.removeProject(b);
          setState(() {});
        },
        () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => SettingsScreen(widget.service)))
            .then((_) => setState(() {})),
        openHelp: () => openHelp(context, widget.service));
    return Stack(children: [
      LibraryView(widget.service, actions),
      if (isLoading) ModalRoundedProgressBar(0.95, "Loading"),
    ]);
  }
}
