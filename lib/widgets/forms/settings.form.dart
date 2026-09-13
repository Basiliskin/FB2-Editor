import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';

const Map<String, dynamic> defaultMap = {};

class SettingsComponent extends StatefulWidget {
  final AppService service;
  final Stream<void>? triggerSave;
  final Map setting;
  SettingsComponent(this.service, this.setting, this.triggerSave);
  @override
  _SettingsComponentState createState() => _SettingsComponentState();
}

class _SettingsComponentState extends State<SettingsComponent> {
  bool isLoading = false;
  bool _autoSave = false;
  bool _showImage = false;
  int _fontSize = 12;
  int _imageQuality = 100;
  int _imageWidth = 1024;
  String _language = 'eng';
  @override
  void initState() {
    super.initState();
    _autoSave = stringToBool(widget.setting["auto-save"]) ?? _autoSave;
    _fontSize = stringToInt(widget.setting["font-size"]) ?? _fontSize;
    _language = widget.setting["language"] ?? _language;
    _showImage = stringToBool(widget.setting["show-image"]) ?? _showImage;
    _imageWidth = stringToInt(widget.setting["image-width"]) ?? _imageWidth;
    _imageQuality =
        stringToInt(widget.setting["image-quality"]) ?? _imageQuality;
  }

  Future<dynamic> _save(Map<String, dynamic> values, EasyFormState form) async {
    setState(() {
      isLoading = true;
    });
    // widget.book.updateInfo(values);
    // await widget.service.saveProject(widget.book);
    final snackBar = SnackBar(
        content:
            Text(widget.service.translate(LangTranslateItems.settingsSaved)));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    setState(() {
      isLoading = false;
    });
  }

  _saved(
      dynamic response, Map<String, dynamic> fieldValues, EasyFormState form) {
    print(response);
  }

  _saveSettings() async {
    setState(() {
      isLoading = true;
    });
    await widget.service.setSettings({
      "auto-save": _autoSave,
      "show-image": _showImage,
      "font-size": _fontSize,
      "image-quality": _imageQuality,
      "language": _language,
      "image-width": _imageWidth
    });
    widget.service.setLanguage(_language);
    final snackBar = SnackBar(
        content:
            Text(widget.service.translate(LangTranslateItems.settingsSaved)));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    setState(() {
      isLoading = false;
    });
  }

  _log(message) {
    final snackBar = SnackBar(content: Text(message));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  _build() {
    try {
      return SafeArea(
          child: Container(
              margin: const EdgeInsets.all(13.0),
              padding: const EdgeInsets.all(15.0),
              decoration:
                  BoxDecoration(border: Border.all(color: Colors.blueAccent)),
              child: Column(children: <Widget>[
                Row(
                  children: [
                    Expanded(
                        child: Column(children: <Widget>[
                      Row(children: [
                        Switch(
                          value: _autoSave,
                          onChanged: (value) {
                            setState(() {
                              _autoSave = value;
                              print(_autoSave);
                            });
                          },
                          activeTrackColor: Colors.lightGreenAccent,
                          activeColor: Colors.green,
                        ),
                        Text(widget.service
                            .translate(LangTranslateItems.autoSave))
                      ])
                    ]))
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: Column(children: <Widget>[
                      Row(children: [
                        Switch(
                          value: _showImage,
                          onChanged: (value) {
                            setState(() {
                              _showImage = value;
                              print(_showImage);
                            });
                          },
                          activeTrackColor: Colors.lightGreenAccent,
                          activeColor: Colors.green,
                        ),
                        Text(widget.service
                            .translate(LangTranslateItems.buttonShowPageImage))
                      ])
                    ]))
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: Column(children: <Widget>[
                      Row(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 0, 0)),
                        DropdownButton(
                          value: _imageWidth,
                          onChanged: (newValue) {
                            setState(() {
                              _imageWidth = newValue! as int;
                            });
                          },
                          items: [600, 800, 1024].map((num) {
                            return new DropdownMenuItem(
                              child: new Text("$num"),
                              value: num,
                            );
                          }).toList(),
                        ),
                        Text(widget.service
                            .translate(LangTranslateItems.imageSize))
                      ])
                    ]))
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: Column(children: <Widget>[
                      Row(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 0, 0)),
                        DropdownButton(
                          value: _fontSize,
                          onChanged: (newValue) {
                            setState(() {
                              _fontSize = newValue! as int;
                            });
                          },
                          items: [12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
                              .map((num) {
                            return new DropdownMenuItem(
                              child: new Text("$num"),
                              value: num,
                            );
                          }).toList(),
                        ),
                        Text(widget.service
                            .translate(LangTranslateItems.fontSize))
                      ])
                    ]))
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: Column(children: <Widget>[
                      Row(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 0, 0)),
                        DropdownButton(
                          value: _imageQuality,
                          onChanged: (newValue) {
                            setState(() {
                              _imageQuality = newValue! as int;
                            });
                          },
                          items: [50, 75, 90, 100].map((num) {
                            return new DropdownMenuItem(
                              child: new Text("$num"),
                              value: num,
                            );
                          }).toList(),
                        ),
                        Text(widget.service
                            .translate(LangTranslateItems.imageQuality))
                      ])
                    ]))
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: Column(children: <Widget>[
                      Row(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 0, 0)),
                        DropdownButton(
                          value: _language,
                          onChanged: (newValue) {
                            setState(() {
                              _language = newValue! as String;
                            });
                          },
                          items: ["eng", "ru"].map((num) {
                            return new DropdownMenuItem(
                              child: new Text(LANGUAGES[num]!),
                              value: num,
                            );
                          }).toList(),
                        ),
                        Text(widget.service
                            .translate(LangTranslateItems.titleLanguage))
                      ])
                    ]))
                  ],
                )
              ])));
    } catch (e) {
      _log(e.toString());
      return Text(widget.service.translate(LangTranslateItems.messageError));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ModalRoundedProgressBar progressBar =
        ModalRoundedProgressBar(0.95, "Loading");
    List<Widget> stackItems = [];

    stackItems.add(EasyForm(
        onSave: _save,
        onSaved: _saved,
        child: _build(),
        triggerSave: widget.triggerSave,
        rebuildOnChange: false));
    if (isLoading) stackItems.add(progressBar);
    stackItems.add(Align(
        alignment: Alignment.bottomRight,
        child: Container(
            width: 40.0,
            height: 40.0,
            child: FloatingActionButton(
              heroTag: 'btnSaveSettings',
              backgroundColor: Colors.red,
              onPressed: () async {
                _saveSettings();
              },
              child: Icon(Icons.save),
              shape: BeveledRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ))));
    return Stack(
      children: stackItems,
    );
  }
}
