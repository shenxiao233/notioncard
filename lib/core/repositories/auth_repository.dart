import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account_model.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

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

  Future<AccountModel?> login(String username, String password) async {
    final normalizedUsername = username.trim();
    if (apiClient != null) {
      try {
        final response = await apiClient!.post(
          '/api/v2/auth/login',
          data: {'username': normalizedUsername, 'password': password},
        );
        final body = response.data as Map<String, dynamic>;
        final token = body['token']?.toString();
        final user = body['user'];
        if (token == null || user is! Map<String, dynamic>) return null;
        await secureStorage.write(key: tokenKey, value: token);
        final accountJson = Map<String, dynamic>.from(user);
        await _saveAccount(AccountModel.fromJson(accountJson));
        return currentAccount;
      } on ApiException catch (error) {
        if (!error.isNetworkFailure) return null;
      }
    }

    return null;
  }

  Future<AccountModel?> register(
    String username,
    String password,
    String invitationCode,
  ) async {
    final normalizedUsername = username.trim();
    final normalizedInvitationCode = invitationCode.trim();
    if (apiClient == null) return null;
    try {
      final response = await apiClient!.post(
        '/api/v2/auth/register',
        data: {
          'username': normalizedUsername,
          'password': password,
          'invitation_code': normalizedInvitationCode,
        },
      );
      final body = response.data as Map<String, dynamic>;
      final token = body['token']?.toString();
      final user = body['user'];
      if (token == null || user is! Map<String, dynamic>) return null;
      await secureStorage.write(key: tokenKey, value: token);
      await _saveAccount(AccountModel.fromJson(user));
      return currentAccount;
    } on ApiException catch (error) {
      if (!error.isNetworkFailure) return null;
    }
    return null;
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
