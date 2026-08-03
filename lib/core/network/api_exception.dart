class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.message,
    this.data,
  });

  final int? statusCode;
  final String message;
  final Object? data;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetworkFailure => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
