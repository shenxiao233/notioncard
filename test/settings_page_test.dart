import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/core/models/account_model.dart';
import 'package:kncard_app/features/settings/account_page.dart';
import 'package:kncard_app/features/settings/settings_page.dart';
import 'package:kncard_app/features/settings/settings_preferences_page.dart';

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

  testWidgets('toggles autonomous learning and disables daily limit rows', (
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

    expect(find.text('自主学习'), findsOneWidget);
    expect(find.text('20 张'), findsOneWidget);
    expect(find.text('100 张'), findsOneWidget);

    final autonomousRow = find.ancestor(
      of: find.text('自主学习'),
      matching: find.byType(ListTile),
    );
    await tester.tap(autonomousRow);
    await tester.pumpAndSettle();

    expect(find.text('不限制'), findsNWidgets(2));
    expect(find.text('自主学习已开启，不限制每日新词数量'), findsOneWidget);
    expect(find.text('自主学习已开启，不限制每日复习数量'), findsOneWidget);
    expect(preferences.getBool('review.autonomous_learning.account-a'), isTrue);
  });

  testWidgets('removes secondary cards from the personal page', (tester) async {
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

    expect(find.text('学习是一场马拉松'), findsNothing);
    expect(find.text('应用更新'), findsNothing);
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('同步'), findsOneWidget);
  });

  testWidgets('renders the standalone settings page', (tester) async {
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
        child: const MaterialApp(home: SettingsPreferencesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('Tester'), findsOneWidget);
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('renders account editing controls on the account page', (
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
        child: const MaterialApp(home: AccountPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账号'), findsOneWidget);
    expect(find.text('点击更换头像'), findsNothing);
    expect(find.text('移除头像'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('账号 ID'), findsOneWidget);
    expect(find.text('账户类型'), findsOneWidget);
    expect(find.text('许可用户'), findsOneWidget);
    expect(find.text('昵称'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    expect(find.byType(Icon), findsNWidgets(2));

    final title = tester.widget<Text>(find.text('账号'));
    expect(title.style?.fontFamily, 'NotoSerifSC');
  });
}
