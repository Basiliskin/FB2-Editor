import 'package:flutter/material.dart';
import 'package:quill_fb2/routes.dart';
import 'dart:async';

import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';

class StartScreen extends StatefulWidget {
  final AppService service;
  StartScreen(this.service);
  @override
  _StartScreenState createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool isLoading = true;
  Timer? _timer;
  Future<Null> _loadUserData() async {
    try {
      await widget.service.init();

      Navigator.pushReplacementNamed(context, Routes.screenHome);
    } catch (e) {
      _log(e.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    startTime();
  }

  @override
  void reassemble() {
    super.reassemble();
    startTime();
  }

  _log(message) {
    final snackBar = SnackBar(content: Text(message));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  startTime() async {
    try {
      var duration = new Duration(seconds: 1);
      _timer?.cancel();
      _timer = Timer(duration, _loadUserData);
    } catch (e) {
      _log(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ModalRoundedProgressBar progressBar =
        ModalRoundedProgressBar(0.95, "Initializing");

    return Scaffold(
        body: Stack(
      children: <Widget>[
        // Loading
        Positioned(
            child: Container(
          child: Center(
            child: progressBar,
          ),
          color: Colors.white.withOpacity(0.8),
        )),
      ],
    ));
  }
}
