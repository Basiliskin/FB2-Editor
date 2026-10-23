import 'package:flutter/material.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/badge/src/badge.dart' as custom_badge;
import 'package:quill_fb2/widgets/badge/src/badge_shape.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';
import 'package:quill_fb2/prototype/prototype_switcher.dart'; // PROTOTYPE

typedef LabelDataChanged<LabelData> = void Function(LabelData value);

class LabelData {
  String name;
  List<String> items;
  LabelData(this.name, this.items);
}

class Label extends StatefulWidget {
  final String label;
  final Function(String) onTextSubmitted;
  Label(this.label, this.onTextSubmitted);
  @override
  _LabelState createState() => _LabelState();
}

class _LabelState extends State<Label> {
  TextEditingController editingController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  @override
  void dispose() {
    // Clean up the controller when the widget is disposed.
    editingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        child: RawKeyboardListener(
            // onKey: (RawKeyEvent event) => print('$event'),
            focusNode: _focusNode,
            child: TextField(
              onSubmitted: (text) => setState(() {
                widget.onTextSubmitted(text);
                editingController.text = "";
              }),
              decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: widget.label,
                  isDense: true, // Added this
                  contentPadding: EdgeInsets.all(8)), // Added this),
              controller: editingController,
            )));
  }
}

class LabelController extends EasyFormFieldController<LabelData?> {
  LabelController(LabelData? value) : super(value);
}

class LabelField extends EasyFormGenericField<LabelData?> {
  late LabelDataChanged<LabelData?>? _onUpdate;
  LabelField(
      {Key? key,
      @required LabelController? controller,
      ValueChanged<LabelData?>? onChange,
      LabelDataChanged<LabelData?>? onUpdate})
      : super(key: key, controller: controller!, onChange: onChange) {
    _onUpdate = onUpdate;
  }

  _addLabel(String labelName) {
    final items = value!.items
        .where((label) =>
            labelName.toLowerCase().compareTo(label.toLowerCase()) != 0)
        .toList()
      ..add(labelName);
    value = LabelData(value!.name, items);
    _onUpdate?.call(value);
  }

  _removeLabel(String labelName) {
    final items = value!.items
        .where((label) =>
            labelName.toLowerCase().compareTo(label.toLowerCase()) != 0)
        .toList();
    value = LabelData(value!.name, items);
    _onUpdate?.call(value);
  }

  Widget _content(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: value!.items.length,
              itemBuilder: (context, index) {
                final badge = custom_badge.Badge(
                    badgeColor:
                        index % 2 != 0 ? LABEL_ODD_COLOR : LABEL_EVEN_COLOR,
                    shape: BadgeShape.square,
                    borderRadius: 5,
                    toAnimate: false,
                    badgeContent: Text(
                        toBeginningOfSentenceCase(value!.items[index])!,
                        style: TextStyle(color: Colors.black)));

                return Row(children: <Widget>[
                  Padding(padding: EdgeInsets.only(right: 5.0)),
                  GestureDetector(
                      onTap: () => {_removeLabel(value!.items[index])},
                      child: badge)
                ]);
              }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Proto.modern) {
      // PROTOTYPE: chips + input; same add/remove behaviour
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (value!.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final item in value!.items)
                InputChip(
                    label: Text(toBeginningOfSentenceCase(item)!),
                    onDeleted: () => _removeLabel(item)),
            ]),
          ),
        Label(value!.name, _addLabel),
      ]);
    }
    return SingleChildScrollView(
        child: SafeArea(
            child: Container(
                margin: const EdgeInsets.all(3.0),
                padding: const EdgeInsets.all(3.0),
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.blueAccent)),
                child: Column(children: <Widget>[
                  Label(value!.name, _addLabel),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2.0)),
                  Container(width: 400, height: 40, child: _content(context))
                ]))));
  }
}

class LabelFormField extends EasyCustomFormField<LabelData?, LabelController> {
  LabelFormField(
      {Key? key,
      @required String? name,
      LabelController? controller,
      LabelData? initialValue,
      LabelDataChanged<LabelData?>? onUpdate})
      : super(
          key: key,
          name: (name as String),
          controller: controller,
          initialValue: initialValue,
          controllerBuilder: (value) => LabelController(value!),
          builder: (state, onChangedHandler) {
            return LabelField(
                controller: (state.controller as LabelController),
                onChange: onChangedHandler,
                onUpdate: onUpdate);
          },
        );
}
