// ignore_for_file: close_sinks

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quill_fb2/pages/book_page.dart';
import 'package:quill_fb2/pages/settings_page.dart';
import 'package:quill_fb2/services/app.service.dart';
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
    final xmlFileInfo = await widget.service.loadBook(project);
    if (xmlFileInfo == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }
    await Future.delayed(Duration(seconds: 1));
    try {
      final json = await widget.service.convertXmlToJson(xmlFileInfo.data);
      await Future.delayed(Duration(seconds: 1));
      final book = await widget.service.addProject(json, xmlFileInfo, project);
      if (book != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                BookPage(widget.service, book, changeController),
          ),
        ).then((value) => setState(() {}));
      }
    } catch (e) {
      print(e);
    }
    setState(() {
      isLoading = false;
    });
  }

  _loadFile() async {
    setState(() {
      isLoading = true;
    });
    final xmlFileInfo =
        await widget.service.openFile({'fb2': true, 'zip': true});
    if (xmlFileInfo == null) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No FB2 book found in the selected file')),
        );
      }
      return;
    }
    await Future.delayed(Duration(seconds: 1));
    try {
      final json = await widget.service.convertXmlToJson(xmlFileInfo.data);
      await Future.delayed(Duration(seconds: 1));
      final book = await widget.service.addProject(json, xmlFileInfo, null);
      if (book != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                BookPage(widget.service, book, changeController),
          ),
        ).then((value) => setState(() {}));
      }
    } catch (e) {
      print(e);
    }
    setState(() {
      isLoading = false;
    });
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
            .then((_) => setState(() {})));
    return Stack(children: [
      LibraryView(widget.service, actions),
      if (isLoading) ModalRoundedProgressBar(0.95, "Loading"),
    ]);
  }
}
