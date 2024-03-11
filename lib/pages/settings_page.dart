import 'package:flutter/material.dart';
import 'dart:async';

import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/forms/settings.form.dart';

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
    bool autoSave = settings["auto-save"] ?? false;
    print('settings.state = ${state.name} - autoSave=$autoSave');
    print(autoSave);
  }

  _build() {
    try {
      Map settings = widget.service.getSettings();
      return SafeArea(
        child: Column(children: <Widget>[
          Stack(children: [
            SettingsComponent(widget.service, settings,
                changeController!.stream.asBroadcastStream()),
          ]),
        ]),
      );
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text('Settings'),
          centerTitle: true,
        ),
        body: Padding(
          padding: EdgeInsets.all(16.0),
          child: _build(),
        ));
  }
}
