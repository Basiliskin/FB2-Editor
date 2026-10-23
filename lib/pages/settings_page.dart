import 'package:flutter/material.dart';
import 'dart:async';

import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/forms/settings.form.dart';
import 'package:quill_fb2/ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  final AppService service;

  SettingsScreen(this.service);
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final GlobalKey _scaffoldKey = GlobalKey();
  StreamController<void>? changeController;
  @override
  void dispose() {
    changeController!.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    changeController = StreamController<void>.broadcast();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void reassemble() {
    changeController!.close();
    super.reassemble();
  }

  // _log(message) {
  //   final snackBar = SnackBar(content: Text(message));
  //   ScaffoldMessenger.of(context).showSnackBar(snackBar);
  // }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Map settings = widget.service.getSettings();
    final raw = settings["auto-save"];
    bool autoSave = raw == true || raw == 'true';
    print('settings.state = ${state.name} - autoSave=$autoSave');
    print(autoSave);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        key: _scaffoldKey,
        appBar: appBarFor(context,
            title: Text(tr(widget.service, 'Settings', 'Настройки'))),
        body: SettingsComponent(widget.service, widget.service.getSettings(),
            changeController!.stream.asBroadcastStream()));
  }
}
