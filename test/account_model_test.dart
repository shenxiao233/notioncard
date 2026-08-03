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
}
