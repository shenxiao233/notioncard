import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/core/network/api_client.dart';
import 'package:kncard_app/core/network/api_config.dart';
import 'package:kncard_app/core/update/app_update_service.dart';

void main() {
  late AppUpdateService service;

  setUp(() {
    service = AppUpdateService(
      apiClient: ApiClient(
        config: const ApiConfig(baseUrl: 'https://api.example.com'),
        tokenReader: () async => null,
      ),
      apiConfig: const ApiConfig(baseUrl: 'https://api.example.com'),
    );
  });

  test('returns null for an explicit no-update response', () {
    expect(service.parseManifest({'available': false}), isNull);
  });

  test('parses a nested Android artifact and patch metadata', () {
    final manifest = service.parseManifest({
      'data': {
        'available': true,
        'version': '1.2.0',
        'android': {
          'versionCode': 12,
          'url': 'https://cdn.example.com/kncard.apk',
          'sha256': 'a' * 64,
          'size': 1234,
        },
        'patch': {
          'url': 'https://cdn.example.com/kncard.patch',
          'fromBuildNumber': 11,
        },
      },
    }, platform: 'android');

    expect(manifest, isNotNull);
    expect(manifest!.versionName, '1.2.0');
    expect(manifest.buildNumber, 12);
    expect(manifest.downloadUrl, 'https://cdn.example.com/kncard.apk');
    expect(manifest.sha256, 'a' * 64);
    expect(manifest.sizeBytes, 1234);
    expect(manifest.canDownload, isTrue);
    expect(manifest.patchFromBuildNumber, 11);
  });

  test('parses forceUpdate and accepts numeric strings', () {
    final manifest = service.parseManifest({
      'available': true,
      'versionName': '2.0.0',
      'buildNumber': '20',
      'forceUpdate': 'true',
      'downloadUrl': '/releases/kncard.apk',
      'sha256': 'b' * 64,
    }, platform: 'android');

    expect(manifest, isNotNull);
    expect(manifest!.buildNumber, 20);
    expect(manifest.mandatory, isTrue);
    expect(manifest.canDownload, isTrue);
  });

  test('does not permit an update without a valid SHA-256', () {
    final manifest = service.parseManifest({
      'available': true,
      'versionName': '1.1.0',
      'buildNumber': 2,
      'downloadUrl': 'https://cdn.example.com/kncard.apk',
      'sha256': 'not-a-digest',
    }, platform: 'android');

    expect(manifest, isNotNull);
    expect(manifest!.hasDownload, isTrue);
    expect(manifest.canDownload, isFalse);
  });

  test('rejects a manifest with missing or invalid build number', () {
    expect(
      service.parseManifest({
        'available': true,
        'versionName': '1.1.0',
        'downloadUrl': 'https://cdn.example.com/kncard.apk',
      }, platform: 'android'),
      isNull,
    );
    expect(
      service.parseManifest({
        'available': true,
        'versionName': '1.1.0',
        'buildNumber': 0,
      }, platform: 'android'),
      isNull,
    );
  });
}
