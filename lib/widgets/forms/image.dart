import 'dart:convert';
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
  final double coverWidth;
  ImageField(
      {Key? key,
      @required ImageController? controller,
      ValueChanged<String?>? onChange,
      int? width,
      int? quality,
      this.coverWidth = 110})
      : super(
          key: key,
          controller: controller!,
          onChange: onChange,
        ) {
    this._width = width ?? _width;
    this._quality = quality ?? _quality;
  }

  _change() async {
    print("Before ${value!.length}");
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      print(pickedFile.path);
      List<int> imageBytes = await readFileByte(pickedFile.path);

      final resized = await resizeImageBytes(imageBytes, _width, _quality);
      // At 100 quality resizeImageBytes returns the original bytes untouched.
      value = resized is String ? resized : base64Encode(resized);
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

  _buildBody(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(children: [
      Stack(children: [
        GestureDetector(
            onTap: _change,
            child: Container(
              width: coverWidth,
              height: coverWidth * 1.45,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.outlineVariant),
                  image: DecorationImage(
                      fit: BoxFit.cover, image: base64Image(value, true))),
            )),
        Positioned(
            right: 4,
            top: 4,
            child: IconButton.filledTonal(
                tooltip: 'Remove cover',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => value = '')),
      ]),
      TextButton.icon(
          onPressed: _change,
          icon: const Icon(Icons.image_outlined, size: 16),
          label: const Text('Change')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody(context);
  }
}

class ImageFormField extends EasyCustomFormField<String?, ImageController> {
  ImageFormField(
      {Key? key,
      @required String? name,
      ImageController? controller,
      String? initialValue,
      int? width,
      int? quality,
      double coverWidth = 110})
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
              coverWidth: coverWidth,
            );
          },
        );
}
