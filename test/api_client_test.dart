import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kncard_app/core/network/api_client.dart';
import 'package:kncard_app/core/network/api_config.dart';

void main() {
  test(
    'warmup shares an in-flight request and reuses a fresh result',
    () async {
      final adapter = _WarmupAdapter();
      final client = _buildClient(adapter);

      final first = client.warmup();
      final second = client.warmup();
      expect(identical(first, second), isTrue);

      try {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(adapter.requests, hasLength(1));
      } finally {
        adapter.releaseFirstRequest();
      }
      await first;
      await client.warmup();
      expect(adapter.requests, hasLength(1));
    },
  );

  test('force warmup bypasses the successful warmup ttl', () async {
    final adapter = _WarmupAdapter();
    final client = _buildClient(adapter);

    adapter.releaseFirstRequest();
    await client.warmup();
    await client.warmup(force: true);

    expect(adapter.requests, hasLength(2));
  });
}

ApiClient _buildClient(_WarmupAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://test.invalid'),
    tokenReader: () async => null,
    dio: dio,
  );
}

class _WarmupAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final _firstRequestGate = Completer<void>();
  var _isFirstRequest = true;

  void releaseFirstRequest() {
    if (!_firstRequestGate.isCompleted) _firstRequestGate.complete();
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_isFirstRequest) {
      _isFirstRequest = false;
      await _firstRequestGate.future;
    }
    return ResponseBody.fromString(
      jsonEncode({'status': 'ok'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
