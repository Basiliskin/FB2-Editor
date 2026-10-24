import 'package:flutter/material.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';

class AnnotationData {
  String name;
  List<String> items;
  AnnotationData(this.name, this.items);
}

class AnnotationController extends EasyFormFieldController<AnnotationData?> {
  AnnotationController(AnnotationData? value) : super(value);
}

class AnnotationField extends EasyFormGenericField<AnnotationData?> {
  /// A mic (or anything else) to put beside the Add button.
  final Widget Function(TextEditingController)? dictation;

  AnnotationField({
    Key? key,
    @required AnnotationController? controller,
    ValueChanged<AnnotationData?>? onChange,
    this.dictation,
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

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < value!.items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(value!.items[i])),
            IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _removeLabel(i)),
          ]),
        ),
      if (value!.items.isNotEmpty) const Divider(),
      _AnnotationInput(value!.name, _addLabel, dictation),
    ]);
  }
}

class AnnotationFormField
    extends EasyCustomFormField<AnnotationData?, AnnotationController> {
  AnnotationFormField({
    Key? key,
    @required String? name,
    AnnotationController? controller,
    AnnotationData? initialValue,
    Widget Function(TextEditingController)? dictation,
  }) : super(
          key: key,
          name: (name as String),
          controller: controller,
          initialValue: initialValue,
          controllerBuilder: (value) => AnnotationController(value!),
          builder: (state, onChangedHandler) {
            return AnnotationField(
                controller: (state.controller as AnnotationController),
                onChange: onChangedHandler,
                dictation: dictation);
          },
        );
}

class _AnnotationInput extends StatefulWidget {
  final String hint;
  final Function(String) onAdd;
  final Widget Function(TextEditingController)? dictation;
  const _AnnotationInput(this.hint, this.onAdd, [this.dictation]);
  @override
  State<_AnnotationInput> createState() => _AnnotationInputState();
}

class _AnnotationInputState extends State<_AnnotationInput> {
  final c = TextEditingController();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            controller: c,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(hintText: widget.hint)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (widget.dictation != null) widget.dictation!(c),
          FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              onPressed: () {
                if (c.text.trim().isEmpty) return;
                widget.onAdd(c.text);
                c.clear();
              }),
        ]),
      ]);
}
