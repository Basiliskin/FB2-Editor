import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';
import 'package:quill_fb2/ui/widgets.dart';

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

  Widget _dd<T>(String label, T value, List<T> opts, void Function(T) on,
          {IconData? icon, String Function(T)? show}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: icon == null ? null : Icon(icon),
        title: Text(label),
        trailing: DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          items: [
            for (final o in opts)
              DropdownMenuItem<T>(value: o, child: Text(show != null ? show(o) : '$o'))
          ],
          onChanged: (v) => setState(() => on(v as T)),
        ),
      );

  Widget _buildBody() {
    final s = widget.service;
    return PageBody(
        max: 600,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
          SettingsGroup(tr(s, 'Editing', 'Редактирование'), icon: Icons.edit_outlined, [
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.translate(LangTranslateItems.autoSave)),
                value: _autoSave,
                onChanged: (v) => setState(() => _autoSave = v)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.translate(LangTranslateItems.buttonShowPageImage)),
                value: _showImage,
                onChanged: (v) => setState(() => _showImage = v)),
            _dd<int>(s.translate(LangTranslateItems.fontSize), _fontSize,
                [12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32], (v) => _fontSize = v,
                icon: Icons.format_size),
          ]),
          SettingsGroup(tr(s, 'Images', 'Изображения'), icon: Icons.image_outlined, [
            _dd<int>(s.translate(LangTranslateItems.imageSize), _imageWidth,
                [600, 800, 1024], (v) => _imageWidth = v),
            _dd<int>(s.translate(LangTranslateItems.imageQuality), _imageQuality,
                [50, 75, 90, 100], (v) => _imageQuality = v),
          ]),
          SettingsGroup(s.translate(LangTranslateItems.titleLanguage), icon: Icons.language, [
            _dd<String>(s.translate(LangTranslateItems.titleLanguage), _language,
                ["eng", "ru"], (v) => _language = v, show: (k) => LANGUAGES[k]!),
          ]),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final ModalRoundedProgressBar progressBar =
        ModalRoundedProgressBar(0.95, "Loading");
    List<Widget> stackItems = [];

    stackItems.add(EasyForm(
        onSave: _save,
        onSaved: _saved,
        child: _buildBody(),
        triggerSave: widget.triggerSave,
        rebuildOnChange: false));
    if (isLoading) stackItems.add(progressBar);
    stackItems.add(Positioned(
        right: 16,
        bottom: 72,
        child: FloatingActionButton.extended(
          heroTag: 'btnSaveSettings',
          icon: const Icon(Icons.save_outlined),
          label: Text(widget.service.translate(LangTranslateItems.buttonSave)),
          onPressed: () async {
            _saveSettings();
          },
        )));
    return Stack(children: stackItems);
  }
}
