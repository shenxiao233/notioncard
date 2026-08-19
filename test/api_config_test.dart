import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/core/network/api_config.dart';

void main() {
  test('uses the current HTTPS API entry point on port 8443', () {
    expect(
      ApiConfig.productionBaseUrl,
      'https://shenxiao.mijiji.cc.cd:8443',
    );
    expect(ApiConfig.defaultBaseUrl, ApiConfig.productionBaseUrl);
  });

  test('resolves relative API paths without dropping the port', () {
    const config = ApiConfig(baseUrl: ApiConfig.productionBaseUrl);

    expect(
      config.endpoint('/api/v2/auth/login').toString(),
      'https://shenxiao.mijiji.cc.cd:8443/api/v2/auth/login',
    );
  });
}
