import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/network/api_client.dart';
import 'package:kncard_app/core/network/api_config.dart';
import 'package:kncard_app/core/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('updates nickname and persists the returned profile', () async {
    SharedPreferences.setMockInitialValues({
      'auth.account': jsonEncode({
        'id': 'account-1',
        'username': 'learner',
        'nickname': '旧昵称',
        'status': 'ACTIVE',
        'avatar': 'https://example.com/old.png',
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final adapter = _QueueAdapter([
      _FakeResponse.json({
        'profile': {
          'id': 'account-1',
          'username': 'learner',
          'nickname': '新昵称',
          'avatar': 'https://example.com/new.png',
          'status': 'ACTIVE',
        },
      }),
    ]);
    final repository = AuthRepository(preferences, apiClient: _client(adapter));

    final result = await repository.updateProfile(nickname: '新昵称');

    expect(result.isSuccess, isTrue);
    expect(result.account?.nickname, '新昵称');
    expect(result.account?.avatar, 'https://example.com/new.png');
    expect(adapter.requests.single.method, 'PATCH');
    expect(adapter.requests.single.path, '/api/v2/me/profile');
    expect(adapter.requests.single.data, {'nickname': '新昵称'});
    expect(repository.currentAccount?.nickname, '新昵称');
  });

  test('sends a cleared avatar only when the avatar was changed', () async {
    SharedPreferences.setMockInitialValues({
      'auth.account': jsonEncode({
        'id': 'account-1',
        'username': 'learner',
        'nickname': '昵称',
        'status': 'ACTIVE',
        'avatar': 'https://example.com/avatar.png',
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final adapter = _QueueAdapter([_FakeResponse.json({})]);
    final repository = AuthRepository(preferences, apiClient: _client(adapter));

    final result = await repository.updateProfile(
      nickname: '昵称',
      avatar: null,
      updateAvatar: true,
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.requests.single.data, {'nickname': '昵称', 'avatar': null});
    expect(repository.currentAccount?.avatar, isNull);
  });
}

ApiClient _client(_QueueAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://test.invalid'),
    tokenReader: () async => 'test-token',
    dio: dio,
  );
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);

  final List<_FakeResponse> responses;
  final requests = <RequestOptions>[];
  var _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responses[_index++].toBody();
  }

  @override
  void close({bool force = false}) {}
}

class _FakeResponse {
  const _FakeResponse(this.body);

  factory _FakeResponse.json(Map<String, dynamic> body) =>
      _FakeResponse(jsonEncode(body));

  final String body;

  ResponseBody toBody() => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
