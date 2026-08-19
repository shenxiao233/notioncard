class ApiConfig {
  const ApiConfig({required this.baseUrl});

  // The API is intentionally exposed on 8443. Port 443 is owned by another
  // service on the VPS and is not the application API entry point.
  static const productionBaseUrl = 'https://shenxiao.mijiji.cc.cd:8443';

  static const defaultBaseUrl = String.fromEnvironment(
    'KN_API_BASE_URL',
    defaultValue: productionBaseUrl,
  );

  final String baseUrl;

  Uri endpoint(String path, [Map<String, dynamic>? queryParameters]) {
    final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(root)
        .resolve(path.replaceFirst('/', ''))
        .replace(queryParameters: queryParameters);
  }
}
