import 'package:flutter/material.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/wave.progress.dart';

class ModalRoundedProgressBar extends StatelessWidget {
  final double opacity;
  final String textMessage;
  ModalRoundedProgressBar(this.opacity, this.textMessage);
  @override
  Widget build(BuildContext context) {
    return Container(child: buildContent(context));
  }

  Widget buildContent(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: <Widget>[
          Opacity(
            opacity: opacity,
            //ModalBarried used to make a modal effect on screen
            child: ModalBarrier(
              dismissible: false,
              color: Colors.black54,
            ),
          ),
          Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                WaveProgress(180.0, PROGRESSBAR_COLOR, PROGRESSBAR_COLOR, 40.0),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Text(textMessage),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// handler class
class ProgressBarHandler {
  late Function show; //show is the name of member..can be what you want...
  late Function dismiss;
}

class Dialogs {
  static Future<void> showLoadingDialog(
      BuildContext context, GlobalKey key) async {
    return showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return new WillPopScope(
              onWillPop: () async => false,
              child: SimpleDialog(
                  key: key,
                  backgroundColor: Colors.black54,
                  children: <Widget>[
                    Center(
                      child: Column(children: [
                        CircularProgressIndicator(),
                        SizedBox(
                          height: 10,
                        ),
                        Text(
                          "Please Wait....",
                          style: TextStyle(color: BUTTON_COLOR),
                        )
                      ]),
                    )
                  ]));
        });
  }
}
