import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';

typedef TokenReader = Future<String?> Function();
typedef UnauthorizedHandler = Future<void> Function();

class ApiClient {
  ApiClient({
    required ApiConfig config,
    required this.tokenReader,
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
          if (!skipAuth && error.response?.statusCode == 401) {
            await onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenReader tokenReader;
  final UnauthorizedHandler? onUnauthorized;

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
