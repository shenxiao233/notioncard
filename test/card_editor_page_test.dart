import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/app/app_providers.dart';
import 'package:kncard_app/core/models/account_model.dart';
import 'package:kncard_app/features/cards/card_source_history.dart';
import 'package:kncard_app/features/cards/card_editor_page.dart';

void main() {
  testWidgets('standalone card editor exposes the card type choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardsProvider.overrideWith((ref) async => const []),
          collectionsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: CardEditorPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择卡片类型'), findsOneWidget);
    expect(find.text('单选题'), findsOneWidget);
    expect(find.text('多选题'), findsOneWidget);
    expect(find.text('速记词条'), findsOneWidget);

    await tester.tap(find.text('多选题'));
    await tester.pumpAndSettle();
    expect(find.text('请选择正确答案（可选择多个）'), findsOneWidget);

    await tester.tap(find.text('速记词条'));
    await tester.pumpAndSettle();
    expect(find.text('内容'), findsOneWidget);
    expect(find.text('这是速记词条的正文，复习时会作为词条背面内容展示。'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('笔记（可选）'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('笔记（可选）'), findsOneWidget);
    expect(find.text('请选择正确答案（可选择多个）'), findsNothing);
  });

  testWidgets('preview opens without leaving the editor', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardsProvider.overrideWith((ref) async => const []),
          collectionsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: CardEditorPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, '示例题目');
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();

    expect(find.text('卡片预览'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('示例题目')),
      findsOneWidget,
    );
  });

  testWidgets('offers the last source for the selected deck', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await CardSourceHistory(preferences).remember(
      accountId: 'account-source-test',
      folder: 'Deck A',
      source: 'Book Chapter 1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          currentAccountProvider.overrideWithValue(
            const AccountModel(
              id: 'account-source-test',
              username: 'tester',
              nickname: 'Tester',
              status: 'ACTIVE',
            ),
          ),
          cardsProvider.overrideWith((ref) async => const []),
          collectionsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: CardEditorPage(initialFolder: 'Deck A')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('Book Chapter 1'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    final recentSourceChip = find.ancestor(
      of: find.textContaining('Book Chapter 1'),
      matching: find.byType(ActionChip),
    );
    expect(recentSourceChip, findsOneWidget);
    tester.widget<ActionChip>(recentSourceChip).onPressed!();
    await tester.pump();
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((field) => field.controller.text == 'Book Chapter 1'),
      isTrue,
    );
  });
}
