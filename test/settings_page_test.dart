import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/core/models/account_model.dart';
import 'package:kncard_app/features/settings/settings_page.dart';

void main() {
  testWidgets('edits and saves the daily new card limit safely', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          currentAccountProvider.overrideWithValue(
            const AccountModel(
              id: 'account-a',
              username: 'tester',
              nickname: 'Tester',
              status: 'ACTIVE',
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);

    final newCardRow = find.ancestor(
      of: find.text('每日新卡上限'),
      matching: find.byType(ListTile),
    );
    await tester.tap(newCardRow);
    await tester.pumpAndSettle();
    expect(find.text('可填写 0 - 9999'), findsOneWidget);

    final input = find.byType(TextField);
    await tester.enterText(input, '42');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('每天最多加入 42 张未学习卡片'), findsOneWidget);
    expect(preferences.getInt('review.new_cards_per_day.account-a'), 42);
  });

  testWidgets('does not close the dialog for an invalid limit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          currentAccountProvider.overrideWithValue(
            const AccountModel(
              id: 'account-a',
              username: 'tester',
              nickname: 'Tester',
              status: 'ACTIVE',
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);

    final reviewRow = find.ancestor(
      of: find.text('每日复习上限'),
      matching: find.byType(ListTile),
    );
    await tester.tap(reviewRow);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请输入 0 到 9999 之间的整数'), findsOneWidget);
    // The label appears in both the settings row and dialog title.
    expect(find.text('每日复习上限'), findsNWidgets(2));
  });
}
