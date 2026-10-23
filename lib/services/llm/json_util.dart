import 'dart:convert';

String encodeJson(Object o) => jsonEncode(o);
Map<String, dynamic> decodeJson(String s) =>
    jsonDecode(s) as Map<String, dynamic>;
