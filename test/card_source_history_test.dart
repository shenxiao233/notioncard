import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/features/cards/card_source_history.dart';

void main() {
  test('converts only long space runs into underscores', () {
    expect(replaceSpacesWithUnderscores('A B  C'), 'A B  C');
    expect(replaceSpacesWithUnderscores('A   B    C'), 'A___B____C');
    expect(replaceSpacesWithUnderscores('already_clean'), 'already_clean');
  });

  test(
    'remembers the last source separately for each account and deck',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final history = CardSourceHistory(preferences);

      expect(history.read(accountId: 'account-a', folder: '数学'), isNull);
      await history.remember(
        accountId: 'account-a',
        folder: '数学',
        source: '高等数学教材',
      );

      expect(history.read(accountId: 'account-a', folder: '数学'), '高等数学教材');
      expect(history.read(accountId: 'account-a', folder: '英语'), isNull);
      expect(history.read(accountId: 'account-b', folder: '数学'), isNull);

      await history.remember(
        accountId: 'account-a',
        folder: '数学',
        source: '期末试卷',
      );
      expect(history.read(accountId: 'account-a', folder: '数学'), '期末试卷');
    },
  );
}
