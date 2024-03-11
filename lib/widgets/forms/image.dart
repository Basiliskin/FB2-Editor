import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quill_fb2/widgets/easy_form_kit/easy_form_kit.dart';

class ImageController extends EasyFormFieldController<String> {
  ImageController(String value) : super(value);
}

class ImageField extends EasyFormGenericField<String> {
  final picker = ImagePicker();
  int? _width = 600;
  int? _quality = 75;
  ImageField(
      {Key? key,
      @required ImageController? controller,
      ValueChanged<String?>? onChange,
      int? width,
      int? quality})
      : super(
          key: key,
          controller: controller!,
          onChange: onChange,
        ) {
    this._width = width;
    this._quality = _quality;
  }

  _change() async {
    print("Before ${value!.length}");
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      print(pickedFile.path);
      List<int> imageBytes = await readFileByte(pickedFile.path);

      value = await resizeImageBytes(imageBytes, _width, _quality);
    } else {
      print('No image selected.');
    }
    print("After ${value!.length}");
  }

  base64Image(base64, provider) {
    if (base64 != "")
      try {
        Uint8List _image = decode64Image(base64);
        final img = provider
            ? MemoryImage(_image)
            : Image.memory(_image,
                gaplessPlayback: true); // assign it value here
        return img;
      } catch (e) {
        print(e);
      }
    return provider ? AssetImage(DEFAULT_IMAGE) : Image.asset(DEFAULT_IMAGE);
  }

  _image() {
    return GestureDetector(
        onTap: _change,
        child: Container(
          width: 100.0,
          height: 160.0,
          decoration: new BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.all(Radius.circular(10)),
              border: Border.all(
                  color: Colors.teal, width: 2.0, style: BorderStyle.solid),
              image: new DecorationImage(
                  fit: BoxFit.cover, image: base64Image(value, true))),
        ));
  }

  _build() {
    return Stack(
      children: [
        _image(),
        Align(
            alignment: Alignment.topRight,
            child: Container(
                width: 32.0,
                height: 32.0,
                child: FloatingActionButton(
                  heroTag: 'imageBtn',
                  onPressed: () {
                    print('Remove');
                    value = '';
                  },
                  child: Icon(Icons.delete),
                  shape: BeveledRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                )))
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _build();
  }
}

class ImageFormField extends EasyCustomFormField<String?, ImageController> {
  ImageFormField(
      {Key? key,
      @required String? name,
      ImageController? controller,
      String? initialValue,
      int? width,
      int? quality})
      : super(
          key: key,
          name: (name as String),
          controller: controller,
          initialValue: initialValue ?? '',
          controllerBuilder: (value) => ImageController(value!),
          builder: (state, onChangedHandler) {
            return ImageField(
              controller: (state.controller as ImageController),
              onChange: onChangedHandler,
              width: width,
              quality: quality,
            );
          },
        );
}
