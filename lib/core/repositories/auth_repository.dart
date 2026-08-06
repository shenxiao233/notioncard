import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account_model.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

enum AuthFailureType {
  invalidCredentials,
  network,
  timeout,
  server,
  invalidResponse,
  unknown,
}

class AuthFailure {
  const AuthFailure(this.type, {this.details});

  final AuthFailureType type;
  final String? details;

  String get userMessage => switch (type) {
    AuthFailureType.invalidCredentials => '?????????',
    AuthFailureType.network => '???????????????',
    AuthFailureType.timeout => '??????????',
    AuthFailureType.server => '??????????????',
    AuthFailureType.invalidResponse => '????????????????',
    AuthFailureType.unknown => '??????????',
  };
}

class AuthResult {
  const AuthResult.success(this.account) : failure = null;
  const AuthResult.failure(this.failure) : account = null;

  final AccountModel? account;
  final AuthFailure? failure;

  bool get isSuccess => account != null && failure == null;
}

class AuthRepository {
  AuthRepository(
    this._preferences, {
    this.apiClient,
    this.secureStorage = const FlutterSecureStorage(),
  });

  final SharedPreferences _preferences;
  final ApiClient? apiClient;
  final FlutterSecureStorage secureStorage;

  static const _accountIdKey = 'auth.account_id';
  static const _accountKey = 'auth.account';
  static const tokenKey = 'auth.jwt';

  AccountModel? get currentAccount {
    final raw = _preferences.getString(_accountKey);
    if (raw != null) {
      try {
        return AccountModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  Future<AuthResult> loginResult(String username, String password) {
    return _authenticate(
      path: '/api/v2/auth/login',
      data: {'username': username.trim(), 'password': password},
      isLogin: true,
    );
  }

  Future<AuthResult> registerResult(
    String username,
    String password,
    String invitationCode,
  ) {
    return _authenticate(
      path: '/api/v2/auth/register',
      data: {
        'username': username.trim(),
        'password': password,
        'invitation_code': invitationCode.trim(),
      },
      isLogin: false,
    );
  }

  // Compatibility helpers for callers that only need the account.
  Future<AccountModel?> login(String username, String password) async =>
      (await loginResult(username, password)).account;

  Future<AccountModel?> register(
    String username,
    String password,
    String invitationCode,
  ) async => (await registerResult(username, password, invitationCode)).account;

  Future<AuthResult> _authenticate({
    required String path,
    required Map<String, dynamic> data,
    required bool isLogin,
  }) async {
    final client = apiClient;
    if (client == null) {
      return const AuthResult.failure(AuthFailure(AuthFailureType.unknown));
    }
    try {
      final response = await client.post(path, data: data);
      final rawBody = response.data;
      if (rawBody is! Map) {
        return const AuthResult.failure(
          AuthFailure(AuthFailureType.invalidResponse),
        );
      }
      final body = Map<String, dynamic>.from(rawBody);
      final token = body['token']?.toString().trim();
      final user = body['user'];
      if (token == null || token.isEmpty || user is! Map) {
        return const AuthResult.failure(
          AuthFailure(AuthFailureType.invalidResponse),
        );
      }
      final account = AccountModel.fromJson(Map<String, dynamic>.from(user));
      if (account.id.isEmpty) {
        return const AuthResult.failure(
          AuthFailure(AuthFailureType.invalidResponse),
        );
      }
      await secureStorage.write(key: tokenKey, value: token);
      await _saveAccount(account);
      return AuthResult.success(currentAccount ?? account);
    } on ApiException catch (error) {
      return AuthResult.failure(_classifyFailure(error, isLogin: isLogin));
    }
  }

  AuthFailure _classifyFailure(ApiException error, {required bool isLogin}) {
    if (error.statusCode == 401 || (isLogin && error.statusCode == 400)) {
      return const AuthFailure(AuthFailureType.invalidCredentials);
    }
    if (error.isNetworkFailure) {
      final type = error.data?.toString();
      if (type != null &&
          (type.contains('Timeout') || type.contains('timeout'))) {
        return const AuthFailure(AuthFailureType.timeout);
      }
      return const AuthFailure(AuthFailureType.network);
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return const AuthFailure(AuthFailureType.server);
    }
    return AuthFailure(AuthFailureType.server, details: error.message);
  }

  Future<void> logout() async {
    await secureStorage.delete(key: tokenKey);
    await _preferences.remove(_accountIdKey);
    await _preferences.remove(_accountKey);
  }

  Future<void> clearSession() async {
    await secureStorage.delete(key: tokenKey);
    await _preferences.remove(_accountIdKey);
    await _preferences.remove(_accountKey);
  }

  Future<String?> token() => secureStorage.read(key: tokenKey);

  Future<void> _saveAccount(AccountModel account) async {
    await _preferences.setString(_accountIdKey, account.id);
    await _preferences.setString(
      _accountKey,
      jsonEncode({
        'id': account.id,
        'username': account.username,
        'nickname': account.nickname,
        'status': account.status,
        'avatar': account.avatar,
      }),
    );
  }
}
