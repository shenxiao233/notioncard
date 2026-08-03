class ApiConfig {
  const ApiConfig({required this.baseUrl});

  static const defaultBaseUrl = String.fromEnvironment(
    'KN_API_BASE_URL',
    defaultValue: 'http://198.23.232.247',
  );

  final String baseUrl;

  Uri endpoint(String path, [Map<String, dynamic>? queryParameters]) {
    final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(root)
        .resolve(path.replaceFirst('/', ''))
        .replace(queryParameters: queryParameters);
  }
}
