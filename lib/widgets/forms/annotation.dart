import 'package:flutter/material.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';

class AnnotationData {
  String name;
  List<String> items;
  AnnotationData(this.name, this.items);
}

class Annotation extends StatefulWidget {
  final String label;
  final Function(String) onTextSubmitted;
  Annotation(this.label, this.onTextSubmitted);
  @override
  _AnnotationState createState() => _AnnotationState();
}

class _AnnotationState extends State<Annotation> {
  final maxLines = 3;
  TextEditingController editingController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  @override
  void dispose() {
    // Clean up the controller when the widget is disposed.
    editingController.dispose();
    super.dispose();
  }

  _input() {
    return Material(
        child: TextField(
      focusNode: _focusNode,
      expands: false,
      textInputAction: TextInputAction.newline,
      keyboardType: TextInputType.multiline,
      maxLines: maxLines,
      onSubmitted: (text) => setState(() {
        widget.onTextSubmitted(text);
        editingController.text = "";
        editingController.clear();
      }),
      decoration: InputDecoration(
          border: OutlineInputBorder(),
          hintText: widget.label,
          isDense: true, // Added this
          contentPadding: EdgeInsets.all(8)), // Added this),
      controller: editingController,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(2),
      height: 124,
      child: Column(
        children: [
          _input(),
          ElevatedButton(
            child: Icon(Icons.save),
            onPressed: () {
              widget.onTextSubmitted(editingController.text);
              editingController.text = "";
            },
          )
        ],
      ),
    );
  }
}

class AnnotationController extends EasyFormFieldController<AnnotationData?> {
  AnnotationController(AnnotationData? value) : super(value);
}

class AnnotationField extends EasyFormGenericField<AnnotationData?> {
  AnnotationField({
    Key? key,
    @required AnnotationController? controller,
    ValueChanged<AnnotationData?>? onChange,
  }) : super(
            key: key,
            controller:
                (controller as EasyFormFieldController<AnnotationData?>),
            onChange: onChange);

  _addLabel(String labelName) {
    final items = value!.items
        .where((label) =>
            labelName.toLowerCase().compareTo(label.toLowerCase()) != 0)
        .toList()
      ..add(labelName);
    value = AnnotationData(value!.name, items);
  }

  _removeLabel(int index) {
    final items = [...value!.items];
    items.removeAt(index);
    value = AnnotationData(value!.name, items);
  }

  Widget _content(BuildContext context) {
    return Container(
        margin: EdgeInsets.all(2),
        height: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: value!.items.length,
                  itemBuilder: (context, index) {
                    return Column(children: <Widget>[
                      Stack(
                        children: [
                          Text(value!.items[index],
                              overflow: TextOverflow.clip),
                          Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                  width: 32.0,
                                  height: 32.0,
                                  child: FloatingActionButton(
                                    heroTag: 'annotation_$index',
                                    onPressed: () {
                                      _removeLabel(index);
                                    },
                                    child: Icon(Icons.delete),
                                    shape: BeveledRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  )))
                        ],
                      )
                    ]);
                  }),
            ),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        child: SafeArea(
            child: Container(
                margin: const EdgeInsets.all(3.0),
                padding: const EdgeInsets.all(3.0),
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.blueAccent)),
                child: Column(children: <Widget>[
                  Annotation(value!.name, _addLabel),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2.0)),
                  Container(child: _content(context))
                ]))));
  }
}

class AnnotationFormField
    extends EasyCustomFormField<AnnotationData?, AnnotationController> {
  AnnotationFormField({
    Key? key,
    @required String? name,
    AnnotationController? controller,
    AnnotationData? initialValue,
  }) : super(
          key: key,
          name: (name as String),
          controller: controller,
          initialValue: initialValue,
          controllerBuilder: (value) => AnnotationController(value!),
          builder: (state, onChangedHandler) {
            return AnnotationField(
                controller: (state.controller as AnnotationController),
                onChange: onChangedHandler);
          },
        );
}
