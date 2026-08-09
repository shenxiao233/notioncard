import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<Uint8List?> loadOrFetchAvatar(String url) async {
  final normalized = url.trim();
  if (normalized.isEmpty) return null;

  try {
    final supportDirectory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory(
      path.join(supportDirectory.path, 'avatar-cache'),
    );
    if (!cacheDirectory.existsSync()) {
      await cacheDirectory.create(recursive: true);
    }

    final key = sha256.convert(utf8.encode(normalized)).toString();
    final file = File(path.join(cacheDirectory.path, '$key.bin'));
    if (await file.exists()) {
      final cached = await file.readAsBytes();
      if (cached.isNotEmpty) return Uint8List.fromList(cached);
      await file.delete();
    }

    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 8),
        responseType: ResponseType.bytes,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    ).get<List<int>>(normalized);
    final data = response.data;
    if (data == null || data.isEmpty) return null;

    final bytes = Uint8List.fromList(data);
    await file.writeAsBytes(bytes, flush: false);
    return bytes;
  } catch (_) {
    return null;
  }
}
