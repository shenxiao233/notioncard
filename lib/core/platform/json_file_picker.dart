import 'dart:convert';

import 'package:flutter/services.dart';

class PickedJsonFile {
  const PickedJsonFile({required this.name, required this.content});

  final String name;
  final String content;
}

const _channel = MethodChannel('kncard/files');

Future<PickedJsonFile?> pickJsonFile() async {
  final response = await _channel.invokeMethod<dynamic>('pickJsonFile');
  if (response == null) return null;
  if (response is! Map) {
    throw const FormatException('系统文件选择器返回了无效结果');
  }

  final name = '${response['name'] ?? 'import.json'}'.trim();
  final encoded = '${response['contentBase64'] ?? ''}';
  if (encoded.isEmpty) throw const FormatException('选择的文件内容为空');
  try {
    return PickedJsonFile(
      name: name.isEmpty ? 'import.json' : name,
      content: utf8.decode(base64Decode(encoded), allowMalformed: true),
    );
  } catch (error) {
    throw FormatException('无法读取 JSON 文件：$error');
  }
}
