import 'dart:async';

import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';

typedef TokenReader = Future<String?> Function();
typedef RefreshTokenReader = Future<String?> Function();
typedef TokenPairWriter =
    Future<void> Function(String accessToken, String refreshToken);
typedef UnauthorizedHandler = Future<void> Function();

enum RefreshOutcome { refreshed, invalid, unavailable }

class ApiClient {
  static const warmupTtl = Duration(seconds: 60);

  ApiClient({
    required ApiConfig config,
    required this.tokenReader,
    this.refreshTokenReader,
    this.onTokensRefreshed,
    this.onUnauthorized,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final skipAuth = options.extra['skipAuth'] == true;
          if (!skipAuth) {
            final token = await tokenReader();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final skipAuth = error.requestOptions.extra['skipAuth'] == true;
          final alreadyRetried =
              error.requestOptions.extra['authRetry'] == true;
          if (!skipAuth &&
              !alreadyRetried &&
              error.response?.statusCode == 401) {
            final outcome = await _refreshSingleFlight();
            if (outcome == RefreshOutcome.refreshed) {
              try {
                error.requestOptions.extra['authRetry'] = true;
                final token = await tokenReader();
                if (token != null && token.isNotEmpty) {
                  error.requestOptions.headers['Authorization'] =
                      'Bearer $token';
                }
                final response = await _dio.fetch(error.requestOptions);
                handler.resolve(response);
                return;
              } on DioException catch (retryError) {
                handler.next(retryError);
                return;
              } catch (_) {
                handler.next(error);
                return;
              }
            }
            if (outcome == RefreshOutcome.invalid) {
              await onUnauthorized?.call();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenReader tokenReader;
  final RefreshTokenReader? refreshTokenReader;
  final TokenPairWriter? onTokensRefreshed;
  final UnauthorizedHandler? onUnauthorized;
  Future<RefreshOutcome>? _refreshInFlight;
  Future<void>? _warmupInFlight;
  DateTime? _warmupCompletedAt;

  Future<RefreshOutcome> _refreshSingleFlight() async {
    final active = _refreshInFlight;
    if (active != null) return active;

    final task = _refreshAccessToken();
    _refreshInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_refreshInFlight, task)) _refreshInFlight = null;
    }
  }

  Future<RefreshOutcome> _refreshAccessToken() async {
    final reader = refreshTokenReader;
    final writer = onTokensRefreshed;
    if (reader == null || writer == null) return RefreshOutcome.invalid;

    final refreshToken = await reader();
    if (refreshToken == null || refreshToken.isEmpty) {
      return RefreshOutcome.invalid;
    }

    try {
      final response = await _dio.post(
        '/api/v2/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'skipAuth': true, 'refreshRequest': true}),
      );
      final body = response.data;
      if (body is! Map) return RefreshOutcome.invalid;
      final accessToken = body['token']?.toString().trim();
      final replacement = body['refreshToken']?.toString().trim();
      if (accessToken == null ||
          accessToken.isEmpty ||
          replacement == null ||
          replacement.isEmpty) {
        return RefreshOutcome.invalid;
      }
      await writer(accessToken, replacement);
      return RefreshOutcome.refreshed;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        return RefreshOutcome.invalid;
      }
      return RefreshOutcome.unavailable;
    } catch (_) {
      return RefreshOutcome.unavailable;
    }
  }

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _run(
    () => _dio.get(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  /// Opens the API connection so the next user action can reuse the TCP/TLS
  /// session. Warmup is best-effort and single-flight: concurrent callers
  /// share one request, while a successful request is reused briefly instead
  /// of creating another cold connection.
  Future<void> warmup({bool force = false}) {
    final active = _warmupInFlight;
    if (active != null) return active;

    final completedAt = _warmupCompletedAt;
    if (!force &&
        completedAt != null &&
        DateTime.now().isBefore(completedAt.add(warmupTtl))) {
      return Future<void>.value();
    }

    final task = _runWarmup();
    _warmupInFlight = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_warmupInFlight, task)) _warmupInFlight = null;
      }),
    );
    return task;
  }

  Future<void> _runWarmup() async {
    try {
      await get(
        '/health',
        options: Options(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          extra: const {'skipAuth': true, 'apiWarmup': true},
        ),
      );
      _warmupCompletedAt = DateTime.now();
    } catch (_) {
      // The real request will report the actual connectivity error.
    }
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _run(
    () => _dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _run(
    () => _dio.patch(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<Response<dynamic>> delete(String path) =>
      _run(() => _dio.delete(path));

  Future<Response<dynamic>> download(
    String path,
    String savePath, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    ProgressCallback? onReceiveProgress,
  }) => _run(
    () => _dio.download(
      path,
      savePath,
      queryParameters: queryParameters,
      options: options,
      onReceiveProgress: onReceiveProgress,
    ),
  );

  Future<Response<dynamic>> _run(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw _fromResponse(response);
      }
      return response;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      if (error.response != null) throw _fromResponse(error.response!);
      throw ApiException(
        statusCode: null,
        message: error.message ?? 'Network request failed',
        data: error.type,
      );
    } on ApiException {
      rethrow;
    }
  }

  ApiException _fromResponse(Response<dynamic> response) {
    final body = response.data;
    final message = body is Map<String, dynamic>
        ? body['message']?.toString() ?? body['error']?.toString()
        : null;
    return ApiException(
      statusCode: response.statusCode,
      message: message ?? 'Request failed (${response.statusCode})',
      data: body,
    );
  }
}
