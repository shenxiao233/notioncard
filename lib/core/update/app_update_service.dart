import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';
import '../network/api_config.dart';
import '../network/api_exception.dart';
import 'app_update_model.dart';

class AppUpdateService {
  AppUpdateService({required this.apiClient, required this.apiConfig});

  static const _updateEndpoint = String.fromEnvironment(
    'KN_APP_UPDATE_URL',
    defaultValue: '/api/v1/app/update',
  );
  static const _channel = MethodChannel('kncard/update');

  final ApiClient apiClient;
  final ApiConfig apiConfig;

  Future<AppUpdateManifest?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    late final Response<dynamic> response;
    try {
      response = await apiClient.get(
        _updateEndpoint,
        options: Options(extra: const {'skipAuth': true}),
        queryParameters: {
          'platform': Platform.operatingSystem,
          'version': packageInfo.version,
          'build': packageInfo.buildNumber,
        },
      );
    } on ApiException catch (error) {
      // Older deployments did not expose the optional update manifest. Treat
      // that as "no update" so startup is not marked as a failed operation.
      if (error.statusCode == 404) return null;
      rethrow;
    }
    final manifest = parseManifest(response.data);
    if (manifest == null) return null;

    final currentBuild = int.tryParse(packageInfo.buildNumber);
    if (currentBuild != null && manifest.buildNumber <= currentBuild) {
      return null;
    }
    return manifest;
  }

  Future<File> downloadAndVerify(
    AppUpdateManifest manifest, {
    required void Function(int received, int total) onProgress,
  }) async {
    final downloadUrl = manifest.downloadUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw const AppUpdateException('更新包地址为空');
    }
    if (!manifest.hasSha256) {
      throw const AppUpdateException('更新包缺少有效的 SHA-256 校验值');
    }

    final directory = await getTemporaryDirectory();
    final file = File(
      path.join(directory.path, 'kncard-${manifest.buildNumber}.apk'),
    );
    if (await file.exists()) await file.delete();

    try {
      await apiClient.download(
        _absoluteUrl(downloadUrl).toString(),
        file.path,
        options: Options(extra: const {'skipAuth': true}),
        onReceiveProgress: onProgress,
      );
      final length = await file.length();
      if (manifest.sizeBytes != null && length != manifest.sizeBytes) {
        throw const AppUpdateException('更新包大小校验失败');
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != manifest.sha256!.toLowerCase()) {
        throw const AppUpdateException('更新包 SHA-256 校验失败');
      }
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> installAndroidApk(File file) async {
    if (!Platform.isAndroid) {
      throw const AppUpdateException('当前平台不支持直接安装 APK');
    }
    try {
      await _channel.invokeMethod<void>('installApk', {'path': file.path});
    } on PlatformException catch (error) {
      throw AppUpdateException(error.message ?? '无法启动系统安装器', code: error.code);
    }
  }

  Future<void> openAndroidInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Uri _absoluteUrl(String value) {
    final uri = Uri.tryParse(value);
    final resolved = uri != null && uri.hasScheme
        ? uri
        : apiConfig.endpoint(value);
    if ((resolved.scheme != 'http' && resolved.scheme != 'https') ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty ||
        resolved.fragment.isNotEmpty) {
      throw const AppUpdateException('更新包地址无效');
    }
    return resolved;
  }

  /// Parses the server response. Kept public so the response contract can be
  /// covered without relying on platform channels or a real HTTP server.
  AppUpdateManifest? parseManifest(dynamic data, {String? platform}) {
    if (data is! Map) return null;
    final root = Map<String, dynamic>.from(data);
    if (root['updateAvailable'] == false || root['available'] == false) {
      return null;
    }
    final nested = root['update'] ?? root['data'];
    final source = nested is Map ? Map<String, dynamic>.from(nested) : root;
    if (source['available'] == false || source['updateAvailable'] == false) {
      return null;
    }
    final platformDataValue = source[platform ?? Platform.operatingSystem];
    final platformData = platformDataValue is Map
        ? Map<String, dynamic>.from(platformDataValue)
        : const <String, dynamic>{};
    final artifact = source['artifact'] is Map
        ? Map<String, dynamic>.from(source['artifact'] as Map)
        : const <String, dynamic>{};
    final candidates = [source, artifact, platformData];
    final versionName = _firstString(candidates, [
      'versionName',
      'version',
      'latestVersion',
    ]);
    final buildNumber = _firstInt(candidates, [
      'buildNumber',
      'versionCode',
      'build',
      'latestBuild',
    ]);
    if (versionName == null || buildNumber == null || buildNumber <= 0) {
      return null;
    }

    final url = _firstString(candidates, ['downloadUrl', 'apkUrl', 'url']);
    final sha = _firstString(candidates, ['sha256', 'sha-256', 'checksum']);
    final size = _firstInt(candidates, ['sizeBytes', 'size']);
    final patchValue = source['patch'] ?? artifact['patch'];
    final patch = patchValue is Map
        ? Map<String, dynamic>.from(patchValue)
        : const <String, dynamic>{};
    return AppUpdateManifest(
      versionName: versionName,
      buildNumber: buildNumber,
      notes:
          _firstString(candidates, ['notes', 'releaseNotes', 'changelog']) ??
          '',
      downloadUrl: url,
      sha256: sha,
      sizeBytes: size,
      mandatory: _firstBool(candidates, ['mandatory', 'forceUpdate']) ?? false,
      releaseUrl: _firstString(candidates, ['releaseUrl', 'website']),
      iosStoreUrl: _firstString(candidates, ['iosStoreUrl', 'appStoreUrl']),
      patchUrl: _string(patch, ['url', 'downloadUrl']),
      patchSha256: _string(patch, ['sha256', 'sha-256', 'checksum']),
      patchSizeBytes: _int(patch, ['sizeBytes', 'size']),
      patchFromBuildNumber: _int(patch, ['fromBuildNumber', 'fromBuild']),
    );
  }

  String? _string(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _firstString(List<Map<String, dynamic>> sources, List<String> keys) {
    for (final source in sources) {
      final value = _string(source, keys);
      if (value != null) return value;
    }
    return null;
  }

  int? _int(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse('$value');
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _firstInt(List<Map<String, dynamic>> sources, List<String> keys) {
    for (final source in sources) {
      final value = _int(source, keys);
      if (value != null) return value;
    }
    return null;
  }

  bool? _firstBool(List<Map<String, dynamic>> sources, List<String> keys) {
    for (final source in sources) {
      for (final key in keys) {
        final value = source[key];
        if (value is bool) return value;
        if (value is String) {
          if (value.toLowerCase() == 'true') return true;
          if (value.toLowerCase() == 'false') return false;
        }
      }
    }
    return null;
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
