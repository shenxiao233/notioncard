import 'package:flutter_test/flutter_test.dart';

import 'package:kncard_app/core/models/account_model.dart';

void main() {
  test('reads avatar from login and nested profile payloads', () {
    final direct = AccountModel.fromJson({
      'id': 1,
      'username': 'learner',
      'avatar': 'data:image/png;base64,AA==',
    });
    final nested = AccountModel.fromJson({
      'id': 2,
      'username': 'learner',
      'profile': {'avatarUrl': '/uploads/avatar.png'},
    });

    expect(direct.avatar, startsWith('data:image/'));
    expect(nested.avatar, '/uploads/avatar.png');
  });

  test('normalizes account roles for the account page', () {
    final admin = AccountModel.fromJson({
      'id': 'admin-1',
      'username': 'admin',
      'role': 'admin',
    });
    final licensed = AccountModel.fromJson({
      'id': 'user-1',
      'username': 'user',
      'roles': ['user'],
    });
    final nestedAdmin = AccountModel.fromJson({
      'id': 'admin-2',
      'username': 'admin',
      'profile': {'isAdmin': true},
    });

    expect(admin.role, 'admin');
    expect(licensed.role, 'user');
    expect(nestedAdmin.role, 'admin');
  });
}
